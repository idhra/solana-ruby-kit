# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative '../errors'

module Solana::Ruby::Kit
  module TransactionIntrospection
    extend T::Sig

    # The signer/readonly account counts from a compiled transaction message.
    # Mirrors the `header` field of TypeScript's `CompiledTransactionMessage`.
    class CompiledTransactionMessageHeader < T::Struct
      const :num_signer_accounts,               Integer
      const :num_readonly_signer_accounts,      Integer
      const :num_readonly_non_signer_accounts,  Integer
    end

    # A single instruction inside a compiled transaction message, with account
    # indices and data still unresolved (see GetInstructions for resolution).
    class CompiledInstruction < T::Struct
      const :program_address_index, Integer
      const :account_indices,       T::Array[Integer]
      const :data,                  String  # binary; may be empty
    end

    # A decoded transaction message: the account roles, static account list,
    # instructions, and lifetime token (recent blockhash or durable nonce value).
    #
    # Mirrors TypeScript's `CompiledTransactionMessage & CompiledTransactionMessageWithLifetime`.
    # Ruby normalizes legacy/v0/v1 instruction representations into a single
    # `instructions` array (TypeScript keeps v1's headers/payloads split) since
    # nothing downstream needs the raw per-version shape.
    class CompiledTransactionMessage < T::Struct
      const :version,         T.untyped  # :legacy or Integer (0 or 1)
      const :header,          CompiledTransactionMessageHeader
      const :static_accounts, T::Array[Addresses::Address]
      const :instructions,    T::Array[CompiledInstruction]
      const :lifetime_token,  String  # base58-encoded blockhash or nonce value
    end

    extend self

    # Decodes legacy or v0 compiled transaction message bytes (the
    # `message_bytes` of a `Transactions::Transaction`) into a
    # CompiledTransactionMessage.
    #
    # v1 messages use a different (message-first) wire envelope and are not
    # decoded here — Ruby's wire compiler (`Transactions.compile_transaction_message`)
    # does not yet produce v1 transactions either, so there is nothing to
    # round-trip. Raises SolanaError::TRANSACTION__VERSION_NUMBER_NOT_SUPPORTED
    # for any version this decoder cannot handle.
    #
    # Mirrors `getCompiledTransactionMessageDecoder()` from @solana/transaction-messages.
    sig { params(message_bytes: String).returns(CompiledTransactionMessage) }
    def decode_compiled_transaction_message(message_bytes)
      bytes  = message_bytes.b
      offset = 0

      first_byte = bytes.getbyte(0).to_i
      if (first_byte & 0x80) != 0
        version = first_byte & 0x7f
        unless version == 0
          Kernel.raise SolanaError.new(
            SolanaError::TRANSACTION__VERSION_NUMBER_NOT_SUPPORTED,
            { unsupported_version: version }
          )
        end
        offset += 1
      else
        version = :legacy
      end

      num_signer_accounts, offset              = read_byte(bytes, offset)
      num_readonly_signer_accounts, offset     = read_byte(bytes, offset)
      num_readonly_non_signer_accounts, offset = read_byte(bytes, offset)

      num_accounts, offset = decode_compact_u16(bytes, offset)
      static_accounts = T.let([], T::Array[Addresses::Address])
      num_accounts.times do
        static_accounts << Addresses.address(Addresses.encode_address(read_bytes(bytes, offset, 32)))
        offset += 32
      end

      lifetime_token = Addresses.encode_address(read_bytes(bytes, offset, 32))
      offset += 32

      num_instructions, offset = decode_compact_u16(bytes, offset)
      instructions = T.let([], T::Array[CompiledInstruction])
      num_instructions.times do
        program_address_index, offset = read_byte(bytes, offset)

        num_ix_accounts, offset = decode_compact_u16(bytes, offset)
        account_indices = T.let([], T::Array[Integer])
        num_ix_accounts.times do
          index, offset = read_byte(bytes, offset)
          account_indices << index
        end

        data_length, offset = decode_compact_u16(bytes, offset)
        data = read_bytes(bytes, offset, data_length)
        offset += data_length

        instructions << CompiledInstruction.new(
          program_address_index: program_address_index,
          account_indices:       account_indices,
          data:                  data
        )
      end

      CompiledTransactionMessage.new(
        version:         version,
        header:          CompiledTransactionMessageHeader.new(
          num_signer_accounts:              num_signer_accounts,
          num_readonly_signer_accounts:     num_readonly_signer_accounts,
          num_readonly_non_signer_accounts: num_readonly_non_signer_accounts
        ),
        static_accounts: static_accounts,
        instructions:    instructions,
        lifetime_token:  lifetime_token
      )
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    sig { params(bytes: String, offset: Integer, length: Integer).returns(String) }
    def read_bytes(bytes, offset, length)
      slice = bytes[offset, length]
      if slice.nil? || slice.bytesize != length
        Kernel.raise SolanaError.new(
          SolanaError::TRANSACTION_INTROSPECTION__MALFORMED_COMPILED_MESSAGE,
          { needed_bytes: offset + length }
        )
      end
      slice.b
    end
    private_class_method :read_bytes

    sig { params(bytes: String, offset: Integer).returns([Integer, Integer]) }
    def read_byte(bytes, offset)
      byte = bytes.getbyte(offset)
      if byte.nil?
        Kernel.raise SolanaError.new(
          SolanaError::TRANSACTION_INTROSPECTION__MALFORMED_COMPILED_MESSAGE,
          { needed_bytes: offset + 1 }
        )
      end
      [byte, offset + 1]
    end
    private_class_method :read_byte

    # Reads a Solana compact-u16 from +bytes+ starting at +offset+.
    # Returns [decoded_integer, next_offset].
    sig { params(bytes: String, offset: Integer).returns([Integer, Integer]) }
    def decode_compact_u16(bytes, offset)
      value = 0
      shift = 0
      Kernel.loop do
        byte, offset = read_byte(bytes, offset)
        value |= (byte & 0x7f) << shift
        shift += 7
        break unless (byte & 0x80) != 0
      end
      [value, offset]
    end
    private_class_method :decode_compact_u16
  end
end
