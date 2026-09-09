# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative '../instructions/instruction'
require_relative 'transaction_message'
require_relative 'resource_limit_validation'

module Solana::Ruby::Kit
  module TransactionMessages
    # Address of the Compute Budget program.
    COMPUTE_BUDGET_PROGRAM_ADDRESS = T.let(
      Addresses::Address.new('ComputeBudget111111111111111111111111111111'),
      Addresses::Address
    )

    # Maximum compute unit limit per transaction (from Agave execution_budget.rs).
    MAX_COMPUTE_UNIT_LIMIT = T.let(1_400_000, Integer)

    # Maximum loaded accounts data size limit per transaction (64 MiB, from Agave).
    MAX_LOADED_ACCOUNTS_DATA_SIZE_LIMIT = T.let(64 * 1024 * 1024, Integer)

    SET_COMPUTE_UNIT_LIMIT_DISCRIMINATOR             = T.let(2, Integer)
    SET_LOADED_ACCOUNTS_DATA_SIZE_LIMIT_DISCRIMINATOR = T.let(4, Integer)

    extend self

    # ---------------------------------------------------------------------------
    # SetComputeUnitLimit instruction helpers
    # ---------------------------------------------------------------------------

    sig { params(units: Integer).returns(Instructions::Instruction) }
    def get_set_compute_unit_limit_instruction(units)
      data = ([SET_COMPUTE_UNIT_LIMIT_DISCRIMINATOR].pack('C') + [units].pack('V')).b
      Instructions::Instruction.new(
        program_address: COMPUTE_BUDGET_PROGRAM_ADDRESS,
        accounts:        nil,
        data:            data
      )
    end

    sig { params(instruction: Instructions::Instruction).returns(T::Boolean) }
    def set_compute_unit_limit_instruction?(instruction)
      instruction.program_address == COMPUTE_BUDGET_PROGRAM_ADDRESS &&
        !instruction.data.nil? &&
        T.must(instruction.data).bytesize == 5 &&
        T.must(instruction.data).getbyte(0) == SET_COMPUTE_UNIT_LIMIT_DISCRIMINATOR
    end

    sig { params(data: String).returns(Integer) }
    def compute_unit_limit_from_instruction_data(data)
      T.must(data[1, 4]).unpack1('V')
    end

    # Returns the compute unit limit set on a transaction message, or nil if none is set.
    # Mirrors `getTransactionMessageComputeUnitLimit` from @solana/transaction-messages.
    sig { params(message: TransactionMessage).returns(T.nilable(Integer)) }
    def get_transaction_message_compute_unit_limit(message)
      ix = message.instructions.find { |i| set_compute_unit_limit_instruction?(i) }
      ix ? compute_unit_limit_from_instruction_data(T.must(ix.data)) : nil
    end

    # Sets the compute unit limit on a transaction message, appending or replacing the
    # SetComputeUnitLimit instruction. Mirrors `setTransactionMessageComputeUnitLimit`.
    sig { params(limit: Integer, message: TransactionMessage).returns(TransactionMessage) }
    def set_transaction_message_compute_unit_limit(limit, message)
      assert_is_valid_compute_unit_limit(limit)
      existing_idx = message.instructions.index { |i| set_compute_unit_limit_instruction?(i) }
      new_ix = get_set_compute_unit_limit_instruction(limit)

      if existing_idx.nil?
        append_instructions(message, [new_ix])
      elsif compute_unit_limit_from_instruction_data(T.must(T.must(message.instructions[existing_idx]).data)) == limit
        message
      else
        new_instructions = message.instructions.dup
        new_instructions[existing_idx] = new_ix
        TransactionMessage.new(
          version:               message.version,
          instructions:          new_instructions,
          fee_payer:             message.fee_payer,
          lifetime_constraint:   message.lifetime_constraint,
          address_table_lookups: message.address_table_lookups
        )
      end
    end

    # ---------------------------------------------------------------------------
    # SetLoadedAccountsDataSizeLimit instruction helpers
    # ---------------------------------------------------------------------------

    sig { params(limit: Integer).returns(Instructions::Instruction) }
    def get_set_loaded_accounts_data_size_limit_instruction(limit)
      data = ([SET_LOADED_ACCOUNTS_DATA_SIZE_LIMIT_DISCRIMINATOR].pack('C') + [limit].pack('V')).b
      Instructions::Instruction.new(
        program_address: COMPUTE_BUDGET_PROGRAM_ADDRESS,
        accounts:        nil,
        data:            data
      )
    end

    sig { params(instruction: Instructions::Instruction).returns(T::Boolean) }
    def set_loaded_accounts_data_size_limit_instruction?(instruction)
      instruction.program_address == COMPUTE_BUDGET_PROGRAM_ADDRESS &&
        !instruction.data.nil? &&
        T.must(instruction.data).bytesize == 5 &&
        T.must(instruction.data).getbyte(0) == SET_LOADED_ACCOUNTS_DATA_SIZE_LIMIT_DISCRIMINATOR
    end

    sig { params(data: String).returns(Integer) }
    def loaded_accounts_data_size_limit_from_instruction_data(data)
      T.must(data[1, 4]).unpack1('V')
    end

    # Returns the loaded accounts data size limit set on a transaction message, or nil.
    # Mirrors `getTransactionMessageLoadedAccountsDataSizeLimit`.
    sig { params(message: TransactionMessage).returns(T.nilable(Integer)) }
    def get_transaction_message_loaded_accounts_data_size_limit(message)
      ix = message.instructions.find { |i| set_loaded_accounts_data_size_limit_instruction?(i) }
      ix ? loaded_accounts_data_size_limit_from_instruction_data(T.must(ix.data)) : nil
    end

    # Sets the loaded accounts data size limit on a transaction message.
    # Mirrors `setTransactionMessageLoadedAccountsDataSizeLimit`.
    sig { params(limit: Integer, message: TransactionMessage).returns(TransactionMessage) }
    def set_transaction_message_loaded_accounts_data_size_limit(limit, message)
      existing_idx = message.instructions.index { |i| set_loaded_accounts_data_size_limit_instruction?(i) }
      new_ix = get_set_loaded_accounts_data_size_limit_instruction(limit)

      if existing_idx.nil?
        append_instructions(message, [new_ix])
      elsif loaded_accounts_data_size_limit_from_instruction_data(T.must(T.must(message.instructions[existing_idx]).data)) == limit
        message
      else
        new_instructions = message.instructions.dup
        new_instructions[existing_idx] = new_ix
        TransactionMessage.new(
          version:               message.version,
          instructions:          new_instructions,
          fee_payer:             message.fee_payer,
          lifetime_constraint:   message.lifetime_constraint,
          address_table_lookups: message.address_table_lookups
        )
      end
    end
  end
end
