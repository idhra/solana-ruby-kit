# typed: strict
# frozen_string_literal: true

require_relative '../errors'

module Solana::Ruby::Kit
  module InstructionPlans
    extend T::Sig

    # The default maximum number of top-level instructions per planned transaction message.
    #
    # Intentionally lower than the transaction format's instruction limit to leave headroom
    # for inner instructions (CPIs), which are not visible at planning time.
    DEFAULT_MAX_INSTRUCTIONS_PER_TRANSACTION = T.let(16, Integer)

    # The hard maximum number of top-level instructions the transaction format can encode.
    TRANSACTION_INSTRUCTION_LIMIT = T.let(64, Integer)

    # The error codes the transaction planner treats as "try another message": the message
    # holds too many instructions, would be too large, or a message packer refused it for a
    # custom reason. Upstream's list also has four `TRANSACTION__TOO_MANY_*` compile errors;
    # Ruby's compiler raises none of them, so they are not listed.
    MESSAGE_PACKER_ERRORS_THAT_REQUIRE_NEW_CANDIDATE = T.let(
      [
        SolanaError::INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED,
        SolanaError::INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN,
        SolanaError::INSTRUCTION_PLANS__MESSAGE_REJECTED_BY_PACKER
      ].freeze,
      T::Array[Symbol]
    )

    extend self

    # Resolves the maximum number of instructions a message packer may put in a transaction
    # message: the default of 16 when +max_instructions+ is nil, otherwise the given value,
    # which must be a positive integer no greater than TRANSACTION_INSTRUCTION_LIMIT.
    #
    # This is typically the first thing a custom MessagePacker does with the
    # +max_instructions+ it receives in +pack_message_to_capacity+:
    #
    #   pack_proc: ->(message, max_instructions) {
    #     max = InstructionPlans.resolve_max_instructions_per_transaction(max_instructions)
    #     InstructionPlans.assert_max_instructions_per_transaction(message.instructions.length + 1, max)
    #     # ...
    #   }
    #
    # Raises INSTRUCTION_PLANS__INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION for an out-of-range value.
    # Mirrors `resolveMaxInstructionsPerTransaction(maxInstructions)`.
    sig { params(max_instructions: T.nilable(Integer)).returns(Integer) }
    def resolve_max_instructions_per_transaction(max_instructions = nil)
      return DEFAULT_MAX_INSTRUCTIONS_PER_TRANSACTION if max_instructions.nil?

      if max_instructions <= 0 || max_instructions > TRANSACTION_INSTRUCTION_LIMIT
        Kernel.raise SolanaError.new(
          SolanaError::INSTRUCTION_PLANS__INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION,
          {
            max_instructions:              max_instructions,
            transaction_instruction_limit: TRANSACTION_INSTRUCTION_LIMIT
          }
        )
      end

      max_instructions
    end

    # Raises if a message holding +num_instructions+ instructions would exceed
    # +max_instructions+. Use it in a custom MessagePacker before appending an instruction -
    # passing the count the message would have after the append - so the planner knows to
    # pack that instruction into another message.
    #
    # Raises INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED.
    # Mirrors `assertMaxInstructionsPerTransaction(numInstructions, maxInstructions)`.
    sig { params(num_instructions: Integer, max_instructions: Integer).void }
    def assert_max_instructions_per_transaction(num_instructions, max_instructions)
      return if num_instructions <= max_instructions

      Kernel.raise SolanaError.new(
        SolanaError::INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED,
        { max_instructions: max_instructions, num_instructions: num_instructions }
      )
    end

    # Raises if a message cannot grow from +current_size+ to +next_size+ bytes without
    # exceeding +size_limit+. Use it in a custom MessagePacker after appending the next
    # instruction(s), so the planner knows to pack them into another message. It takes sizes
    # rather than messages so callers who already computed them do not pay for it twice:
    #
    #   next_message = TransactionMessages.append_instructions(message, [ix])
    #   InstructionPlans.assert_message_can_accommodate_size(
    #     current_size: Transactions.get_transaction_message_size(message),
    #     next_size:    Transactions.get_transaction_message_size(next_message),
    #     size_limit:   Transactions::TRANSACTION_SIZE_LIMIT
    #   )
    #
    # Raises INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN, reporting how many bytes
    # were required and how many were free.
    # Mirrors `assertMessageCanAccommodateSize({ currentSize, nextSize, sizeLimit })`.
    sig { params(current_size: Integer, next_size: Integer, size_limit: Integer).void }
    def assert_message_can_accommodate_size(current_size:, next_size:, size_limit:)
      return if next_size <= size_limit

      Kernel.raise SolanaError.new(
        SolanaError::INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN,
        { num_bytes_required: next_size - current_size, num_free_bytes: size_limit - current_size }
      )
    end

    # Whether +error+, raised while packing instructions into a message, means the message
    # cannot take them and a new candidate message is required (see
    # MESSAGE_PACKER_ERRORS_THAT_REQUIRE_NEW_CANDIDATE). Any other error is unexpected and
    # should propagate:
    #
    #   begin
    #     message = packer.pack_message_to_capacity(message)
    #   rescue => e
    #     raise unless InstructionPlans.message_packer_error_that_requires_new_candidate?(e)
    #     message = packer.pack_message_to_capacity(create_new_message)
    #   end
    #
    # A custom packer refuses a message for any other reason by raising
    # INSTRUCTION_PLANS__MESSAGE_REJECTED_BY_PACKER with a +reason:+.
    # Mirrors `isMessagePackerErrorThatRequiresNewCandidate(error)`.
    sig { params(error: T.anything).returns(T::Boolean) }
    def message_packer_error_that_requires_new_candidate?(error)
      case error
      when SolanaError then MESSAGE_PACKER_ERRORS_THAT_REQUIRE_NEW_CANDIDATE.include?(error.code)
      else false
      end
    end
  end
end
