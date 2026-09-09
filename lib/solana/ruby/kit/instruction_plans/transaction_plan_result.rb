# typed: strict
# frozen_string_literal: true

require_relative '../errors'
require_relative '../transaction_messages/transaction_message'
require_relative '../transactions/transaction'

module Solana::Ruby::Kit
  module InstructionPlans
    extend T::Sig

    # ── Result status types ───────────────────────────────────────────────────
    #
    # Each single transaction produces one of three statuses:
    #   successful: { kind: :successful, transaction:, context: }
    #   failed:     { kind: :failed,     error:, context: }
    #   canceled:   { kind: :canceled,   context: }
    #
    # Every status carries a context, so whatever the executor callback recorded
    # before it failed — or before an earlier failure canceled it — survives into
    # the result. Mirrors TypeScript's TransactionPlanResultStatus union.

    class SuccessfulStatus < T::Struct
      extend T::Sig

      const :transaction, T.nilable(Transactions::Transaction)
      const :context,     T::Hash[T.untyped, T.untyped]
      sig { returns(Symbol) }
      def kind = :successful
    end

    class FailedStatus < T::Struct
      extend T::Sig

      const :error,   SolanaError
      const :context, T::Hash[T.untyped, T.untyped], default: {}.freeze
      sig { returns(Symbol) }
      def kind = :failed
    end

    class CanceledStatus < T::Struct
      extend T::Sig

      const :context, T::Hash[T.untyped, T.untyped], default: {}.freeze
      sig { returns(Symbol) }
      def kind = :canceled
    end

    # ── Result plan types ──────────────────────────────────────────────────────

    class SingleTransactionPlanResult < T::Struct
      extend T::Sig

      const :message, TransactionMessages::TransactionMessage
      const :status,  T.untyped  # SuccessfulStatus | FailedStatus | CanceledStatus
      sig { returns(Symbol) }
      def kind = :single
    end

    class SequentialTransactionPlanResult < T::Struct
      extend T::Sig

      const :plans,     T::Array[T.untyped]  # Array[TransactionPlanResult]
      const :divisible, T::Boolean
      sig { returns(Symbol) }
      def kind = :sequential
    end

    class ParallelTransactionPlanResult < T::Struct
      extend T::Sig

      const :plans, T::Array[T.untyped]  # Array[TransactionPlanResult]
      sig { returns(Symbol) }
      def kind = :parallel
    end

    extend self

    # ── Result factory helpers ────────────────────────────────────────────────

    # Mirrors `sequentialTransactionPlanResult(plans)`.
    sig { params(plans: T::Array[T.untyped]).returns(SequentialTransactionPlanResult) }
    def sequential_transaction_plan_result(plans)
      SequentialTransactionPlanResult.new(plans: plans, divisible: true)
    end

    # Mirrors `nonDivisibleSequentialTransactionPlanResult(plans)`.
    sig { params(plans: T::Array[T.untyped]).returns(SequentialTransactionPlanResult) }
    def non_divisible_sequential_transaction_plan_result(plans)
      SequentialTransactionPlanResult.new(plans: plans, divisible: false)
    end

    # Mirrors `parallelTransactionPlanResult(plans)`.
    sig { params(plans: T::Array[T.untyped]).returns(ParallelTransactionPlanResult) }
    def parallel_transaction_plan_result(plans)
      ParallelTransactionPlanResult.new(plans: plans)
    end

    # Mirrors `successfulSingleTransactionPlanResult(message, context)`.
    #
    # Upstream carries the transaction inside the context; Ruby keeps the separate
    # +transaction+ reader it has always exposed. Pass it either way — as the positional
    # argument, or under +:transaction+ in the context, where the reader picks it up.
    # Nothing is written back into the context, which stays exactly what was passed.
    sig do
      params(
        message:     TransactionMessages::TransactionMessage,
        transaction: T.nilable(Transactions::Transaction),
        context:     T::Hash[T.untyped, T.untyped]
      ).returns(SingleTransactionPlanResult)
    end
    def successful_single_transaction_plan_result(message, transaction = nil, context = {})
      from_context = context[:transaction]
      transaction ||= from_context if from_context.is_a?(Transactions::Transaction)

      SingleTransactionPlanResult.new(
        message: message,
        status:  SuccessfulStatus.new(transaction: transaction, context: context.dup.freeze)
      )
    end

    # Mirrors `failedSingleTransactionPlanResult(message, error, context)`.
    sig do
      params(
        message: TransactionMessages::TransactionMessage,
        error:   SolanaError,
        context: T::Hash[T.untyped, T.untyped]
      ).returns(SingleTransactionPlanResult)
    end
    def failed_single_transaction_plan_result(message, error, context = {})
      SingleTransactionPlanResult.new(
        message: message,
        status:  FailedStatus.new(error: error, context: context.dup.freeze)
      )
    end

    # Mirrors `canceledSingleTransactionPlanResult(message, context)`.
    sig do
      params(
        message: TransactionMessages::TransactionMessage,
        context: T::Hash[T.untyped, T.untyped]
      ).returns(SingleTransactionPlanResult)
    end
    def canceled_single_transaction_plan_result(message, context = {})
      SingleTransactionPlanResult.new(
        message: message,
        status:  CanceledStatus.new(context: context.dup.freeze)
      )
    end
  end
end
