# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative '../errors'
require_relative 'accounts'

module Solana::Ruby::Kit
  module Instructions
    extend T::Sig
    # A single instruction to be executed by a Solana program.
    # Mirrors TypeScript's `Instruction<TProgramAddress, TAccounts, TData>`.
    #
    # All fields are optional — instructions may omit accounts or data.
    class Instruction < T::Struct
      const :program_address, Addresses::Address
      const :accounts,        T.nilable(T::Array[T.any(AccountMeta, AccountLookupMeta)])
      const :data,            T.nilable(String)  # binary String (Uint8Array equivalent)
    end

    extend self

    # Returns true if the instruction targets the given program address.
    # Mirrors `isInstructionForProgram()`.
    sig { params(instruction: Instruction, program_address: Addresses::Address).returns(T::Boolean) }
    def instruction_for_program?(instruction, program_address)
      instruction.program_address == program_address
    end

    # Raises SolanaError unless the instruction targets the given program.
    # Mirrors `assertIsInstructionForProgram()`.
    sig { params(instruction: Instruction, program_address: Addresses::Address).void }
    def assert_instruction_for_program!(instruction, program_address)
      return if instruction_for_program?(instruction, program_address)

      Kernel.raise SolanaError.new(
        :SOLANA_ERROR__INSTRUCTION__EXPECTED_TO_HAVE_ACCOUNTS,
        expected_program_address: program_address.value,
        actual_program_address:   instruction.program_address.value
      )
    end

    # Returns true if the instruction has at least one account.
    # Mirrors `isInstructionWithAccounts()`.
    sig { params(instruction: Instruction).returns(T::Boolean) }
    def instruction_with_accounts?(instruction)
      !instruction.accounts.nil? && !T.must(instruction.accounts).empty?
    end

    # Raises unless the instruction has accounts.
    # Mirrors `assertIsInstructionWithAccounts()`.
    sig { params(instruction: Instruction).void }
    def assert_instruction_with_accounts!(instruction)
      Kernel.raise SolanaError.new(:SOLANA_ERROR__INSTRUCTION__EXPECTED_TO_HAVE_ACCOUNTS) unless instruction_with_accounts?(instruction)
    end

    # Returns true if the instruction carries data bytes.
    # Mirrors `isInstructionWithData()`.
    sig { params(instruction: Instruction).returns(T::Boolean) }
    def instruction_with_data?(instruction)
      !instruction.data.nil?
    end

    # Raises unless the instruction has data.
    # Mirrors `assertIsInstructionWithData()`.
    sig { params(instruction: Instruction).void }
    def assert_instruction_with_data!(instruction)
      Kernel.raise SolanaError.new(:SOLANA_ERROR__INSTRUCTION__EXPECTED_TO_HAVE_DATA) unless instruction_with_data?(instruction)
    end
  end
end
