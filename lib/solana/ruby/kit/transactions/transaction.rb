# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative '../keys/signatures'
require_relative '../errors'

module Solana::Ruby::Kit
  module Transactions
    extend T::Sig
    # The wire-encoded bytes of a compiled transaction message.
    # Mirrors TypeScript's `TransactionMessageBytes` (branded Uint8Array).
    TransactionMessageBytes = T.type_alias { String }  # binary String

    # An ordered map of signer addresses to their Ed25519 signatures (or nil
    # when the address has been reserved for signing but not yet signed).
    # Mirrors TypeScript's `SignaturesMap = OrderedMap<Address, SignatureBytes | null>`.
    SignaturesMap = T.type_alias { T::Hash[String, T.nilable(String)] }

    # A compiled, signable Solana transaction.
    # Mirrors TypeScript's `Transaction` type.
    class Transaction < T::Struct
      # Compiled transaction message bytes (wire format).
      const :message_bytes, String   # binary
      # Signer address → 64-byte signature (or nil if not yet signed).
      const :signatures,    T::Hash[String, T.nilable(String)]
    end

    # Marks that every required signer has provided a signature.
    # Mirrors TypeScript's `FullySignedTransaction` nominal type.
    # T::Struct is final; cannot subclass Transaction, so we use a parallel struct.
    class FullySignedTransaction < T::Struct
      const :message_bytes, String
      const :signatures,    T::Hash[String, T.nilable(String)]
    end

    # Either transaction struct.
    #
    # Because `FullySignedTransaction` is a *parallel* struct rather than a
    # subclass of `Transaction` (T::Struct is final), it is not a subtype of it,
    # and a signature naming only `Transaction` rejects it. That matters for
    # nearly everything below, because `sign_transaction` returns a
    # `FullySignedTransaction` and encoding, inspecting or sending one is the
    # ordinary next step — `wire_encode_transaction(sign_transaction(...))` is
    # the single most common two-call sequence in the whole library.
    #
    # TypeScript has no such problem: `FullySignedTransaction` there is
    # `Transaction & { readonly [brand] }`, an intersection that *is* assignable
    # to `Transaction`. This alias is the Ruby equivalent of that assignability.
    #
    # Use it for any parameter that reads a transaction. Use `Transaction`
    # alone only where the value is specifically an unsigned or partially
    # signed one, and `FullySignedTransaction` alone only as a return type
    # asserting that signing happened.
    AnyTransaction = T.type_alias { T.any(Transaction, FullySignedTransaction) }

    extend self

    # Returns the base58-encoded signature that uniquely identifies a transaction.
    # This is the fee payer's signature (first entry in the signatures map).
    # Mirrors `getSignatureFromTransaction(transaction)`.
    sig { params(transaction: AnyTransaction).returns(Keys::Signature) }
    def get_signature_from_transaction(transaction)
      sig_bytes = transaction.signatures.values.first
      Kernel.raise SolanaError.new(:SOLANA_ERROR__TRANSACTION__FEE_PAYER_SIGNATURE_MISSING) unless sig_bytes

      Keys.encode_signature(Keys::SignatureBytes.new(sig_bytes))
    end

    # Returns true if every slot in the signatures map is filled.
    # Mirrors `isFullySignedTransaction(transaction)`.
    sig { params(transaction: AnyTransaction).returns(T::Boolean) }
    def fully_signed_transaction?(transaction)
      transaction.signatures.values.all? { |sig| !sig.nil? }
    end

    # Raises SolanaError unless every signer slot is filled.
    # Mirrors `assertIsFullySignedTransaction(transaction)`.
    sig { params(transaction: AnyTransaction).void }
    def assert_fully_signed_transaction!(transaction)
      missing = transaction.signatures.filter_map { |addr, sig| addr if sig.nil? }
      return if missing.empty?

      Kernel.raise SolanaError.new(
        :SOLANA_ERROR__TRANSACTION__SIGNATURES_MISSING,
        addresses: missing
      )
    end

    # Returns true if the wire-encoded transaction fits within TRANSACTION_SIZE_LIMIT.
    # Mirrors `isTransactionWithinSizeLimit(transaction)`.
    sig { params(transaction: AnyTransaction).returns(T::Boolean) }
    def within_size_limit?(transaction)
      wire_encode_transaction(transaction).bytesize <= TRANSACTION_SIZE_LIMIT
    end

    # Raises SolanaError if the wire-encoded transaction exceeds TRANSACTION_SIZE_LIMIT.
    # Mirrors `assertIsTransactionWithinSizeLimit(transaction)`.
    sig { params(transaction: AnyTransaction).void }
    def assert_within_size_limit!(transaction)
      actual = wire_encode_transaction(transaction).bytesize
      return if actual <= TRANSACTION_SIZE_LIMIT

      Kernel.raise SolanaError.new(
        SolanaError::TRANSACTIONS__EXCEEDS_SIZE_LIMIT,
        { actual_size: actual, limit: TRANSACTION_SIZE_LIMIT }
      )
    end

    # Returns true if the transaction is both fully signed and within the size limit.
    # Mirrors `isSendableTransaction(transaction)`.
    # sendableTransaction = FullySignedTransaction & TransactionWithinSizeLimit
    sig { params(transaction: AnyTransaction).returns(T::Boolean) }
    def sendable_transaction?(transaction)
      fully_signed_transaction?(transaction) && within_size_limit?(transaction)
    end

    # Raises SolanaError unless the transaction is fully signed and within size limit.
    # Mirrors `assertIsSendableTransaction(transaction)`.
    sig { params(transaction: AnyTransaction).void }
    def assert_sendable_transaction!(transaction)
      assert_fully_signed_transaction!(transaction)
      assert_within_size_limit!(transaction)
    end

    # Signs a transaction with one or more RbNaCl::SigningKey objects.
    # Only keys whose address appears in `transaction.signatures` are applied.
    # Raises SolanaError if a key is not expected to sign this transaction.
    #
    # Mirrors `partiallySignTransaction(keyPairs, transaction)`.
    # TypeScript version is async (Web Crypto); Ruby version is synchronous.
    sig do
      params(
        signing_keys: T::Array[T.untyped],  # Array<RbNaCl::SigningKey>
        transaction:  AnyTransaction
      ).returns(Transaction)
    end
    def partially_sign_transaction(signing_keys, transaction)
      new_signatures  = transaction.signatures.dup
      unexpected      = T.let([], T::Array[String])

      signing_keys.each do |signing_key|
        verify_key = signing_key.verify_key
        addr_str   = Addresses.encode_address(verify_key.to_bytes)

        unless new_signatures.key?(addr_str)
          unexpected << addr_str
          next
        end

        sig_bytes = Keys.sign_bytes(signing_key, transaction.message_bytes)
        existing  = new_signatures[addr_str]

        next if existing && existing == sig_bytes.value

        new_signatures[addr_str] = sig_bytes.value
      end

      if unexpected.any?
        Kernel.raise SolanaError.new(
          :SOLANA_ERROR__TRANSACTION__ADDRESSES_CANNOT_SIGN_TRANSACTION,
          expected_addresses:    transaction.signatures.keys,
          unexpected_addresses:  unexpected
        )
      end

      Transaction.new(
        message_bytes: transaction.message_bytes,
        signatures:    new_signatures
      )
    end

    # Signs a transaction and asserts it is fully signed before returning.
    # Mirrors `signTransaction(keyPairs, transaction)`.
    sig do
      params(
        signing_keys: T::Array[T.untyped],
        transaction:  AnyTransaction
      ).returns(FullySignedTransaction)
    end
    def sign_transaction(signing_keys, transaction)
      signed = partially_sign_transaction(signing_keys, transaction)
      assert_fully_signed_transaction!(signed)

      FullySignedTransaction.new(
        message_bytes: signed.message_bytes,
        signatures:    signed.signatures
      )
    end
  end
end
