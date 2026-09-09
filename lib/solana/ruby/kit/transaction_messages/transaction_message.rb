# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative '../errors'
require_relative '../instructions/instruction'

module Solana::Ruby::Kit
  module TransactionMessages
    extend T::Sig
    # Supported transaction versions.
    # Mirrors TypeScript's `TransactionVersion = 'legacy' | 0 | 1`.
    # Version 1 is defined but not yet supported by most tooling.
    TransactionVersion = T.type_alias { T.any(Symbol, Integer) }

    LEGACY_VERSION = T.let(:legacy, Symbol)
    V0_VERSION     = T.let(0, Integer)
    V1_VERSION     = T.let(1, Integer)

    MAX_SUPPORTED_TRANSACTION_VERSION = T.let(1, Integer)

    # A blockhash-based lifetime constraint.
    # Mirrors TypeScript's `BlockhashLifetimeConstraint`.
    class BlockhashLifetimeConstraint < T::Struct
      # A recent blockhash string (base58-encoded 32 bytes).
      const :blockhash,              String
      # Block height after which the blockhash is considered expired.
      # TypeScript uses bigint; Ruby uses Integer.
      const :last_valid_block_height, Integer
    end

    # A durable-nonce lifetime constraint.
    # Mirrors TypeScript's `DurableNonceTransactionMessageLifetimeConstraint`.
    class DurableNonceLifetimeConstraint < T::Struct
      const :nonce,               String             # base58 nonce value
      const :nonce_account_address, Addresses::Address
    end

    # Lifetime can be a blockhash constraint, a durable-nonce constraint, or nil.
    Lifetime = T.type_alias { T.nilable(T.any(BlockhashLifetimeConstraint, DurableNonceLifetimeConstraint)) }

    # The core transaction message structure.
    # Mirrors TypeScript's `TransactionMessage` (legacy | V0).
    #
    # TypeScript uses compile-time type narrowing to differentiate versions;
    # Ruby uses the `version` field at runtime.
    class TransactionMessage < T::Struct
      # :legacy or 0 (V1 reserved)
      const :version,             T.untyped  # Symbol or Integer
      # Ordered list of instructions.
      const :instructions,        T::Array[Instructions::Instruction]
      # The account that pays the transaction fee (nil on a freshly created message).
      const :fee_payer,           T.nilable(Addresses::Address)
      # Lifetime constraint (nil until explicitly set).
      const :lifetime_constraint, Lifetime
      # V0 only: lookup table addresses mapped to the accounts they hold.
      const :address_table_lookups, T.nilable(T::Hash[String, T::Array[Integer]])
    end

    extend self

    # Creates an empty transaction message at the given version.
    # Mirrors `createTransactionMessage({ version })`.
    sig { params(version: T.untyped).returns(TransactionMessage) }
    def create_transaction_message(version:)
      TransactionMessage.new(
        version:               version,
        instructions:          [],
        fee_payer:             nil,
        lifetime_constraint:   nil,
        address_table_lookups: nil
      )
    end

    # Sets the fee payer on a transaction message.
    # Mirrors `setTransactionMessageFeePayer(feePayer, transactionMessage)`.
    sig { params(fee_payer: Addresses::Address, message: TransactionMessage).returns(TransactionMessage) }
    def set_fee_payer(fee_payer, message)
      return message if message.fee_payer == fee_payer

      TransactionMessage.new(
        version:               message.version,
        instructions:          message.instructions,
        fee_payer:             fee_payer,
        lifetime_constraint:   message.lifetime_constraint,
        address_table_lookups: message.address_table_lookups
      )
    end

    # Sets a blockhash-based lifetime constraint on a transaction message.
    # Mirrors `setTransactionMessageLifetimeUsingBlockhash(constraint, message)`.
    sig { params(constraint: BlockhashLifetimeConstraint, message: TransactionMessage).returns(TransactionMessage) }
    def set_blockhash_lifetime(constraint, message)
      existing = message.lifetime_constraint
      if existing.is_a?(BlockhashLifetimeConstraint) &&
         existing.blockhash == constraint.blockhash &&
         existing.last_valid_block_height == constraint.last_valid_block_height
        return message
      end

      TransactionMessage.new(
        version:               message.version,
        instructions:          message.instructions,
        fee_payer:             message.fee_payer,
        lifetime_constraint:   constraint,
        address_table_lookups: message.address_table_lookups
      )
    end

    # Sets a durable-nonce lifetime constraint on a transaction message.
    # Mirrors `setTransactionMessageLifetimeUsingDurableNonce(constraint, message)`.
    sig { params(constraint: DurableNonceLifetimeConstraint, message: TransactionMessage).returns(TransactionMessage) }
    def set_durable_nonce_lifetime(constraint, message)
      TransactionMessage.new(
        version:               message.version,
        instructions:          message.instructions,
        fee_payer:             message.fee_payer,
        lifetime_constraint:   constraint,
        address_table_lookups: message.address_table_lookups
      )
    end

    # Appends one or more instructions to a transaction message.
    # Mirrors `appendTransactionMessageInstruction(instruction, message)` and
    # `appendTransactionMessageInstructions(instructions, message)`.
    sig { params(message: TransactionMessage, instructions: T::Array[Instructions::Instruction]).returns(TransactionMessage) }
    def append_instructions(message, instructions)
      TransactionMessage.new(
        version:               message.version,
        instructions:          message.instructions + instructions,
        fee_payer:             message.fee_payer,
        lifetime_constraint:   message.lifetime_constraint,
        address_table_lookups: message.address_table_lookups
      )
    end

    # Prepends one or more instructions to a transaction message.
    # Mirrors `prependTransactionMessageInstruction(instruction, message)`.
    sig { params(message: TransactionMessage, instructions: T::Array[Instructions::Instruction]).returns(TransactionMessage) }
    def prepend_instructions(message, instructions)
      TransactionMessage.new(
        version:               message.version,
        instructions:          instructions + message.instructions,
        fee_payer:             message.fee_payer,
        lifetime_constraint:   message.lifetime_constraint,
        address_table_lookups: message.address_table_lookups
      )
    end

    # Returns true if the message has a blockhash-based lifetime.
    sig { params(message: TransactionMessage).returns(T::Boolean) }
    def blockhash_lifetime?(message)
      message.lifetime_constraint.is_a?(BlockhashLifetimeConstraint)
    end

    # Returns true if the message has a durable-nonce lifetime.
    sig { params(message: TransactionMessage).returns(T::Boolean) }
    def durable_nonce_lifetime?(message)
      message.lifetime_constraint.is_a?(DurableNonceLifetimeConstraint)
    end

    # Raises SolanaError unless the message has a blockhash lifetime.
    sig { params(message: TransactionMessage).void }
    def assert_blockhash_lifetime!(message)
      Kernel.raise SolanaError.new(:SOLANA_ERROR__TRANSACTION__EXPECTED_BLOCKHASH_LIFETIME) unless blockhash_lifetime?(message)
    end
  end
end
