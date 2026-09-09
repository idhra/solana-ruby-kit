# typed: strict
# frozen_string_literal: true

require 'base64'
require 'rbnacl'
require_relative 'addresses/address'
require_relative 'keys/signatures'
require_relative 'transactions/transaction'
require_relative 'errors'

module Solana::Ruby::Kit
  # Server-side Ruby port of the @solana/wallet-standard signTransaction interface.
  #
  # When a browser wallet (Phantom, Backpack, Solflare, …) calls
  #   wallet.features['solana:signTransaction'].signTransaction(transaction)
  # the signed transaction is returned as serialised wire bytes.  Rails receives
  # those bytes (typically base64-encoded in a JSON request body) and uses this
  # module to:
  #
  #   1. Decode the wire bytes back into a +Transactions::Transaction+ struct.
  #   2. Verify every present Ed25519 signature against the message bytes.
  #   3. Confirm that a specific wallet address (or all required addresses) signed.
  #   4. Optionally broadcast the verified transaction via +Rpc+.
  #
  # Solana addresses ARE Ed25519 public keys (32-byte base58), so signature
  # verification requires no external key lookup — the verify key is derived
  # directly from the signer's address string.
  #
  # Typical Rails controller usage:
  #
  #   wire_bytes = Base64.strict_decode64(params[:signed_transaction])
  #   tx = Solana::Ruby::Kit::WalletStandard.verify_signed_transaction!(wire_bytes)
  #   Solana::Ruby::Kit::Transactions.assert_fully_signed_transaction!(tx)
  #   # tx is now safe to inspect or forward to the RPC node
  #
  # Mirrors @solana/wallet-standard (anza-xyz/kit) and @wallet-standard/features.
  module WalletStandard
    extend T::Sig

    # ── Wallet Standard feature identifiers ──────────────────────────────────
    # String constants that identify which signing capabilities a browser wallet
    # supports.  Client-side JavaScript reads wallet.features to detect these;
    # the constants are documented here so Rails code can reference them by name
    # when building feature-negotiation metadata for the frontend.

    # The wallet can sign transactions without broadcasting them.
    SIGN_TRANSACTION          = T.let('solana:signTransaction',        String)
    # The wallet can sign and broadcast in a single round-trip.
    SIGN_AND_SEND_TRANSACTION = T.let('solana:signAndSendTransaction', String)
    # The wallet can sign arbitrary off-chain messages.
    SIGN_MESSAGE              = T.let('solana:signMessage',            String)
    # Base Wallet Standard lifecycle features.
    CONNECT                   = T.let('standard:connect',              String)
    DISCONNECT                = T.let('standard:disconnect',           String)
    EVENTS                    = T.let('standard:events',               String)

    extend self

    # ── Wire-format decoder ───────────────────────────────────────────────────

    # Decodes a Solana wire-encoded transaction into a +Transactions::Transaction+.
    #
    # Accepts the binary output of a wallet's +signTransaction+ call.  Binary
    # (ASCII_8BIT) strings are used as-is; any other encoding is treated as
    # standard base64 and decoded automatically.
    #
    # Solana wire format (legacy; v0 versioned transactions add a one-byte
    # version prefix to the message section):
    #
    #   [compact-u16]       num_signatures
    #   [64 bytes × n]      signature slots (all-zero slot means unfilled)
    #   [message bytes …]
    #
    # The returned Transaction carries:
    #   +message_bytes+  — raw bytes that were (or will be) signed
    #   +signatures+     — ordered Hash of signer_address → raw_sig_bytes or nil
    #
    # Raises +SolanaError::WALLET_STANDARD__INVALID_WIRE_FORMAT+ for malformed input.
    #
    # Mirrors +getTransactionDecoder()+ from @solana/transactions.
    sig { params(wire_bytes: String).returns(Transactions::Transaction) }
    def decode_wire_transaction(wire_bytes)
      bytes  = coerce_to_binary(wire_bytes)
      offset = 0

      # 1. Signature count (compact-u16)
      sig_count, offset = decode_compact_u16(bytes, offset)
      if sig_count > 19
        Kernel.raise SolanaError.new(
          SolanaError::WALLET_STANDARD__INVALID_WIRE_FORMAT,
          reason: "signature count #{sig_count} exceeds the maximum of 19"
        )
      end

      # 2. Signature slots — 64 bytes each; all-zero means the slot is unfilled.
      zero64   = ("\x00" * 64).b
      raw_sigs = T.let([], T::Array[T.nilable(String)])
      sig_count.times do
        slot = bytes[offset, 64]
        if slot.nil? || slot.bytesize != 64
          Kernel.raise SolanaError.new(
            SolanaError::WALLET_STANDARD__INVALID_WIRE_FORMAT,
            reason: 'truncated signature slot'
          )
        end
        raw_sigs << (slot.b == zero64 ? nil : slot.b)
        offset += 64
      end

      # 3. Everything after the signatures section is the message.
      msg_slice = bytes[offset..]
      if msg_slice.nil? || msg_slice.empty?
        Kernel.raise SolanaError.new(
          SolanaError::WALLET_STANDARD__INVALID_WIRE_FORMAT,
          reason: 'message section is missing'
        )
      end
      message_bytes = msg_slice.b

      # 4. Determine version and locate the message header.
      #    Legacy transactions:   first byte = num_required_signatures (0..127)
      #    Versioned (v0) trans.: first byte = 0x80 | version  (≥ 128); skip it.
      msg_pos    = 0
      first_byte = message_bytes.getbyte(msg_pos).to_i
      msg_pos   += 1 if (first_byte & 0x80) != 0

      num_required_sigs = message_bytes.getbyte(msg_pos).to_i
      msg_pos += 1
      msg_pos += 2  # skip num_readonly_signed + num_readonly_unsigned

      # 5. Parse the account list to recover signer addresses.
      num_accounts, msg_pos = decode_compact_u16(message_bytes, msg_pos)
      if msg_pos + (num_accounts * 32) > message_bytes.bytesize
        Kernel.raise SolanaError.new(
          SolanaError::WALLET_STANDARD__INVALID_WIRE_FORMAT,
          reason: 'account table truncated'
        )
      end

      account_addrs = T.let([], T::Array[String])
      num_accounts.times do
        account_addrs << Addresses.encode_address(T.must(message_bytes[msg_pos, 32]).b)
        msg_pos += 32
      end

      # 6. Build the signatures map.
      #    The first +num_required_sigs+ accounts in the account table are the
      #    signers; their raw_sigs slots are positionally aligned.
      signer_addrs = T.must(account_addrs[0, num_required_sigs])
      signatures   = T.let({}, T::Hash[String, T.nilable(String)])
      signer_addrs.each_with_index { |addr, i| signatures[addr] = raw_sigs[i] }

      Transactions::Transaction.new(message_bytes: message_bytes, signatures: signatures)
    end

    # ── Signature verification ────────────────────────────────────────────────

    # Verifies every filled (non-nil) signature in +transaction.signatures+.
    #
    # For each signed slot the signer's Ed25519 public key is reconstructed
    # directly from their address (Solana addresses are base58-encoded 32-byte
    # Ed25519 public keys), so no external key lookup is required.
    #
    # Raises +SolanaError::WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED+ if
    # any signature does not verify.  Nil (unfilled) slots are skipped silently;
    # use +Transactions.assert_fully_signed_transaction!+ to enforce that all
    # required signers have signed.
    sig { params(transaction: Transactions::AnyTransaction).void }
    def verify_transaction_signatures!(transaction)
      transaction.signatures.each do |addr_str, sig_raw|
        next if sig_raw.nil?

        verify_key = RbNaCl::VerifyKey.new(Addresses.decode_address(Addresses::Address.new(addr_str)))
        sig_bytes  = Keys::SignatureBytes.new(sig_raw)

        unless Keys.verify_signature(verify_key, sig_bytes, transaction.message_bytes)
          Kernel.raise SolanaError.new(
            SolanaError::WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED,
            address: addr_str
          )
        end
      end
    end

    # Convenience method for Rails controllers: decode wire bytes received from a
    # browser wallet and verify all present signatures in one call.
    #
    # Returns the decoded +Transaction+ on success.
    # Raises +SolanaError+ for malformed wire bytes or any invalid signature.
    # Does NOT require the transaction to be fully signed; follow up with
    # +Transactions.assert_fully_signed_transaction!+ when broadcasting.
    #
    # Accepts binary or base64-encoded input (see +decode_wire_transaction+).
    sig { params(wire_bytes: String).returns(Transactions::Transaction) }
    def verify_signed_transaction!(wire_bytes)
      tx = decode_wire_transaction(wire_bytes)
      verify_transaction_signatures!(tx)
      tx
    end

    # Returns +true+ if +address+ has provided a cryptographically valid
    # signature for +transaction+; +false+ if the slot is absent, nil, or the
    # signature does not verify against +transaction.message_bytes+.
    sig { params(transaction: Transactions::AnyTransaction, address: Addresses::Address).returns(T::Boolean) }
    def signed_by?(transaction, address)
      sig_raw = transaction.signatures[address.value]
      return false if sig_raw.nil?

      verify_key = RbNaCl::VerifyKey.new(Addresses.decode_address(address))
      sig_bytes  = Keys::SignatureBytes.new(sig_raw)
      Keys.verify_signature(verify_key, sig_bytes, transaction.message_bytes)
    end

    # ── Private helpers ───────────────────────────────────────────────────────

    # Forces +input+ to a binary (ASCII_8BIT) String.
    # ASCII_8BIT input is returned as-is; anything else is treated as base64.
    sig { params(input: String).returns(String) }
    def coerce_to_binary(input)
      return input.b if input.encoding == ::Encoding::ASCII_8BIT

      stripped = input.strip
      begin
        Base64.strict_decode64(stripped).b
      rescue ArgumentError
        Base64.decode64(stripped).b
      end
    end
    private_class_method :coerce_to_binary

    # Reads a Solana compact-u16 from +bytes+ starting at +offset+.
    # Returns +[decoded_integer, next_offset]+.
    sig { params(bytes: String, offset: Integer).returns([Integer, Integer]) }
    def decode_compact_u16(bytes, offset)
      value = 0
      shift = 0
      Kernel.loop do
        byte = bytes.getbyte(offset)
        if byte.nil?
          Kernel.raise SolanaError.new(
            SolanaError::WALLET_STANDARD__INVALID_WIRE_FORMAT,
            reason: 'compact-u16 read past end of buffer'
          )
        end
        offset += 1
        value  |= (byte & 0x7f) << shift
        shift  += 7
        break unless (byte & 0x80) != 0
      end
      [value, offset]
    end
    private_class_method :decode_compact_u16
  end
end
