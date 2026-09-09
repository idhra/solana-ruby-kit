# typed: strict
# frozen_string_literal: true

require_relative '../errors'
require_relative '../instructions/instruction'
require_relative '../instructions/roles'
require_relative 'compiled_transaction_message'
require_relative 'loaded_addresses'

module Solana::Ruby::Kit
  module TransactionIntrospection
    extend T::Sig

    extend self

    # Builds the full ordered list of AccountMetas for a compiled transaction
    # message.
    #
    # The order matches the runtime's resolution order:
    #   1. Static accounts, with role bits derived from the message header
    #      (writable signers, readonly signers, writable non-signers, readonly
    #      non-signers).
    #   2. ALT-loaded writable accounts (always non-signer, writable).
    #   3. ALT-loaded readonly accounts (always non-signer, readonly).
    #
    # Inner-instruction account indices reference the same flat list, so this
    # helper is also useful for resolving inner instructions.
    #
    # Mirrors `getAccountMetasFromCompiledTransactionMessage()`.
    sig do
      params(
        compiled_message: CompiledTransactionMessage,
        loaded_addresses: T.nilable(LoadedAddresses)
      ).returns(T::Array[Instructions::AccountMeta])
    end
    def get_account_metas_from_compiled_transaction_message(compiled_message, loaded_addresses = nil)
      header          = compiled_message.header
      static_accounts = compiled_message.static_accounts

      num_writable_signer_accounts =
        header.num_signer_accounts - header.num_readonly_signer_accounts
      num_writable_non_signer_accounts =
        static_accounts.length - header.num_signer_accounts - header.num_readonly_non_signer_accounts

      metas = T.let([], T::Array[Instructions::AccountMeta])
      i = 0
      num_writable_signer_accounts.times do
        metas << Instructions::AccountMeta.new(address: T.must(static_accounts[i]), role: Instructions::AccountRole::WRITABLE_SIGNER)
        i += 1
      end
      header.num_readonly_signer_accounts.times do
        metas << Instructions::AccountMeta.new(address: T.must(static_accounts[i]), role: Instructions::AccountRole::READONLY_SIGNER)
        i += 1
      end
      num_writable_non_signer_accounts.times do
        metas << Instructions::AccountMeta.new(address: T.must(static_accounts[i]), role: Instructions::AccountRole::WRITABLE)
        i += 1
      end
      header.num_readonly_non_signer_accounts.times do
        metas << Instructions::AccountMeta.new(address: T.must(static_accounts[i]), role: Instructions::AccountRole::READONLY)
        i += 1
      end

      if loaded_addresses
        loaded_addresses.writable.each { |addr| metas << Instructions::AccountMeta.new(address: addr, role: Instructions::AccountRole::WRITABLE) }
        loaded_addresses.readonly.each  { |addr| metas << Instructions::AccountMeta.new(address: addr, role: Instructions::AccountRole::READONLY) }
      end

      metas
    end

    # Returns the outer instructions of a compiled transaction message as
    # Instructions::Instruction objects, with account indices resolved to
    # AccountMetas and data exposed as a raw binary String. `accounts` and
    # `data` are omitted (nil) when empty.
    #
    # Mirrors `getInstructionsFromCompiledTransactionMessage()`.
    sig do
      params(
        compiled_message: CompiledTransactionMessage,
        loaded_addresses: T.nilable(LoadedAddresses)
      ).returns(T::Array[Instructions::Instruction])
    end
    def get_instructions_from_compiled_transaction_message(compiled_message, loaded_addresses = nil)
      metas = get_account_metas_from_compiled_transaction_message(compiled_message, loaded_addresses)
      get_instructions_from_compiled_transaction_message_with_metas(compiled_message, metas)
    end

    # Internal variant of get_instructions_from_compiled_transaction_message
    # that takes pre-built AccountMetas. Used by WalkInstructions to avoid
    # rebuilding the meta list when it is already needed for resolving inner
    # instructions.
    sig do
      params(
        compiled_message: CompiledTransactionMessage,
        account_metas:    T::Array[Instructions::AccountMeta]
      ).returns(T::Array[Instructions::Instruction])
    end
    def get_instructions_from_compiled_transaction_message_with_metas(compiled_message, account_metas)
      compiled_message.instructions.map { |ix| resolve_instruction(ix, account_metas) }
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    sig { params(ix: CompiledInstruction, metas: T::Array[Instructions::AccountMeta]).returns(Instructions::Instruction) }
    def resolve_instruction(ix, metas)
      program_meta = metas[ix.program_address_index]
      if program_meta.nil?
        Kernel.raise SolanaError.new(
          SolanaError::TRANSACTIONS__FAILED_TO_DECOMPILE_INSTRUCTION_PROGRAM_ADDRESS_NOT_FOUND,
          { index: ix.program_address_index }
        )
      end

      accounts = ix.account_indices.map do |i|
        account_meta = metas[i]
        if account_meta.nil?
          Kernel.raise SolanaError.new(
            SolanaError::TRANSACTION__FAILED_TO_DECOMPILE_INSTRUCTION_ACCOUNT_INDEX_OUT_OF_RANGE,
            { index: i }
          )
        end
        account_meta
      end

      Instructions::Instruction.new(
        program_address: program_meta.address,
        accounts:        accounts.empty? ? nil : accounts,
        data:            ix.data.empty? ? nil : ix.data
      )
    end
    private_class_method :resolve_instruction
  end
end
