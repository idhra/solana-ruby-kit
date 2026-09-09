# typed: strict
# frozen_string_literal: true

require_relative '../errors'
require_relative '../encoding/base58'

module Solana::Ruby::Kit
  module Addresses
    extend T::Sig
    # A validated, base58-encoded Solana address (32 bytes on-wire).
    # Mirrors the TypeScript branded type:
    #   type Address<TAddress extends string = string> = Brand<EncodedString<TAddress, 'base58'>, 'Address'>
    #
    # Because Sorbet does not support nominal/branded string types, Address is a
    # lightweight value object whose string representation is always a validated
    # base58 string.
    class Address
      extend T::Sig
      include Comparable

      sig { returns(String) }
      attr_reader :value

      sig { params(value: String).void }
      def initialize(value)
        @value = T.let(value, String)
      end

      sig { returns(String) }
      def to_s = @value

      sig { returns(String) }
      def inspect = "#<#{self.class} \"#{@value}\">"

      sig { params(other: T.untyped).returns(T.nilable(Integer)) }
      def <=>(other)
        return nil unless other.is_a?(Address)

        @value <=> other.value
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        !!(other.is_a?(Address) && @value == other.value)
      end

      sig { returns(Integer) }
      def hash = @value.hash

      alias eql? ==
    end

    # ---------------------------------------------------------------------------
    # Constants
    # ---------------------------------------------------------------------------

    # Expected byte length of a Solana address.
    ADDRESS_BYTE_LENGTH = T.let(32, Integer)

    # Minimum / maximum character lengths for a base58-encoded 32-byte address.
    ADDRESS_MIN_STR_LEN = T.let(32, Integer)
    ADDRESS_MAX_STR_LEN = T.let(44, Integer)

    extend self

    # Encodes raw bytes (binary String, length == 32) to a base58 address string.
    # Mirrors `getAddressEncoder()` in TypeScript.
    sig { params(bytes: String).returns(String) }
    def encode_address(bytes)
      Kernel.raise SolanaError.new(
        SolanaError::ADDRESSES__INVALID_BYTE_LENGTH_FOR_ADDRESS,
        byte_length: bytes.bytesize
      ) unless bytes.bytesize == ADDRESS_BYTE_LENGTH

      Encoding::Base58.encode(bytes)
    end

    # Decodes a base58 address string to a 32-byte binary String.
    # Mirrors `getAddressDecoder()` in TypeScript.
    sig { params(addr: Address).returns(String) }
    def decode_address(addr)
      bytes = Encoding::Base58.decode(addr.value)
      Kernel.raise SolanaError.new(
        SolanaError::ADDRESSES__INVALID_BYTE_LENGTH_FOR_ADDRESS,
        byte_length: bytes.bytesize
      ) unless bytes.bytesize == ADDRESS_BYTE_LENGTH

      bytes
    end

    # Returns true if the string is a syntactically valid Solana address.
    # Mirrors `isAddress()` in TypeScript.
    sig { params(putative: String).returns(T::Boolean) }
    def address?(putative)
      return false unless putative.length.between?(ADDRESS_MIN_STR_LEN, ADDRESS_MAX_STR_LEN)
      return false unless putative.chars.all? { |c| Encoding::Base58::ALPHABET.include?(c) }

      bytes = Encoding::Base58.decode(putative)
      bytes.bytesize == ADDRESS_BYTE_LENGTH
    rescue ArgumentError
      false
    end

    # Raises SolanaError if the string is not a valid Solana address.
    # Mirrors `assertIsAddress()` in TypeScript.
    sig { params(putative: String).void }
    def assert_address!(putative)
      unless putative.length.between?(ADDRESS_MIN_STR_LEN, ADDRESS_MAX_STR_LEN)
        Kernel.raise SolanaError.new(
          SolanaError::ADDRESSES__STRING_LENGTH_OUT_OF_RANGE,
          actual_length: putative.length
        )
      end

      Kernel.raise SolanaError.new(SolanaError::ADDRESSES__INVALID_BASE58_ENCODED_ADDRESS) unless address?(putative)
    end

    # Validates and wraps a string in an Address value object.
    # Mirrors `address()` in TypeScript.
    sig { params(putative: String).returns(Address) }
    def address(putative)
      assert_address!(putative)
      Address.new(putative)
    end

    # Returns a Proc that compares two Address values lexicographically,
    # matching the semantics of `getAddressComparator()` in TypeScript.
    sig { returns(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)) }
    def address_comparator
      ->(a, b) { a.value <=> b.value }
    end
  end
end
