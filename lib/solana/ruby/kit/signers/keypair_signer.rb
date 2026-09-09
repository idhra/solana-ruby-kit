# typed: strict
# frozen_string_literal: true

require 'rbnacl'
require_relative '../errors'
require_relative '../addresses/address'
require_relative '../keys/key_pair'
require_relative '../keys/signatures'
require_relative '../transactions/transaction'

module Solana::Ruby::Kit
  module Signers
    extend T::Sig
    # A signer backed by an Ed25519 key pair, capable of signing both
    # transaction messages and off-chain messages.
    #
    # Mirrors TypeScript's `KeyPairSigner<TAddress>`, which combines
    # `MessagePartialSigner` and `TransactionPartialSigner` with a
    # `CryptoKeyPair` reference.
    #
    # In Ruby we keep it simple: the signer holds an RbNaCl::SigningKey
    # (which contains the private key seed and can derive the public key)
    # and exposes the signer's address.
    class KeyPairSigner
      extend T::Sig

      sig { returns(Addresses::Address) }
      attr_reader :address

      sig { returns(Keys::KeyPair) }
      attr_reader :key_pair

      sig { params(key_pair: Keys::KeyPair).void }
      def initialize(key_pair)
        @key_pair = T.let(key_pair, Keys::KeyPair)
        @address  = T.let(
          Addresses::Address.new(Addresses.encode_address(key_pair.verify_key.to_bytes)),
          Addresses::Address
        )
      end

      sig { returns(String) }
      def to_s = @address.to_s

      sig { returns(String) }
      def inspect = "#<KeyPairSigner address=#{@address}>"

      # Signs raw bytes with the private key, returning a SignatureBytes.
      # Used internally by sign_transaction and sign_message.
      sig { params(data: String).returns(Keys::SignatureBytes) }
      def sign(data)
        Keys.sign_bytes(@key_pair.signing_key, data)
      end

      # Verifies a signature against data using this signer's public key.
      sig { params(sig_bytes: Keys::SignatureBytes, data: String).returns(T::Boolean) }
      def verify(sig_bytes, data)
        Keys.verify_signature(@key_pair.verify_key, sig_bytes, data)
      end
    end

    extend self

    # Creates a KeyPairSigner from an existing Keys::KeyPair.
    # Mirrors `createSignerFromKeyPair(keyPair)`.
    sig { params(key_pair: Keys::KeyPair).returns(KeyPairSigner) }
    def create_signer_from_key_pair(key_pair)
      KeyPairSigner.new(key_pair)
    end

    # Generates a fresh random key pair and wraps it in a KeyPairSigner.
    # Mirrors `generateKeyPairSigner()`.
    sig { returns(KeyPairSigner) }
    def generate_key_pair_signer
      KeyPairSigner.new(Keys.generate_key_pair)
    end

    # Creates a KeyPairSigner from 64 raw bytes (seed || public key).
    # Mirrors `createKeyPairSignerFromBytes(bytes)`.
    sig { params(bytes: String).returns(KeyPairSigner) }
    def create_key_pair_signer_from_bytes(bytes)
      KeyPairSigner.new(Keys.create_key_pair_from_bytes(bytes))
    end

    # Creates a KeyPairSigner from a 32-byte private key seed.
    # Mirrors `createKeyPairSignerFromPrivateKeyBytes(bytes)`.
    sig { params(bytes: String).returns(KeyPairSigner) }
    def create_key_pair_signer_from_private_key_bytes(bytes)
      KeyPairSigner.new(Keys.create_key_pair_from_private_key_bytes(bytes))
    end

    # Returns true if the value is a KeyPairSigner.
    # Mirrors `isKeyPairSigner(value)`.
    sig { params(value: T.untyped).returns(T::Boolean) }
    def key_pair_signer?(value)
      value.is_a?(KeyPairSigner)
    end

    # Raises SolanaError if the value is not a KeyPairSigner.
    # Mirrors `assertIsKeyPairSigner(value)`.
    sig { params(value: T.untyped).void }
    def assert_key_pair_signer!(value)
      Kernel.raise SolanaError.new(:SOLANA_ERROR__SIGNER__EXPECTED_KEY_PAIR_SIGNER) unless key_pair_signer?(value)
    end

    # Signs a transaction message's bytes using all provided signers.
    # Returns a hash mapping each signer's address to its SignatureBytes.
    #
    # This is the Ruby analogue of the TypeScript signers' sign-transaction
    # workflow: each signer produces its Ed25519 signature of the compiled
    # message bytes, and the signatures are collected into a map.
    #
    # Mirrors the combined behaviour of `TransactionPartialSigner.signTransactions`.
    sig do
      params(
        signers:       T::Array[KeyPairSigner],
        message_bytes: String
      ).returns(T::Hash[String, Keys::SignatureBytes])
    end
    def sign_message_bytes_with_signers(signers, message_bytes)
      signers.each_with_object({}) do |signer, map|
        map[signer.address.value] = signer.sign(message_bytes)
      end
    end
  end
end
