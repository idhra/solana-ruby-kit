# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Encoding
    # Base58 codec using the Bitcoin/Solana alphabet (no check bytes).
    # This module provides the shared base58 encoding used by both
    # Solana::Ruby::Kit::Addresses and Solana::Ruby::Kit::Keys::Signatures.
    module Base58
      extend T::Sig
      ALPHABET = T.let(
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz',
        String
      )

      extend self

      # Encodes a binary String to a base58 string.
      sig { params(bytes: String).returns(String) }
      def encode(bytes)
        # Each leading zero byte maps to a leading '1'.
        leading_ones = 0
        bytes.each_byte { |b| b == 0 ? leading_ones += 1 : break }

        # Convert big-endian byte string to an integer.
        n = bytes.unpack1('H*').to_i(16)

        result = +''
        while n > 0
          result.prepend(T.must(ALPHABET[n % 58]))
          n /= 58
        end

        ('1' * leading_ones) + result
      end

      # Decodes a base58 string to a binary String.
      # Raises ArgumentError if the string contains characters not in the alphabet.
      sig { params(str: String).returns(String) }
      def decode(str)
        # Each leading '1' maps to a leading zero byte.
        leading_zeros = 0
        str.each_char { |c| c == '1' ? leading_zeros += 1 : break }

        n = 0
        str.each_char do |c|
          idx = ALPHABET.index(c)
          Kernel.raise ArgumentError, "Invalid base58 character: #{c.inspect}" if idx.nil?

          n = n * 58 + idx
        end

        # Convert integer back to a big-endian byte string.
        hex = n.zero? ? '' : n.to_s(16)
        hex = hex.rjust((hex.length + 1) & ~1, '0')  # guarantee even hex length

        raw = [hex].pack('H*')
        ("\x00" * leading_zeros + raw).b
      end
    end
  end
end
