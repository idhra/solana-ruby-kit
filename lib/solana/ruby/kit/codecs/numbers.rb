# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Codecs
    # Numeric codecs — mirrors @solana/codecs-numbers.
    # All pack/unpack directives follow Ruby's Array#pack notation.
    # Default endian is :little (Solana is always little-endian on-chain).
    #
    # Fixed sizes (bytes):
    #   u8/i8 = 1, u16/i16 = 2, u32/i32 = 4, u64/i64 = 8,
    #   u128/i128 = 16, f32 = 4, f64 = 8
    module Numbers
      extend T::Sig

      # `extend self`, not `module_function`: both expose these as module
      # methods, but module_function also marks the instance methods PRIVATE,
      # and `Codecs extend Numbers` then inherits that privacy - which silently
      # defeated the "directly available as Codecs.x" intent in codecs.rb.
      extend self

      # ── Multi-byte integers ──────────────────────────────────────────────────

      # Shared implementation behind u128 / i128 / u256 / i256.
      #
      # Upstream splits these values into 64-bit words because a JS `DataView`
      # has no accessor wider than 64 bits. Ruby's Integer is arbitrary
      # precision, so there is nothing to split: the value is shifted out one
      # byte at a time and reassembled the same way, which keeps a single
      # implementation correct for any +byte_count+.
      #
      # +signed+ selects two's-complement interpretation over +byte_count * 8+
      # bits, so negative values round-trip.
      sig { params(byte_count: Integer, signed: T::Boolean, endian: Symbol).returns(Codec) }
      def big_int_codec(byte_count, signed:, endian: :little)
        bits = byte_count * 8
        enc = Encoder.new(fixed_size: byte_count) do |v|
          n = Kernel.Integer(v)
          n += (1 << bits) if signed && n.negative?
          out = Array.new(byte_count) do
            byte = n & 0xFF
            n >>= 8
            byte
          end
          # `out` is least-significant-byte first.
          (endian == :little ? out : out.reverse).pack('C*')
        end
        dec = Decoder.new(fixed_size: byte_count) do |bytes, offset|
          slice = bytes.b.byteslice(offset, byte_count) || ("\x00" * byte_count).b
          arr   = T.cast(T.unsafe(slice).unpack('C*'), T::Array[Integer])
          arr   = arr.reverse if endian == :little
          n     = arr.reduce(0) { |acc, byte| (acc << 8) | byte }
          n -= (1 << bits) if signed && n >= (1 << (bits - 1))
          [n, byte_count]
        end
        Codec.new(enc, dec)
      end

      # ── Unsigned integers ────────────────────────────────────────────────────

      sig { returns(Codec) }
      def u8_codec
        enc = Encoder.new(fixed_size: 1) { |v| [Kernel.Integer(v)].pack('C') }
        dec = Decoder.new(fixed_size: 1) do |bytes, offset|
          [bytes.b.byteslice(offset, 1)&.unpack1('C') || 0, 1]
        end
        Codec.new(enc, dec)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def u16_codec(endian: :little)
        dir = endian == :little ? 'v' : 'n'
        enc = Encoder.new(fixed_size: 2) { |v| [Kernel.Integer(v)].pack(dir) }
        dec = Decoder.new(fixed_size: 2) do |bytes, offset|
          [bytes.b.byteslice(offset, 2)&.unpack1(dir) || 0, 2]
        end
        Codec.new(enc, dec)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def u32_codec(endian: :little)
        dir = endian == :little ? 'V' : 'N'
        enc = Encoder.new(fixed_size: 4) { |v| [Kernel.Integer(v)].pack(dir) }
        dec = Decoder.new(fixed_size: 4) do |bytes, offset|
          [bytes.b.byteslice(offset, 4)&.unpack1(dir) || 0, 4]
        end
        Codec.new(enc, dec)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def u64_codec(endian: :little)
        dir = endian == :little ? 'Q<' : 'Q>'
        enc = Encoder.new(fixed_size: 8) { |v| [Kernel.Integer(v)].pack(dir) }
        dec = Decoder.new(fixed_size: 8) do |bytes, offset|
          [bytes.b.byteslice(offset, 8)&.unpack1(dir) || 0, 8]
        end
        Codec.new(enc, dec)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def u128_codec(endian: :little)
        big_int_codec(16, signed: false, endian: endian)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def u256_codec(endian: :little)
        big_int_codec(32, signed: false, endian: endian)
      end

      # ── Signed integers ──────────────────────────────────────────────────────

      sig { returns(Codec) }
      def i8_codec
        enc = Encoder.new(fixed_size: 1) { |v| [Kernel.Integer(v)].pack('c') }
        dec = Decoder.new(fixed_size: 1) do |bytes, offset|
          [bytes.b.byteslice(offset, 1)&.unpack1('c') || 0, 1]
        end
        Codec.new(enc, dec)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def i16_codec(endian: :little)
        dir = endian == :little ? 's<' : 's>'
        enc = Encoder.new(fixed_size: 2) { |v| [Kernel.Integer(v)].pack(dir) }
        dec = Decoder.new(fixed_size: 2) do |bytes, offset|
          [bytes.b.byteslice(offset, 2)&.unpack1(dir) || 0, 2]
        end
        Codec.new(enc, dec)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def i32_codec(endian: :little)
        dir = endian == :little ? 'l<' : 'l>'
        enc = Encoder.new(fixed_size: 4) { |v| [Kernel.Integer(v)].pack(dir) }
        dec = Decoder.new(fixed_size: 4) do |bytes, offset|
          [bytes.b.byteslice(offset, 4)&.unpack1(dir) || 0, 4]
        end
        Codec.new(enc, dec)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def i64_codec(endian: :little)
        dir = endian == :little ? 'q<' : 'q>'
        enc = Encoder.new(fixed_size: 8) { |v| [Kernel.Integer(v)].pack(dir) }
        dec = Decoder.new(fixed_size: 8) do |bytes, offset|
          [bytes.b.byteslice(offset, 8)&.unpack1(dir) || 0, 8]
        end
        Codec.new(enc, dec)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def i128_codec(endian: :little)
        big_int_codec(16, signed: true, endian: endian)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def i256_codec(endian: :little)
        big_int_codec(32, signed: true, endian: endian)
      end

      # ── Floating point ───────────────────────────────────────────────────────

      sig { params(endian: Symbol).returns(Codec) }
      def f32_codec(endian: :little)
        dir = endian == :little ? 'e' : 'g'
        enc = Encoder.new(fixed_size: 4) { |v| [Kernel.Float(v)].pack(dir) }
        dec = Decoder.new(fixed_size: 4) do |bytes, offset|
          [bytes.b.byteslice(offset, 4)&.unpack1(dir) || 0.0, 4]
        end
        Codec.new(enc, dec)
      end

      sig { params(endian: Symbol).returns(Codec) }
      def f64_codec(endian: :little)
        dir = endian == :little ? 'E' : 'G'
        enc = Encoder.new(fixed_size: 8) { |v| [Kernel.Float(v)].pack(dir) }
        dec = Decoder.new(fixed_size: 8) do |bytes, offset|
          [bytes.b.byteslice(offset, 8)&.unpack1(dir) || 0.0, 8]
        end
        Codec.new(enc, dec)
      end

      # ── Short vector (Solana compact-u16) ────────────────────────────────────
      # Variable-length encoding used in transaction wire format.
      # Each byte uses the 7 low bits for data and bit 7 as a continuation flag.

      sig { returns(Codec) }
      def compact_u16_codec
        enc = Encoder.new do |v|
          n = Kernel.Integer(v)
          Kernel.raise ArgumentError, "compact_u16 value out of range: #{n}" if n > 0xFFFF || n.negative?

          bytes = []
          Kernel.loop do
            low7 = n & 0x7F
            n >>= 7
            bytes << (n.positive? ? (low7 | 0x80) : low7)
            break if n.zero?
          end
          bytes.pack('C*')
        end
        dec = Decoder.new do |bytes, offset|
          b  = bytes.b
          n  = 0
          shift = 0
          consumed = 0
          Kernel.loop do
            byte = b.byteslice(offset + consumed, 1)&.unpack1('C') || 0
            consumed += 1
            n |= (byte & 0x7F) << shift
            shift += 7
            break if (byte & 0x80).zero?
          end
          [n, consumed]
        end
        Codec.new(enc, dec)
      end
    end
  end
end
