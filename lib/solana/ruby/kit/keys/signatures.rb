# typed: strict
# frozen_string_literal: true

require 'rbnacl'
require_relative '../errors'
require_relative '../encoding/base58'

module Solana::Ruby::Kit
  module Keys
    extend T::Sig
    # A validated base58-encoded Ed25519 signature string (64 bytes on-wire).
    # Mirrors TypeScript:
    #   type Signature = Brand<EncodedString<string, 'base58'>, 'Signature'>
    class Signature
      extend T::Sig

      sig { returns(String) }
      attr_reader :value

      sig { params(value: String).void }
      def initialize(value)
        @value = T.let(value, String)
      end

      sig { returns(String) }
      def to_s = @value

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        !!(other.is_a?(Signature) && @value == other.value)
      end
    end

    # A 64-byte binary string holding raw Ed25519 signature bytes.
    # Mirrors TypeScript:
    #   type SignatureBytes = Brand<Uint8Array, 'SignatureBytes'>
    class SignatureBytes
      extend T::Sig

      BYTE_LENGTH = 64

      sig { returns(String) }
      attr_reader :value  # binary String, always 64 bytes

      sig { params(value: String).void }
      def initialize(value)
        @value = T.let(value, String)
      end

      sig { returns(Integer) }
      def bytesize = @value.bytesize

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        !!(other.is_a?(SignatureBytes) && @value == other.value)
      end
    end

    # Length bounds for a base58-encoded 64-byte signature string.
    SIGNATURE_MIN_STR_LEN = 64
    SIGNATURE_MAX_STR_LEN = 88

    extend self

    # Returns true if the string is a valid base58-encoded Ed25519 signature.
    # Mirrors `isSignature()` in TypeScript.
    sig { params(putative: String).returns(T::Boolean) }
    def signature?(putative)
      return false unless putative.length.between?(SIGNATURE_MIN_STR_LEN, SIGNATURE_MAX_STR_LEN)

      bytes = Encoding::Base58.decode(putative)
      bytes.bytesize == SignatureBytes::BYTE_LENGTH
    rescue ArgumentError
      false
    end

    # Raises SolanaError if the string is not a valid base58-encoded signature.
    # Mirrors `assertIsSignature()` in TypeScript.
    sig { params(putative: String).void }
    def assert_signature!(putative)
      unless putative.length.between?(SIGNATURE_MIN_STR_LEN, SIGNATURE_MAX_STR_LEN)
        Kernel.raise SolanaError.new(
          SolanaError::KEYS__SIGNATURE_STRING_LENGTH_OUT_OF_RANGE,
          actual_length: putative.length
        )
      end

      bytes = Encoding::Base58.decode(putative)
      assert_signature_bytes!(bytes)
    rescue ArgumentError
      Kernel.raise SolanaError.new(SolanaError::KEYS__SIGNATURE_STRING_LENGTH_OUT_OF_RANGE, actual_length: putative.length)
    end

    # Validates and wraps a string in a Signature value object.
    # Mirrors `signature()` in TypeScript.
    sig { params(putative: String).returns(Signature) }
    def signature(putative)
      assert_signature!(putative)
      Signature.new(putative)
    end

    # Returns true if the binary string is exactly 64 bytes (valid signature length).
    # Mirrors `isSignatureBytes()` in TypeScript.
    sig { params(putative: String).returns(T::Boolean) }
    def signature_bytes?(putative)
      putative.bytesize == SignatureBytes::BYTE_LENGTH
    end

    # Raises SolanaError if the binary string is not exactly 64 bytes.
    # Mirrors `assertIsSignatureBytes()` in TypeScript.
    sig { params(putative: String).void }
    def assert_signature_bytes!(putative)
      unless putative.bytesize == SignatureBytes::BYTE_LENGTH
        Kernel.raise SolanaError.new(
          SolanaError::KEYS__INVALID_SIGNATURE_BYTE_LENGTH,
          actual_length: putative.bytesize
        )
      end
    end

    # Validates and wraps raw bytes in a SignatureBytes value object.
    # Mirrors `signatureBytes()` in TypeScript.
    sig { params(putative: String).returns(SignatureBytes) }
    def signature_bytes(putative)
      assert_signature_bytes!(putative)
      SignatureBytes.new(putative.b)
    end

    # Signs data with an Ed25519 signing key, returning raw 64-byte SignatureBytes.
    #
    # Mirrors `signBytes(key: CryptoKey, data: ReadonlyUint8Array)` in TypeScript.
    # TypeScript uses `crypto.subtle.sign` (async); Ruby uses RbNaCl (sync).
    #
    # @param signing_key [RbNaCl::SigningKey]
    # @param data        [String] binary string to sign
    sig { params(signing_key: T.untyped, data: String).returns(SignatureBytes) }
    def sign_bytes(signing_key, data)
      raw = signing_key.sign(data.b)
      SignatureBytes.new(raw)
    end

    # Verifies an Ed25519 signature against a message.
    #
    # Mirrors `verifySignature(key, signature, data)` in TypeScript.
    # Returns false rather than raising on mismatch, matching the TS return type.
    #
    # @param verify_key  [RbNaCl::VerifyKey]
    # @param sig_bytes   [SignatureBytes]
    # @param data        [String] binary string that was signed
    sig { params(verify_key: T.untyped, sig_bytes: SignatureBytes, data: String).returns(T::Boolean) }
    def verify_signature(verify_key, sig_bytes, data)
      verify_key.verify(sig_bytes.value, data.b)
      true
    rescue RbNaCl::BadSignatureError
      false
    end

    # Convenience: encode a SignatureBytes to a base58 Signature string.
    sig { params(sig_bytes: SignatureBytes).returns(Signature) }
    def encode_signature(sig_bytes)
      Signature.new(Encoding::Base58.encode(sig_bytes.value))
    end

    # Convenience: decode a base58 Signature string to SignatureBytes.
    sig { params(sig: Signature).returns(SignatureBytes) }
    def decode_signature(sig)
      bytes = Encoding::Base58.decode(sig.value)
      signature_bytes(bytes)
    end
  end
end
