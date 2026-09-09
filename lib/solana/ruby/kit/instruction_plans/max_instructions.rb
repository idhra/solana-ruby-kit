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

    extend self

    # Resolves the effective maximum number of instructions allowed in a transaction message,
    # falling back to the default when no value is provided.
    # Mirrors `resolveMaxInstructions(maxInstructions)`.
    sig { params(max_instructions: T.nilable(Integer)).returns(Integer) }
    def resolve_max_instructions(max_instructions)
      max_instructions || DEFAULT_MAX_INSTRUCTIONS_PER_TRANSACTION
    end

    # Asserts that a configured maximum number of instructions per transaction is valid.
    # +nil+ is allowed and falls back to the default.
    # Mirrors `assertValidMaxInstructionsPerTransaction(maxInstructions)`.
    sig { params(max_instructions: T.nilable(Integer)).void }
    def assert_valid_max_instructions_per_transaction(max_instructions)
      return if max_instructions.nil?

      if max_instructions <= 0 || max_instructions > TRANSACTION_INSTRUCTION_LIMIT
        Kernel.raise SolanaError.new(
          SolanaError::INSTRUCTION_PLANS__INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION,
          {
            max_instructions:              max_instructions,
            transaction_instruction_limit: TRANSACTION_INSTRUCTION_LIMIT
          }
        )
      end
    end

    # Raises if +num_instructions+ exceeds +max_instructions+.
    # Mirrors `assertMaxInstructionsPerTransaction(numInstructions, maxInstructions)`.
    sig { params(num_instructions: Integer, max_instructions: Integer).void }
    def assert_max_instructions_per_transaction(num_instructions, max_instructions)
      return if num_instructions <= max_instructions

      Kernel.raise SolanaError.new(
        SolanaError::INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED,
        { max_instructions: max_instructions, num_instructions: num_instructions }
      )
    end
  end
end
