# typed: strict
# frozen_string_literal: true

require 'rbnacl'
require_relative '../errors'
require_relative 'signatures'

module Solana::Ruby::Kit
  module Keys
    extend T::Sig
    # Represents an Ed25519 key pair: a signing key (private) and its
    # corresponding verification key (public).
    #
    # Mirrors TypeScript's `CryptoKeyPair`:
    #   { privateKey: CryptoKey, publicKey: CryptoKey }
    #
    # In TypeScript this wraps Web Crypto opaque `CryptoKey` handles.
    # In Ruby, RbNaCl::SigningKey holds the 32-byte private key seed, and
    # RbNaCl::VerifyKey holds the 32-byte public key.
    class KeyPair < T::Struct
      # 32-byte Ed25519 signing (private) key
      const :signing_key, T.untyped  # RbNaCl::SigningKey
      # Corresponding 32-byte verification (public) key
      const :verify_key,  T.untyped  # RbNaCl::VerifyKey
    end

    extend self

    # Generates a fresh Ed25519 key pair using a cryptographically secure RNG.
    # Mirrors `generateKeyPair()` in TypeScript.
    sig { returns(KeyPair) }
    def generate_key_pair
      signing_key = RbNaCl::SigningKey.generate
      KeyPair.new(signing_key: signing_key, verify_key: signing_key.verify_key)
    end

    # Creates a KeyPair from a 64-byte seed array (first 32 = private seed,
    # last 32 = expected public key bytes) and verifies they match by performing
    # a sign-and-verify round-trip.
    #
    # Mirrors `createKeyPairFromBytes(bytes: ReadonlyUint8Array)` in TypeScript.
    #
    # @param bytes [String] A 64-byte binary string (private seed || public key).
    sig { params(bytes: String).returns(KeyPair) }
    def create_key_pair_from_bytes(bytes)
      if bytes.bytesize != 64
        Kernel.raise SolanaError.new(
          SolanaError::KEYS__INVALID_KEY_PAIR_BYTE_LENGTH,
          byte_length: bytes.bytesize
        )
      end

      private_seed = bytes.byteslice(0, 32) || Kernel.raise(SolanaError.new(SolanaError::KEYS__INVALID_KEY_PAIR_BYTE_LENGTH, byte_length: bytes.bytesize))
      public_bytes = bytes.byteslice(32, 32) || Kernel.raise(SolanaError.new(SolanaError::KEYS__INVALID_KEY_PAIR_BYTE_LENGTH, byte_length: bytes.bytesize))

      signing_key = RbNaCl::SigningKey.new(private_seed.b)
      verify_key  = signing_key.verify_key

      # Verify that the embedded public key matches the derived one.
      unless verify_key.to_bytes == public_bytes.b
        Kernel.raise SolanaError.new(SolanaError::KEYS__PUBLIC_KEY_MUST_MATCH_PRIVATE_KEY)
      end

      # Round-trip sign-and-verify with random data (mirrors the TypeScript check).
      random_data = RbNaCl::Random.random_bytes(32)
      signed_data = sign_bytes(signing_key, random_data)
      unless verify_signature(verify_key, signed_data, random_data)
        Kernel.raise SolanaError.new(SolanaError::KEYS__PUBLIC_KEY_MUST_MATCH_PRIVATE_KEY)
      end

      KeyPair.new(signing_key: signing_key, verify_key: verify_key)
    end

    # Creates a KeyPair from a 32-byte private key seed alone.
    # The matching public key is derived automatically.
    #
    # Mirrors `createKeyPairFromPrivateKeyBytes(bytes: ReadonlyUint8Array)`.
    sig { params(bytes: String).returns(KeyPair) }
    def create_key_pair_from_private_key_bytes(bytes)
      signing_key = RbNaCl::SigningKey.new(bytes.b)
      KeyPair.new(signing_key: signing_key, verify_key: signing_key.verify_key)
    end
  end
end
