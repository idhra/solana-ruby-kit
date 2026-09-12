# typed: strict
# frozen_string_literal: true

require 'base64'

module Solana::Ruby::Kit
  module Codecs
    # String codecs — mirrors @solana/codecs-strings.
    module Strings
      extend T::Sig

      # `extend self`, not `module_function`: both expose these as module
      # methods, but module_function also marks the instance methods PRIVATE,
      # and `Codecs extend Strings` then inherits that privacy - which silently
      # defeated the "directly available as Codecs.x" intent in codecs.rb.
      extend self

      # Byte order mark, U+FEFF, in its UTF-8 encoding.
      BOM = T.let("\xEF\xBB\xBF".b.freeze, String)

      # Remove every null character from a decoded string.
      # Mirrors `removeNullCharacters`.
      sig { params(value: String).returns(String) }
      def remove_null_characters(value)
        value.delete("\x00")
      end

      # Find the first malformed UTF-8 sequence in +bytes+, starting at +offset+.
      # Returns the byte offset at which it starts, or -1 when the bytes are
      # well-formed.
      #
      # This rejects everything the Unicode standard rejects: unexpected
      # continuation bytes, overlong encodings, encoded surrogates, code points
      # above U+10FFFF and truncated sequences. Ruby's own +valid_encoding?+
      # answers the same question, but only yes or no - this reports *where*,
      # which is what the error context needs.
      # Mirrors `findMalformedUtf8SequenceOffset`.
      sig { params(bytes: String, offset: Integer).returns(Integer) }
      def find_malformed_utf8_sequence_offset(bytes, offset = 0)
        arr    = T.cast(T.unsafe(bytes.b).unpack('C*'), T::Array[Integer])
        length = arr.length
        index  = offset
        while index < length
          lead = T.must(arr[index])
          min  = 0x80
          max  = 0xBF
          if lead < 0x80
            index += 1
            next
          elsif lead >= 0xC2 && lead <= 0xDF
            count = 1
          elsif lead >= 0xE0 && lead <= 0xEF
            count = 2
            min = 0xA0 if lead == 0xE0 # Overlong.
            max = 0x9F if lead == 0xED # Encoded surrogate.
          elsif lead >= 0xF0 && lead <= 0xF4
            count = 3
            min = 0x90 if lead == 0xF0 # Overlong.
            max = 0x8F if lead == 0xF4 # Above U+10FFFF.
          else
            return index
          end

          start  = index
          index += 1
          count.times do |i|
            return start if index >= length

            byte     = T.must(arr[index])
            in_range = i.zero? ? byte >= min && byte <= max : byte >= 0x80 && byte <= 0xBF
            return start unless in_range

            index += 1
          end
        end
        -1
      end

      # Raise unless +bytes+, from +offset+, form well-formed UTF-8.
      # Mirrors `assertIsWellFormedUtf8Bytes`.
      sig { params(bytes: String, offset: Integer).void }
      def assert_is_well_formed_utf8_bytes(bytes, offset = 0)
        malformed = find_malformed_utf8_sequence_offset(bytes, offset)
        return if malformed == -1

        Kernel.raise SolanaError.new(
          SolanaError::CODECS__INVALID_UTF8_BYTES,
          { bytes: bytes.b, offset: malformed }
        )
      end

      # Raise unless +value+ can be encoded as UTF-8 without loss.
      # Mirrors `assertIsWellFormedUtf8String`.
      #
      # Upstream guards against lone surrogates, which a JavaScript string can
      # hold because it is a sequence of UTF-16 code units. A Ruby String is a
      # byte sequence with an encoding tag, so the equivalent flaw is a String
      # whose bytes are not valid UTF-8. Upstream's reported +index+ counts
      # UTF-16 code units; the +index+ here is a byte offset.
      sig { params(value: String).void }
      def assert_is_well_formed_utf8_string(value)
        index = find_malformed_utf8_sequence_offset(value.b)
        return if index == -1

        Kernel.raise SolanaError.new(
          SolanaError::CODECS__INVALID_UTF8_STRING,
          { index: index, value: value }
        )
      end

      # UTF-8 string codec.
      # When +size+ is given the encoded bytes are fixed to that length
      # (zero-padded or truncated); otherwise the codec is variable-length
      # and must be used inside a size-prefixed container.
      #
      # +fatal+ rejects invalid UTF-8 instead of passing it through: on encode a
      # String whose bytes are not valid UTF-8, on decode a malformed byte
      # sequence.
      #
      # +ignore_bom+ follows TextDecoder's confusing spelling: the default,
      # +false+, *strips* a leading byte order mark; +true+ keeps it.
      #
      # +remove_null_characters+ strips every null character from the decoded
      # string, which is what makes fixed-size padded strings read back cleanly.
      # It is on by default, matching upstream, and makes the codec lossy for
      # strings that legitimately contain nulls - pass +false+ for a lossless
      # round trip.
      sig do
        params(
          size:                   T.nilable(Integer),
          fatal:                  T::Boolean,
          ignore_bom:             T::Boolean,
          remove_null_characters: T::Boolean
        ).returns(Codec)
      end
      def utf8_codec(size: nil, fatal: false, ignore_bom: false, remove_null_characters: true)
        strip_nulls = remove_null_characters
        enc = Encoder.new(fixed_size: size) do |v|
          str = v.to_s
          # Transcode anything that is not already UTF-8 (or raw bytes); a
          # UTF-8 to UTF-8 `encode` is a no-op and would not validate, which is
          # what `fatal` is for.
          str = str.encode(::Encoding::UTF_8) unless [::Encoding::UTF_8, ::Encoding::BINARY].include?(str.encoding)
          raw = str.b
          assert_is_well_formed_utf8_string(raw) if fatal
          if size
            raw.bytesize <= size ? raw.ljust(size, "\x00") : raw.byteslice(0, size) || ''.b
          else
            raw
          end
        end
        dec = Decoder.new(fixed_size: size) do |bytes, offset|
          len   = size || (bytes.bytesize - offset)
          slice = bytes.b.byteslice(offset, len) || ''.b
          assert_is_well_formed_utf8_bytes(slice) if fatal
          slice = T.must(slice.byteslice(BOM.bytesize..)) if !ignore_bom && slice.start_with?(BOM)
          str   = slice.force_encoding(::Encoding::UTF_8)
          # Non-fatal decoding substitutes U+FFFD for malformed sequences, as
          # TextDecoder does. `scrub` is Ruby's version of exactly that, and it
          # also keeps the null-stripping below from raising on invalid bytes.
          str   = str.scrub unless fatal
          str   = remove_null_characters(str) if strip_nulls
          [str, len]
        end
        Codec.new(enc, dec)
      end

      # Base58 codec — uses Solana::Ruby::Kit::Encoding::Base58.
      sig { returns(Codec) }
      def base58_codec
        enc = Encoder.new do |v|
          Solana::Ruby::Kit::Encoding::Base58.decode(v.to_s)
        end
        dec = Decoder.new do |bytes, offset|
          remaining = bytes.b.byteslice(offset..) || ''.b
          [Solana::Ruby::Kit::Encoding::Base58.encode(remaining), remaining.bytesize]
        end
        Codec.new(enc, dec)
      end

      # Base64 codec — strict (no newlines).
      sig { returns(Codec) }
      def base64_codec
        enc = Encoder.new do |v|
          Base64.strict_encode64(v.to_s)
        end
        dec = Decoder.new do |bytes, offset|
          remaining = bytes.b.byteslice(offset..) || ''.b
          [Base64.strict_decode64(remaining.force_encoding('ASCII')), remaining.bytesize]
        end
        Codec.new(enc, dec)
      end

      # Hex codec — lower-case hex string ↔ binary bytes.
      sig { returns(Codec) }
      def hex_codec
        enc = Encoder.new do |v|
          [v.to_s.tr(' ', '')].pack('H*')
        end
        dec = Decoder.new do |bytes, offset|
          remaining = bytes.b.byteslice(offset..) || ''.b
          [remaining.unpack1('H*'), remaining.bytesize]
        end
        Codec.new(enc, dec)
      end

      # Fixed-size raw bytes passthrough.
      sig { params(size: Integer).returns(Codec) }
      def bytes_codec(size)
        enc = Encoder.new(fixed_size: size) do |v|
          b = v.is_a?(String) ? v.b : v.to_s.b
          Kernel.raise ArgumentError, "Expected #{size} bytes, got #{b.bytesize}" if b.bytesize != size

          b
        end
        dec = Decoder.new(fixed_size: size) do |bytes, offset|
          slice = bytes.b.byteslice(offset, size) || ''.b
          [slice, size]
        end
        Codec.new(enc, dec)
      end

      # Bit-array codec.
      # Encodes an Array of booleans into +size+ bytes (LSB-first within each byte).
      sig { params(size: Integer).returns(Codec) }
      def bit_array_codec(size)
        total_bits = size * 8
        enc = Encoder.new(fixed_size: size) do |bits|
          arr   = T.cast(bits, T::Array[T::Boolean])
          bytes = Array.new(size, 0)
          arr.first(total_bits).each_with_index do |bit, idx|
            bytes[idx / 8] |= (1 << (idx % 8)) if bit
          end
          bytes.pack('C*')
        end
        dec = Decoder.new(fixed_size: size) do |bytes, offset|
          slice = bytes.b.byteslice(offset, size) || ''.b
          byte_arr = T.cast(T.unsafe(slice).unpack('C*'), T::Array[Integer])
          bits = byte_arr.flat_map { |byte| 8.times.map { |i| byte[i] == 1 } }
          [bits, size]
        end
        Codec.new(enc, dec)
      end
    end
  end
end
