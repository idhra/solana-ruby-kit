# typed: strict
# frozen_string_literal: true

require_relative '../errors'
require_relative '../instructions/instruction'
require_relative '../transaction_messages/transaction_message'
require_relative '../transactions/compiler'
require_relative 'max_instructions'

module Solana::Ruby::Kit
  module InstructionPlans
    extend T::Sig

    # ── Plan types ─────────────────────────────────────────────────────────────
    #
    # InstructionPlan is a recursive tree that describes operations which may
    # span multiple transactions. Mirrors @solana/instruction-plans.
    #
    #   InstructionPlan = SingleInstructionPlan
    #                   | SequentialInstructionPlan
    #                   | ParallelInstructionPlan
    #                   | MessagePackerInstructionPlan

    # A plan that wraps a single instruction.
    class SingleInstructionPlan < T::Struct
      extend T::Sig

      const :instruction, Instructions::Instruction
      sig { returns(Symbol) }
      def kind = :single
    end

    # A plan whose children must execute in order.
    # +divisible: true+ allows the planner to split children across transactions.
    # +divisible: false+ means all children should be atomic (one tx or a bundle).
    class SequentialInstructionPlan < T::Struct
      extend T::Sig

      const :plans,     T::Array[T.untyped]  # Array[InstructionPlan]
      const :divisible, T::Boolean
      sig { returns(Symbol) }
      def kind = :sequential
    end

    # A plan whose children may execute concurrently or be packed in any order.
    class ParallelInstructionPlan < T::Struct
      extend T::Sig

      const :plans, T::Array[T.untyped]  # Array[InstructionPlan]
      sig { returns(Symbol) }
      def kind = :parallel
    end

    # Provides a MessagePacker that dynamically packs instructions into messages.
    # The +get_message_packer+ proc returns a fresh MessagePacker each call.
    class MessagePackerInstructionPlan < T::Struct
      extend T::Sig

      const :get_message_packer, T.untyped  # Proc -> MessagePacker
      sig { returns(Symbol) }
      def kind = :message_packer
    end

    # Returned by MessagePackerInstructionPlan#get_message_packer.
    # Mirrors the TypeScript MessagePacker interface.
    class MessagePacker
      extend T::Sig

      sig { params(done_proc: T.untyped, pack_proc: T.untyped).void }
      def initialize(done_proc:, pack_proc:)
        @done_proc = T.let(done_proc, T.untyped)
        @pack_proc = T.let(pack_proc, T.untyped)
      end

      # Returns true when all instructions have been packed.
      sig { returns(T::Boolean) }
      def done?
        @done_proc.call
      end

      # Packs as many instructions as possible into +message+ and returns the
      # updated message. Raises SolanaError if the message is too small or the
      # packer is already done.
      #
      # +max_instructions+ caps the number of top-level instructions allowed in the
      # returned message (defaults to 16; must be a positive integer no greater than 64).
      sig do
        params(
          message:          TransactionMessages::TransactionMessage,
          max_instructions: T.nilable(Integer)
        ).returns(TransactionMessages::TransactionMessage)
      end
      def pack_message_to_capacity(message, max_instructions: nil)
        @pack_proc.call(message, max_instructions)
      end
    end

    # ── Factory helpers ────────────────────────────────────────────────────────

    extend self

    # Wraps a single instruction in a plan.
    # Mirrors `singleInstructionPlan(instruction)`.
    sig { params(instruction: Instructions::Instruction).returns(SingleInstructionPlan) }
    def single_instruction_plan(instruction)
      SingleInstructionPlan.new(instruction: instruction)
    end

    # Creates a divisible sequential plan (children may be split across txs).
    # Mirrors `sequentialInstructionPlan(plans)`.
    # Accepts raw Instruction objects; wraps them in SingleInstructionPlan automatically.
    sig { params(plans: T::Array[T.untyped]).returns(SequentialInstructionPlan) }
    def sequential_instruction_plan(plans)
      SequentialInstructionPlan.new(plans: parse_single_instruction_plans(plans), divisible: true)
    end

    # Creates a non-divisible sequential plan (children must be atomic).
    # Mirrors `nonDivisibleSequentialInstructionPlan(plans)`.
    sig { params(plans: T::Array[T.untyped]).returns(SequentialInstructionPlan) }
    def non_divisible_sequential_instruction_plan(plans)
      SequentialInstructionPlan.new(plans: parse_single_instruction_plans(plans), divisible: false)
    end

    # Creates a parallel plan (children may execute concurrently).
    # Mirrors `parallelInstructionPlan(plans)`.
    sig { params(plans: T::Array[T.untyped]).returns(ParallelInstructionPlan) }
    def parallel_instruction_plan(plans)
      ParallelInstructionPlan.new(plans: parse_single_instruction_plans(plans))
    end

    # Creates a MessagePackerInstructionPlan that packs a fixed byte stream into
    # instructions of maximum size, calling +get_instruction.(offset, length)+.
    # Mirrors `getLinearMessagePackerInstructionPlan({ getInstruction, totalLength })`.
    sig do
      params(
        total_length:    Integer,
        get_instruction: T.untyped  # Proc(offset, length) -> Instruction
      ).returns(MessagePackerInstructionPlan)
    end
    def get_linear_message_packer_instruction_plan(total_length:, get_instruction:)
      MessagePackerInstructionPlan.new(
        get_message_packer: -> {
          offset = T.let(0, Integer)
          MessagePacker.new(
            done_proc: -> { offset >= total_length },
            pack_proc:  ->(message, max_instructions) {
              if offset >= total_length
                Kernel.raise SolanaError.new(SolanaError::INSTRUCTION_PLANS__MESSAGE_PACKER_ALREADY_COMPLETE)
              end

              InstructionPlans.assert_valid_max_instructions_per_transaction(max_instructions)
              resolved_max = InstructionPlans.resolve_max_instructions(max_instructions)
              InstructionPlans.assert_max_instructions_per_transaction(message.instructions.length + 1, resolved_max)

              base_ix    = get_instruction.call(offset, 0)
              with_base  = TransactionMessages.append_instructions(message, [base_ix])
              base_size  = Transactions.get_transaction_message_size(with_base)
              # -1 leeway for compact-u16 headers
              free_space = Transactions::TRANSACTION_SIZE_LIMIT - base_size - 1

              if free_space <= 0
                msg_size = Transactions.get_transaction_message_size(message)
                Kernel.raise SolanaError.new(
                  SolanaError::INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN,
                  {
                    num_bytes_required: base_size - msg_size + 1,
                    num_free_bytes:     Transactions::TRANSACTION_SIZE_LIMIT - msg_size - 1
                  }
                )
              end

              length = [total_length - offset, free_space].min
              ix     = get_instruction.call(offset, length)
              offset += length
              TransactionMessages.append_instructions(message, [ix])
            }
          )
        }
      )
    end

    # Creates a MessagePackerInstructionPlan that iterates over a fixed list of
    # instructions, packing as many as fit into each message.
    # Mirrors `getMessagePackerInstructionPlanFromInstructions(instructions)`.
    sig { params(instructions: T::Array[Instructions::Instruction]).returns(MessagePackerInstructionPlan) }
    def get_message_packer_instruction_plan_from_instructions(instructions)
      MessagePackerInstructionPlan.new(
        get_message_packer: -> {
          idx = T.let(0, Integer)
          MessagePacker.new(
            done_proc: -> { idx >= instructions.length },
            pack_proc:  ->(message, max_instructions) {
              if idx >= instructions.length
                Kernel.raise SolanaError.new(SolanaError::INSTRUCTION_PLANS__MESSAGE_PACKER_ALREADY_COMPLETE)
              end

              InstructionPlans.assert_valid_max_instructions_per_transaction(max_instructions)
              resolved_max = InstructionPlans.resolve_max_instructions(max_instructions)
              InstructionPlans.assert_max_instructions_per_transaction(message.instructions.length + 1, resolved_max)

              original_size = Transactions.get_transaction_message_size(message)
              packed        = T.let(message, TransactionMessages::TransactionMessage)
              start_idx     = idx

              (idx...instructions.length).each do |i|
                # Stop once the message is full, before compiling a message that would exceed
                # the instruction limit (which would raise). The assertion above guarantees at
                # least the first instruction fits, so reaching the limit here is a graceful stop.
                if packed.instructions.length >= resolved_max
                  idx = i
                  return packed
                end

                next_packed = TransactionMessages.append_instructions(packed, [T.must(instructions[i])])
                size        = Transactions.get_transaction_message_size(next_packed)

                if size > Transactions::TRANSACTION_SIZE_LIMIT
                  if i == start_idx
                    Kernel.raise SolanaError.new(
                      SolanaError::INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN,
                      {
                        num_bytes_required: size - original_size,
                        num_free_bytes:     Transactions::TRANSACTION_SIZE_LIMIT - original_size
                      }
                    )
                  end
                  idx = i
                  return packed
                end

                packed = next_packed
              end

              idx = instructions.length
              packed
            }
          )
        }
      )
    end

    # Creates a MessagePackerInstructionPlan that splits +total_size+ bytes into
    # chunks of REALLOC_LIMIT (10,240) bytes, calling +get_instruction.(size)+.
    # Mirrors `getReallocMessagePackerInstructionPlan({ getInstruction, totalSize })`.
    sig do
      params(
        total_size:      Integer,
        get_instruction: T.untyped  # Proc(size) -> Instruction
      ).returns(MessagePackerInstructionPlan)
    end
    def get_realloc_message_packer_instruction_plan(total_size:, get_instruction:)
      realloc_limit      = 10_240
      num_instructions   = (total_size.to_f / realloc_limit).ceil
      last_size          = total_size % realloc_limit

      instructions = num_instructions.times.map do |i|
        chunk = (i == num_instructions - 1) ? last_size : realloc_limit
        get_instruction.call(chunk)
      end

      get_message_packer_instruction_plan_from_instructions(instructions)
    end

    # Recursively extracts all instructions from a plan tree (depth-first).
    sig { params(plan: T.untyped).returns(T::Array[Instructions::Instruction]) }
    def flatten_instruction_plan(plan)
      case plan
      when SingleInstructionPlan
        [plan.instruction]
      when SequentialInstructionPlan, ParallelInstructionPlan
        plan.plans.flat_map { |p| flatten_instruction_plan(p) }
      when MessagePackerInstructionPlan
        Kernel.raise ArgumentError, 'Cannot flatten a MessagePackerInstructionPlan (instructions are dynamically generated)'
      else
        Kernel.raise ArgumentError, "Unknown InstructionPlan type: #{plan.class}"
      end
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    # Wraps bare Instruction objects in SingleInstructionPlan; passes plans through.
    sig { params(items: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
    def parse_single_instruction_plans(items)
      items.map do |item|
        item.is_a?(Instructions::Instruction) ? single_instruction_plan(item) : item
      end
    end
    private_class_method :parse_single_instruction_plans
  end
end
