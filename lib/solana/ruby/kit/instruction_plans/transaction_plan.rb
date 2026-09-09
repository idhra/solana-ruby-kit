# typed: strict
# frozen_string_literal: true

require_relative '../transaction_messages/transaction_message'

module Solana::Ruby::Kit
  module InstructionPlans
    extend T::Sig

    # ── Transaction plan types ────────────────────────────────────────────────
    #
    # A TransactionPlan is a recursive tree of compiled transaction messages that
    # mirrors the structure of an InstructionPlan after the planner has resolved it.
    #
    #   TransactionPlan = SingleTransactionPlan
    #                   | SequentialTransactionPlan
    #                   | ParallelTransactionPlan

    class SingleTransactionPlan < T::Struct
      extend T::Sig

      const :message, TransactionMessages::TransactionMessage
      sig { returns(Symbol) }
      def kind = :single
    end

    class SequentialTransactionPlan < T::Struct
      extend T::Sig

      const :plans,     T::Array[T.untyped]  # Array[TransactionPlan]
      const :divisible, T::Boolean
      sig { returns(Symbol) }
      def kind = :sequential
    end

    class ParallelTransactionPlan < T::Struct
      extend T::Sig

      const :plans, T::Array[T.untyped]  # Array[TransactionPlan]
      sig { returns(Symbol) }
      def kind = :parallel
    end

    extend self

    # Creates a single-message plan.
    # Mirrors `singleTransactionPlan(transactionMessage)`.
    sig { params(message: TransactionMessages::TransactionMessage).returns(SingleTransactionPlan) }
    def single_transaction_plan(message)
      SingleTransactionPlan.new(message: message)
    end

    # Creates a divisible sequential plan.
    # Accepts TransactionMessage objects directly (wraps them automatically).
    # Mirrors `sequentialTransactionPlan(plans)`.
    sig { params(plans: T::Array[T.untyped]).returns(SequentialTransactionPlan) }
    def sequential_transaction_plan(plans)
      SequentialTransactionPlan.new(plans: parse_single_transaction_plans(plans), divisible: true)
    end

    # Creates a non-divisible sequential plan.
    # Mirrors `nonDivisibleSequentialTransactionPlan(plans)`.
    sig { params(plans: T::Array[T.untyped]).returns(SequentialTransactionPlan) }
    def non_divisible_sequential_transaction_plan(plans)
      SequentialTransactionPlan.new(plans: parse_single_transaction_plans(plans), divisible: false)
    end

    # Creates a parallel plan.
    # Accepts TransactionMessage objects directly (wraps them automatically).
    # Mirrors `parallelTransactionPlan(plans)`.
    sig { params(plans: T::Array[T.untyped]).returns(ParallelTransactionPlan) }
    def parallel_transaction_plan(plans)
      ParallelTransactionPlan.new(plans: parse_single_transaction_plans(plans))
    end

    # Recursively collects all SingleTransactionPlan leaves from a plan tree.
    # Mirrors `getAllSingleTransactionPlans(transactionPlan)`.
    sig { params(plan: T.untyped).returns(T::Array[SingleTransactionPlan]) }
    def get_all_single_transaction_plans(plan)
      case plan
      when SingleTransactionPlan
        [plan]
      when SequentialTransactionPlan, ParallelTransactionPlan
        plan.plans.flat_map { |p| get_all_single_transaction_plans(p) }
      else
        Kernel.raise ArgumentError, "Unknown TransactionPlan type: #{plan.class}"
      end
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    sig { params(items: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
    def parse_single_transaction_plans(items)
      items.map do |item|
        item.is_a?(TransactionMessages::TransactionMessage) ? single_transaction_plan(item) : item
      end
    end
    private_class_method :parse_single_transaction_plans
  end
end
