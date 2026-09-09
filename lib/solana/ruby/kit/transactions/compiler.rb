# typed: strict
# frozen_string_literal: true

require_relative 'transaction'
require_relative '../addresses/address'
require_relative '../transaction_messages/transaction_message'
require_relative '../instructions/roles'
require_relative '../errors'

module Solana::Ruby::Kit
  module Transactions
    # Maximum wire-encoded transaction size in bytes (Solana protocol limit).
    TRANSACTION_SIZE_LIMIT = T.let(1232, Integer)

    extend self

    # Returns the compiled byte-size of a transaction message.
    # Mirrors `getTransactionMessageSize()` from @solana/transactions.
    # The message must have a fee payer and a blockhash lifetime set.
    sig { params(message: TransactionMessages::TransactionMessage).returns(Integer) }
    def get_transaction_message_size(message)
      compile_transaction_message(message).message_bytes.bytesize
    end

    # ---------------------------------------------------------------------------
    # compile_transaction_message
    # ---------------------------------------------------------------------------
    # Compiles a TransactionMessage into a Transaction ready for signing.
    #
    # Only legacy (version: :legacy) transactions are supported; the serialised
    # format follows the Solana on-wire message layout:
    #
    #   [header: 3 bytes]
    #   [compact-u16 account count] [32-byte addresses …]
    #   [recent blockhash: 32 bytes]
    #   [compact-u16 instruction count]
    #   [for each instruction:
    #     [program_id_index: u8]
    #     [compact-u16 account count] [account indices: u8 …]
    #     [compact-u16 data length]  [data bytes]
    #   ]
    #
    # The returned Transaction contains:
    #   - message_bytes  — the serialised message (the bytes that are signed)
    #   - signatures     — an ordered hash of signer_address → nil (unfilled)
    #
    # Use wire_encode_transaction to prepend the signatures section before
    # submitting to the RPC node via sendTransaction.
    sig { params(message: TransactionMessages::TransactionMessage).returns(Transaction) }
    def compile_transaction_message(message)
      Kernel.raise SolanaError.new(:SOLANA_ERROR__TRANSACTION__FEE_PAYER_MISSING) if message.fee_payer.nil?
      fee_payer = T.must(message.fee_payer)

      # ── 1. Collect accounts and merge roles ────────────────────────────────
      # Insertion-ordered hash: address_str → merged AccountRole integer.
      account_roles = T.let({}, T::Hash[String, Integer])

      # Fee payer is always the first writable signer.
      account_roles[fee_payer.value] = Instructions::AccountRole::WRITABLE_SIGNER

      message.instructions.each do |ix|
        # The instruction's program address is a readonly non-signer participant.
        prog = ix.program_address.value
        account_roles[prog] ||= Instructions::AccountRole::READONLY

        (ix.accounts || []).each do |meta|
          addr     = meta.address.value
          existing = account_roles[addr] || Instructions::AccountRole::READONLY
          account_roles[addr] = Instructions::AccountRole.merge(existing, meta.role)
        end
      end

      # ── 2. Partition into the four groups and sort within each ─────────────
      fp = fee_payer.value

      writable_signers    = T.let([], T::Array[String])
      readonly_signers    = T.let([], T::Array[String])
      writable_non_signers = T.let([], T::Array[String])
      readonly_non_signers = T.let([], T::Array[String])

      account_roles.each do |addr, role|
        next if addr == fp  # fee payer is handled separately

        is_signer   = Instructions::AccountRole.signer_role?(role)
        is_writable = Instructions::AccountRole.writable_role?(role)

        if is_signer && is_writable
          writable_signers << addr
        elsif is_signer
          readonly_signers << addr
        elsif is_writable
          writable_non_signers << addr
        else
          readonly_non_signers << addr
        end
      end

      writable_signers.sort!
      readonly_signers.sort!
      writable_non_signers.sort!
      readonly_non_signers.sort!

      # Fee payer first, then writable signers, readonly signers, non-signers.
      ordered = [fp] + writable_signers + readonly_signers +
                writable_non_signers + readonly_non_signers

      # ── 3. Build index lookup ──────────────────────────────────────────────
      account_index = T.let({}, T::Hash[String, Integer])
      ordered.each_with_index { |addr, i| account_index[addr] = i }

      # ── 4. Message header (3 bytes) ────────────────────────────────────────
      num_required_sigs    = 1 + writable_signers.size + readonly_signers.size
      num_readonly_signed  = readonly_signers.size
      num_readonly_unsigned = readonly_non_signers.size

      header = [num_required_sigs, num_readonly_signed, num_readonly_unsigned].pack('CCC').b

      # ── 5. Account addresses section ───────────────────────────────────────
      accounts_section = encode_compact_u16(ordered.size)
      ordered.each do |addr_str|
        accounts_section = accounts_section + Addresses.decode_address(Addresses::Address.new(addr_str))
      end

      # ── 6. Recent blockhash (32 bytes) ─────────────────────────────────────
      # Mirrors upstream compile-transaction.ts #581:
      #   - BlockhashLifetime → use the blockhash bytes
      #   - DurableNonceLifetime → use the nonce value bytes (stored in the same field)
      #   - No lifetime → 32 zero bytes (placeholder; must be replaced before signing)
      constraint = message.lifetime_constraint
      blockhash_bytes =
        if constraint.is_a?(TransactionMessages::BlockhashLifetimeConstraint)
          Addresses.decode_address(Addresses::Address.new(constraint.blockhash))
        elsif constraint.is_a?(TransactionMessages::DurableNonceLifetimeConstraint)
          Addresses.decode_address(Addresses::Address.new(constraint.nonce))
        else
          ("\x00" * 32).b
        end

      # ── 7. Instructions section ────────────────────────────────────────────
      ixs_section = encode_compact_u16(message.instructions.size)

      message.instructions.each do |ix|
        prog_idx    = T.must(account_index[ix.program_address.value])
        ix_accounts = ix.accounts || []
        ix_indices  = ix_accounts.map { |m| T.must(account_index[m.address.value]) }
        data_bytes  = (ix.data || '').b

        ixs_section = ixs_section +
                      [prog_idx].pack('C').b +
                      encode_compact_u16(ix_indices.size) +
                      ix_indices.pack('C*').b +
                      encode_compact_u16(data_bytes.bytesize) +
                      data_bytes
      end

      message_bytes = (header + accounts_section + blockhash_bytes + ixs_section).b

      # ── 8. Signatures map (one nil slot per required signer) ───────────────
      signer_addresses = [fp] + writable_signers + readonly_signers
      signatures = T.let({}, T::Hash[String, T.nilable(String)])
      signer_addresses.each { |addr| signatures[addr] = nil }

      Transaction.new(message_bytes: message_bytes, signatures: signatures)
    end

    # ---------------------------------------------------------------------------
    # wire_encode_transaction
    # ---------------------------------------------------------------------------
    # Encodes a Transaction (signed or partially signed) into the full Solana
    # on-wire format that the RPC node's sendTransaction method expects:
    #
    #   [compact-u16 signature count]
    #   [64-byte signature or 64 zero bytes if nil] × count
    #   [message bytes]
    #
    # The result is a binary String; base64-encode it before sending via HTTP.
    sig { params(transaction: AnyTransaction).returns(String) }
    def wire_encode_transaction(transaction)
      sigs    = transaction.signatures
      header  = encode_compact_u16(sigs.size)
      sig_bytes = sigs.values.map { |s| (s || ("\x00" * 64)).b }.join

      (header + sig_bytes + transaction.message_bytes).b
    end

    # ---------------------------------------------------------------------------
    # Private helpers
    # ---------------------------------------------------------------------------

    # Encodes a non-negative integer using Solana's compact-u16 format.
    #   0–127     → 1 byte
    #   128–16383 → 2 bytes
    #   16384+    → 3 bytes (max value 0x7fff used in practice)
    sig { params(value: Integer).returns(String) }
    def encode_compact_u16(value)
      result    = T.let([], T::Array[Integer])
      remaining = value

      Kernel.loop do
        byte       = remaining & 0x7f
        remaining  = remaining >> 7
        byte      |= 0x80 if remaining > 0
        result << byte
        break if remaining == 0
      end

      result.pack('C*').b
    end
    private_class_method :encode_compact_u16
  end
end
