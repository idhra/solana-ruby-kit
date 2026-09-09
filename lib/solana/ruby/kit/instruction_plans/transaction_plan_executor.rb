# typed: strict
# frozen_string_literal: true

require_relative '../errors'
require_relative 'transaction_plan'
require_relative 'transaction_plan_result'

module Solana::Ruby::Kit
  module InstructionPlans
    extend T::Sig

    extend self

    # Creates a TransactionPlanExecutor — a callable that traverses a TransactionPlan,
    # executing each single transaction message and collecting results.
    #
    # Configuration:
    #   execute_transaction_message: ->(context, message) { context_to_report }
    #     Called once per SingleTransactionPlan with a fresh, mutable +context+ Hash and
    #     the transaction message to execute. Store data on +context+ as execution
    #     progresses, and return the context a successful result should carry. The two
    #     serve different outcomes: what you *store* reaches a failed or canceled result,
    #     what you *return* reaches a successful one. On success the returned Hash is
    #     merged over the stored one, the returned value winning, so anything recorded
    #     but left out of the return value is still reported.
    #
    #     Raise a SolanaError to signal failure; remaining plans will be canceled. The
    #     context accumulated up to the point of failure is preserved on the resulting
    #     failed result, which is useful for debugging or building recovery plans.
    #
    #     A one-argument callable is still accepted for backwards compatibility with the
    #     shape this method used to require — `->(message) { { transaction:, context: } }`
    #     — and is adapted onto the context flow above.
    #
    # The returned executor is a lambda: executor.call(transaction_plan) -> TransactionPlanResult
    #
    # Mirrors `createTransactionPlanExecutor(config)` from @solana/instruction-plans.
    # NOTE: Ruby translation is synchronous; abort-signal support is omitted.
    sig { params(execute_transaction_message: T.untyped).returns(T.untyped) }
    def create_transaction_plan_executor(execute_transaction_message:)
      ->(transaction_plan) {
        state  = { canceled: false }
        result = executor_traverse(transaction_plan, execute_transaction_message, state)

        if state[:canceled]
          cause = executor_find_error(result)
          err   = SolanaError.new(
            SolanaError::INSTRUCTION_PLANS__FAILED_TO_EXECUTE_TRANSACTION_PLAN,
            { cause: cause }
          )
          # Store the full result tree as a non-enumerable attribute for recovery.
          err.instance_variable_set(:@transaction_plan_result, result)
          err.define_singleton_method(:transaction_plan_result) { result }
          Kernel.raise err
        end

        result
      }
    end

    # Creates a TransactionPlanExecutor that processes every leaf concurrently.
    #
    # It takes the same configuration as +create_transaction_plan_executor+ and its
    # +execute_transaction_message+ callback follows the same contract: it receives a fresh
    # mutable +context+ Hash for every leaf and returns the Hash a successful result should
    # carry. On success the two are merged with the returned value winning; when the callback
    # raises, the context accumulated so far is preserved on the failed result. The legacy
    # one-argument callable shape is accepted here too.
    #
    # The difference is the traversal. This executor preserves the input plan's nesting, order
    # and divisibility in the returned result, but it does not enforce the execution
    # dependencies expressed by sequential plans: every leaf is started immediately, each on
    # its own thread, with no concurrency limit. That makes it suitable for work that can be
    # performed independently, such as signing or serializing transactions. For the same
    # reason a callback that raises does not cancel the other leaves — each one runs to
    # completion — and non-divisible sequential plans are supported rather than rejected.
    #
    # Once every leaf has settled, a result tree containing any failure raises
    # INSTRUCTION_PLANS__FAILED_TO_EXECUTE_TRANSACTION_PLAN carrying the complete tree on its
    # +transaction_plan_result+ reader.
    #
    # Because each leaf runs on its own thread, the callback must be safe to run concurrently
    # with itself. Each leaf gets its own context Hash, so the contexts do not need guarding,
    # but anything the callback shares between invocations does.
    #
    # Mirrors `createTransactionPlanExecutorWithConcurrentLeaves(config)` from
    # @solana/instruction-plans.
    # NOTE: Ruby translation has no abort signal; leaves are never canceled, only failed.
    sig { params(execute_transaction_message: T.untyped).returns(T.untyped) }
    def create_transaction_plan_executor_with_concurrent_leaves(execute_transaction_message:)
      ->(transaction_plan) {
        # Traversal spawns every leaf's thread on the way down and returns a tree of thunks;
        # resolving them afterwards is what joins the threads, so all leaves are already in
        # flight before the first one is waited on.
        result = concurrent_executor_traverse(transaction_plan, execute_transaction_message).call

        cause = executor_find_error(result)
        if cause
          err = SolanaError.new(
            SolanaError::INSTRUCTION_PLANS__FAILED_TO_EXECUTE_TRANSACTION_PLAN,
            { cause: cause }
          )
          err.instance_variable_set(:@transaction_plan_result, result)
          err.define_singleton_method(:transaction_plan_result) { result }
          Kernel.raise err
        end

        result
      }
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    extend self

    sig { params(plan: T.untyped, execute_fn: T.untyped, state: T.untyped).returns(T.untyped) }

    def executor_traverse(plan, execute_fn, state)
      case plan.kind
      when :sequential then executor_traverse_sequential(plan, execute_fn, state)
      when :parallel   then executor_traverse_parallel(plan, execute_fn, state)
      when :single     then executor_traverse_single(plan, execute_fn, state)
      else
        Kernel.raise SolanaError.new(
          SolanaError::INVARIANT_VIOLATION__INVALID_TRANSACTION_PLAN_KIND,
          { kind: plan.kind }
        )
      end
    end

    sig { params(plan: T.untyped, execute_fn: T.untyped, state: T.untyped).returns(T.untyped) }

    def executor_traverse_sequential(plan, execute_fn, state)
      results = plan.plans.map { |sub| executor_traverse(sub, execute_fn, state) }
      plan.divisible \
        ? sequential_transaction_plan_result(results) \
        : non_divisible_sequential_transaction_plan_result(results)
    end

    sig { params(plan: T.untyped, execute_fn: T.untyped, state: T.untyped).returns(T.untyped) }

    def executor_traverse_parallel(plan, execute_fn, state)
      results = plan.plans.map { |sub| executor_traverse(sub, execute_fn, state) }
      parallel_transaction_plan_result(results)
    end

    sig { params(plan: T.untyped, execute_fn: T.untyped, state: T.untyped).returns(T.untyped) }

    def executor_traverse_single(plan, execute_fn, state)
      # A fresh context per single transaction plan. Nothing is populated yet — filling
      # it in is the callback's job, which is what lets a partial context survive an error.
      context = {}
      return canceled_single_transaction_plan_result(plan.message, context) if state[:canceled]

      begin
        returned = executor_invoke(execute_fn, context, plan.message)
        # The callback told us what the successful result should carry, so take it as-is
        # and derive nothing from it. Anything it stored but left out of the return value
        # is kept, since dropping it would lose data it deliberately recorded.
        successful_single_transaction_plan_result(plan.message, nil, context.merge(returned))
      rescue SolanaError => e
        state[:canceled] = true
        failed_single_transaction_plan_result(plan.message, e, context)
      rescue => e
        state[:canceled] = true
        wrapped = SolanaError.new(
          SolanaError::INSTRUCTION_PLANS__FAILED_TO_EXECUTE_TRANSACTION_PLAN,
          { cause: e }
        )
        failed_single_transaction_plan_result(plan.message, wrapped, context)
      end
    end

    # Calls the configured callback, adapting the legacy one-argument shape onto the
    # context flow. Returns the Hash the successful result should carry.
    sig do
      params(
        execute_fn: T.untyped,
        context:    T::Hash[T.untyped, T.untyped],
        message:    TransactionMessages::TransactionMessage
      ).returns(T::Hash[T.untyped, T.untyped])
    end
    def executor_invoke(execute_fn, context, message)
      unless execute_fn.arity == 1
        returned = execute_fn.call(context, message)
        return returned.is_a?(Hash) ? returned : {}
      end

      # Legacy shape: `->(message) { { transaction:, context: } }`. There is no mutable
      # context to record into, so everything it reports arrives at once on the way out.
      legacy      = execute_fn.call(message)
      legacy      = {} unless legacy.is_a?(Hash)
      returned    = legacy.fetch(:context, {}).dup
      transaction = legacy[:transaction]
      returned[:transaction] = transaction if transaction
      returned
    end

    # Returns a thunk that resolves to this plan's result. Leaf threads are started as the
    # tree is walked, so the whole plan is in flight by the time the outermost thunk is called.
    sig { params(plan: T.untyped, execute_fn: T.untyped).returns(T.untyped) }

    def concurrent_executor_traverse(plan, execute_fn)
      case plan.kind
      when :single
        thread = Thread.new { concurrent_executor_execute_single(plan, execute_fn) }
        -> { thread.value }
      when :sequential, :parallel
        thunks = plan.plans.map { |sub| concurrent_executor_traverse(sub, execute_fn) }
        Kernel.lambda do
          results = thunks.map(&:call)
          if plan.kind == :parallel
            parallel_transaction_plan_result(results)
          elsif plan.divisible
            sequential_transaction_plan_result(results)
          else
            # Unlike the sequential executor, non-divisible plans are supported: nothing
            # about running every leaf independently depends on the plan being divisible.
            non_divisible_sequential_transaction_plan_result(results)
          end
        end
      else
        Kernel.raise SolanaError.new(
          SolanaError::INVARIANT_VIOLATION__INVALID_TRANSACTION_PLAN_KIND,
          { kind: plan.kind }
        )
      end
    end

    # Runs one leaf. Identical to +executor_traverse_single+ except that a failure is recorded
    # and nothing else — there is no shared cancellation state for it to trip.
    sig { params(plan: T.untyped, execute_fn: T.untyped).returns(T.untyped) }

    def concurrent_executor_execute_single(plan, execute_fn)
      context = {}

      begin
        returned = executor_invoke(execute_fn, context, plan.message)
        successful_single_transaction_plan_result(plan.message, nil, context.merge(returned))
      rescue SolanaError => e
        failed_single_transaction_plan_result(plan.message, e, context)
      rescue => e
        wrapped = SolanaError.new(
          SolanaError::INSTRUCTION_PLANS__FAILED_TO_EXECUTE_TRANSACTION_PLAN,
          { cause: e }
        )
        failed_single_transaction_plan_result(plan.message, wrapped, context)
      end
    end

    sig { params(result: T.untyped).returns(T.untyped) }

    def executor_find_error(result)
      return result.status.error if result.kind == :single && result.status.kind == :failed
      return nil                 if result.kind == :single

      result.plans.each do |sub|
        err = executor_find_error(sub)
        return err if err
      end
      nil
    end

    private_class_method :executor_traverse
    private_class_method :executor_traverse_sequential
    private_class_method :executor_traverse_parallel
    private_class_method :executor_traverse_single
    private_class_method :executor_invoke
    private_class_method :executor_find_error
    private_class_method :concurrent_executor_traverse
    private_class_method :concurrent_executor_execute_single
  end
end
