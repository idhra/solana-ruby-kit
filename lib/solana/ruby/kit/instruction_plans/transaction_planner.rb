# typed: strict
# frozen_string_literal: true

require_relative '../errors'
require_relative '../transaction_messages/transaction_message'
require_relative '../transactions/compiler'
require_relative 'instruction_plan'
require_relative 'transaction_plan'

module Solana::Ruby::Kit
  module InstructionPlans
    extend T::Sig

    extend self

    # Creates a TransactionPlanner — a callable that converts an InstructionPlan
    # into a TransactionPlan by packing instructions into transaction messages.
    #
    # Configuration:
    #   create_transaction_message: -> { TransactionMessage }
    #     Called whenever a new (empty) message is needed. Must return a message
    #     with at least a fee payer and blockhash already set.
    #
    #   on_transaction_message_updated: ->(message) { TransactionMessage }  (optional)
    #     Called after instructions are appended to a message. Must return the
    #     (possibly further updated) message. Defaults to identity.
    #
    #   max_instructions_per_transaction: Integer  (optional)
    #     Maximum number of top-level instructions allowed in each planned transaction.
    #     Must be a positive integer no greater than 64. Defaults to 16. Can be overridden
    #     per-call via the returned planner's `max_instructions_per_transaction:` kwarg.
    #
    # The returned planner is a lambda:
    #   planner.call(instruction_plan, max_instructions_per_transaction: nil) -> TransactionPlan
    #
    # Mirrors `createTransactionPlanner(config)` from @solana/instruction-plans.
    # NOTE: Ruby translation is synchronous; abort-signal support is omitted.
    sig do
      params(
        create_transaction_message:        T.untyped,
        on_transaction_message_updated:    T.untyped,
        max_instructions_per_transaction:  T.nilable(Integer)
      ).returns(T.untyped)
    end
    def create_transaction_planner(
      create_transaction_message:,
      on_transaction_message_updated: ->(msg) { msg },
      max_instructions_per_transaction: nil
    )
      ctx = {
        create_transaction_message:     create_transaction_message,
        on_transaction_message_updated: on_transaction_message_updated
      }
      config_max_instructions_per_transaction = max_instructions_per_transaction

      ->(instruction_plan, max_instructions_per_transaction: nil) {
        resolved_max = max_instructions_per_transaction || config_max_instructions_per_transaction

        # Reject up front any configured maximum the transaction format could never satisfy,
        # rather than discovering it mid-plan when a message fails to compile.
        InstructionPlans.assert_valid_max_instructions_per_transaction(resolved_max)

        mutable = planner_traverse(
          instruction_plan,
          ctx.merge(parent: nil, parent_candidates: [], max_instructions_per_transaction: resolved_max)
        )
        Kernel.raise SolanaError.new(SolanaError::INSTRUCTION_PLANS__EMPTY_INSTRUCTION_PLAN) unless mutable
        planner_freeze(mutable)
      }
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    extend self

    sig { params(plan: T.untyped, ctx: T.untyped).returns(T.untyped) }

    def planner_traverse(plan, ctx)
      case plan.kind
      when :sequential     then planner_traverse_sequential(plan, ctx)
      when :parallel       then planner_traverse_parallel(plan, ctx)
      when :single         then planner_traverse_single(plan, ctx)
      when :message_packer then planner_traverse_message_packer(plan, ctx)
      else
        Kernel.raise SolanaError.new(
          SolanaError::INVARIANT_VIOLATION__INVALID_INSTRUCTION_PLAN_KIND,
          { kind: plan.kind }
        )
      end
    end

    sig { params(plan: T.untyped, ctx: T.untyped).returns(T.untyped) }

    def planner_traverse_sequential(plan, ctx)
      must_fit_in_parent = ctx[:parent] && (ctx[:parent].kind == :parallel || !plan.divisible)

      if must_fit_in_parent
        candidate = planner_select_and_mutate_candidate(ctx, ctx[:parent_candidates]) do |msg|
          planner_fit_entire_plan(plan, msg, ctx)
        end
        return nil if candidate
      end

      candidate = (!must_fit_in_parent && !ctx[:parent_candidates].empty?) ? ctx[:parent_candidates][0] : nil
      tx_plans  = []

      plan.plans.each do |sub_plan|
        sub_ctx = ctx.merge(parent: plan, parent_candidates: candidate ? [candidate] : [])
        tx_plan = planner_traverse(sub_plan, sub_ctx)
        next unless tx_plan

        candidate = planner_get_sequential_candidate(tx_plan)
        new_plans =
          tx_plan[:kind] == :sequential && (tx_plan[:divisible] || !plan.divisible) \
            ? tx_plan[:plans] \
            : [tx_plan]
        tx_plans.concat(new_plans)
      end

      return nil          if tx_plans.empty?
      return tx_plans[0]  if tx_plans.length == 1
      { kind: :sequential, divisible: plan.divisible, plans: tx_plans }
    end

    sig { params(plan: T.untyped, ctx: T.untyped).returns(T.untyped) }

    def planner_traverse_parallel(plan, ctx)
      candidates = ctx[:parent_candidates].dup
      tx_plans   = []

      sorted = plan.plans.sort_by { |p| p.kind == :message_packer ? 1 : 0 }

      sorted.each do |sub_plan|
        sub_ctx = ctx.merge(parent: plan, parent_candidates: candidates)
        tx_plan = planner_traverse(sub_plan, sub_ctx)
        next unless tx_plan

        candidates.concat(planner_get_parallel_candidates(tx_plan))
        new_plans = tx_plan[:kind] == :parallel ? tx_plan[:plans] : [tx_plan]
        tx_plans.concat(new_plans)
      end

      return nil          if tx_plans.empty?
      return tx_plans[0]  if tx_plans.length == 1
      { kind: :parallel, plans: tx_plans }
    end

    sig { params(plan: T.untyped, ctx: T.untyped).returns(T.untyped) }

    def planner_traverse_single(plan, ctx)
      predicate = ->(msg) { TransactionMessages.append_instructions(msg, [plan.instruction]) }
      candidate = planner_select_and_mutate_candidate(ctx, ctx[:parent_candidates], &predicate)
      return nil if candidate

      msg = planner_create_new_message(ctx, &predicate)
      { kind: :single, message: msg }
    end

    sig { params(plan: T.untyped, ctx: T.untyped).returns(T.untyped) }

    def planner_traverse_message_packer(plan, ctx)
      packer     = plan.get_message_packer.call
      tx_plans   = []
      candidates = ctx[:parent_candidates].dup

      until packer.done?
        predicate = ->(msg) { packer.pack_message_to_capacity(msg, max_instructions: ctx[:max_instructions_per_transaction]) }
        candidate = planner_select_and_mutate_candidate(ctx, candidates, &predicate)
        unless candidate
          msg      = planner_create_new_message(ctx, &predicate)
          new_plan = { kind: :single, message: msg }
          tx_plans << new_plan
          candidates << new_plan
        end
      end

      return nil          if tx_plans.empty?
      return tx_plans[0]  if tx_plans.length == 1

      if ctx[:parent]&.kind == :parallel
        { kind: :parallel, plans: tx_plans }
      else
        divisible = ctx[:parent]&.kind == :sequential ? ctx[:parent].divisible : true
        { kind: :sequential, divisible: divisible, plans: tx_plans }
      end
    end

    sig { params(ctx: T.untyped, candidates: T.untyped, predicate: T.proc.params(arg0: T.untyped).returns(T.untyped)).returns(T.untyped) }

    def planner_select_and_mutate_candidate(ctx, candidates, &predicate)
      candidates.each do |candidate|
        begin
          updated = ctx[:on_transaction_message_updated].call(predicate.call(candidate[:message]))
          if Transactions.get_transaction_message_size(updated) <= Transactions::TRANSACTION_SIZE_LIMIT
            InstructionPlans.assert_max_instructions_per_transaction(
              updated.instructions.length,
              InstructionPlans.resolve_max_instructions(ctx[:max_instructions_per_transaction])
            )
            candidate[:message] = updated
            return candidate
          end
        rescue SolanaError => e
          next if [
            SolanaError::INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN,
            SolanaError::INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED
          ].include?(e.code)
          Kernel.raise
        end
      end
      nil
    end

    sig { params(ctx: T.untyped, predicate: T.proc.params(arg0: T.untyped).returns(T.untyped)).returns(T.untyped) }

    def planner_create_new_message(ctx, &predicate)
      new_msg      = ctx[:create_transaction_message].call
      updated_msg  = ctx[:on_transaction_message_updated].call(predicate.call(new_msg))
      updated_size = Transactions.get_transaction_message_size(updated_msg)

      if updated_size > Transactions::TRANSACTION_SIZE_LIMIT
        new_size = Transactions.get_transaction_message_size(new_msg)
        Kernel.raise SolanaError.new(
          SolanaError::INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN,
          { num_bytes_required: updated_size - new_size,
            num_free_bytes:     Transactions::TRANSACTION_SIZE_LIMIT - new_size }
        )
      end

      InstructionPlans.assert_max_instructions_per_transaction(
        updated_msg.instructions.length,
        InstructionPlans.resolve_max_instructions(ctx[:max_instructions_per_transaction])
      )

      updated_msg
    end

    sig { params(plan: T.untyped, message: T.untyped, ctx: T.untyped).returns(T.untyped) }

    def planner_fit_entire_plan(plan, message, ctx)
      case plan.kind
      when :sequential, :parallel
        plan.plans.reduce(message) { |msg, sub| planner_fit_entire_plan(sub, msg, ctx) }
      when :single
        updated  = TransactionMessages.append_instructions(message, [plan.instruction])
        new_size = Transactions.get_transaction_message_size(updated)
        if new_size > Transactions::TRANSACTION_SIZE_LIMIT
          base_size = Transactions.get_transaction_message_size(message)
          Kernel.raise SolanaError.new(
            SolanaError::INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN,
            { num_bytes_required: new_size - base_size,
              num_free_bytes:     Transactions::TRANSACTION_SIZE_LIMIT - base_size }
          )
        end
        InstructionPlans.assert_max_instructions_per_transaction(
          updated.instructions.length,
          InstructionPlans.resolve_max_instructions(ctx[:max_instructions_per_transaction])
        )
        updated
      when :message_packer
        packer = plan.get_message_packer.call
        msg    = message
        until packer.done?
          msg = packer.pack_message_to_capacity(msg, max_instructions: ctx[:max_instructions_per_transaction])
          InstructionPlans.assert_max_instructions_per_transaction(
            msg.instructions.length,
            InstructionPlans.resolve_max_instructions(ctx[:max_instructions_per_transaction])
          )
        end
        msg
      else
        Kernel.raise SolanaError.new(
          SolanaError::INVARIANT_VIOLATION__INVALID_INSTRUCTION_PLAN_KIND,
          { kind: plan.kind }
        )
      end
    end

    sig { params(plan: T.untyped).returns(T.untyped) }

    def planner_get_sequential_candidate(plan)
      return plan if plan[:kind] == :single
      return nil  unless plan[:kind] == :sequential && plan[:plans]&.any?
      planner_get_sequential_candidate(plan[:plans].last)
    end

    sig { params(plan: T.untyped).returns(T.untyped) }

    def planner_get_parallel_candidates(plan)
      return [plan] if plan[:kind] == :single
      (plan[:plans] || []).flat_map { |p| planner_get_parallel_candidates(p) }
    end

    sig { params(plan: T.untyped).returns(T.untyped) }

    def planner_freeze(plan)
      case plan[:kind]
      when :single
        single_transaction_plan(plan[:message])
      when :sequential
        frozen_plans = plan[:plans].map { |p| planner_freeze(p) }
        plan[:divisible] \
          ? sequential_transaction_plan(frozen_plans) \
          : non_divisible_sequential_transaction_plan(frozen_plans)
      when :parallel
        parallel_transaction_plan(plan[:plans].map { |p| planner_freeze(p) })
      else
        Kernel.raise SolanaError.new(
          SolanaError::INVARIANT_VIOLATION__INVALID_TRANSACTION_PLAN_KIND,
          { kind: plan[:kind] }
        )
      end
    end

    private_class_method :planner_traverse
    private_class_method :planner_traverse_sequential
    private_class_method :planner_traverse_parallel
    private_class_method :planner_traverse_single
    private_class_method :planner_traverse_message_packer
    private_class_method :planner_select_and_mutate_candidate
    private_class_method :planner_create_new_message
    private_class_method :planner_fit_entire_plan
    private_class_method :planner_get_sequential_candidate
    private_class_method :planner_get_parallel_candidates
    private_class_method :planner_freeze
  end
end
