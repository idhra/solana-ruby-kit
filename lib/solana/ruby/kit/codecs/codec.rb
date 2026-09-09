# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Codecs
    extend T::Sig
    # A Codec combines an Encoder and a Decoder for the same type.
    # It also provides combinators that mirror @solana/codecs-core helpers:
    #   fix_codec_size, add_codec_size_prefix, offset_codec, reverse_codec
    class Codec
      extend T::Sig

      sig { returns(Encoder) }
      attr_reader :encoder

      sig { returns(Decoder) }
      attr_reader :decoder

      sig { params(encoder: Encoder, decoder: Decoder).void }
      def initialize(encoder, decoder)
        @encoder = encoder
        @decoder = decoder
      end

      # Build a Codec from separate Encoder and Decoder.
      sig { params(encoder: Encoder, decoder: Decoder).returns(Codec) }
      def self.combine(encoder, decoder)
        new(encoder, decoder)
      end

      # Delegate encode / decode for convenience.
      sig { params(value: T.untyped).returns(String) }
      def encode(value) = @encoder.encode(value)

      sig { params(bytes: String, offset: Integer).returns([T.untyped, Integer]) }
      def decode(bytes, offset: 0) = @decoder.decode(bytes, offset: offset)

      sig { returns(T.nilable(Integer)) }
      def fixed_size = @encoder.fixed_size

      # Return a new Codec whose Encoder maps values through +map_fn+ before
      # encoding (pre-encode transform).
      sig { params(map_fn: T.proc.params(value: T.untyped).returns(T.untyped)).returns(Codec) }
      def transform_encoder(&map_fn)
        original_enc = @encoder
        new_enc = Encoder.new(fixed_size: original_enc.fixed_size, max_size: original_enc.max_size) do |value|
          original_enc.encode(map_fn.call(value))
        end
        Codec.new(new_enc, @decoder)
      end

      # Return a new Codec whose Decoder maps decoded values through +map_fn+
      # (post-decode transform).
      sig { params(map_fn: T.proc.params(value: T.untyped).returns(T.untyped)).returns(Codec) }
      def transform_decoder(&map_fn)
        original_dec = @decoder
        new_dec = Decoder.new(fixed_size: original_dec.fixed_size) do |bytes, offset|
          value, consumed = original_dec.decode(bytes, offset: offset)
          [map_fn.call(value), consumed]
        end
        Codec.new(@encoder, new_dec)
      end
    end

    # ── Combinators ─────────────────────────────────────────────────────────────

    extend self

    # Return a Codec whose output is always exactly +size+ bytes
    # (zero-padded on right, truncated if too large).
    sig { params(codec: Codec, size: Integer).returns(Codec) }
    def fix_codec_size(codec, size)
      enc = Encoder.new(fixed_size: size) do |value|
        raw = codec.encode(value)
        if raw.bytesize < size
          raw.b + ("\x00".b * (size - raw.bytesize))
        else
          raw.b[0, size] || ''.b
        end
      end
      dec = Decoder.new(fixed_size: size) do |bytes, offset|
        slice = bytes.b.byteslice(offset, size) || ''.b
        value, = codec.decoder.decode(slice, offset: 0)
        [value, size]
      end
      Codec.new(enc, dec)
    end

    # Prefix encoded data with its byte length using +prefix_codec+
    # (typically a u32 little-endian codec).
    sig { params(codec: Codec, prefix_codec: Codec).returns(Codec) }
    def add_codec_size_prefix(codec, prefix_codec)
      enc = Encoder.new do |value|
        data   = codec.encode(value)
        prefix = prefix_codec.encode(data.bytesize)
        prefix + data
      end
      dec = Decoder.new do |bytes, offset|
        len, prefix_size = prefix_codec.decode(bytes, offset: offset)
        value, data_size = codec.decode(bytes, offset: offset + prefix_size)
        [value, prefix_size + data_size]
      end
      Codec.new(enc, dec)
    end

    # Shift the decode offset by +pre_offset+ before decoding and add
    # +post_offset+ to the consumed byte count afterwards.
    sig do
      params(codec: Codec, pre_offset: Integer, post_offset: Integer).returns(Codec)
    end
    def offset_codec(codec, pre_offset: 0, post_offset: 0)
      enc = Encoder.new(fixed_size: codec.fixed_size) { |v| codec.encode(v) }
      dec = Decoder.new(fixed_size: codec.fixed_size) do |bytes, offset|
        value, consumed = codec.decode(bytes, offset: offset + pre_offset)
        [value, consumed + post_offset]
      end
      Codec.new(enc, dec)
    end

    # Reverse the byte order of the encoded output (and input).
    sig { params(codec: Codec).returns(Codec) }
    def reverse_codec(codec)
      enc = Encoder.new(fixed_size: codec.fixed_size) do |value|
        codec.encode(value).b.reverse
      end
      dec = Decoder.new(fixed_size: codec.fixed_size) do |bytes, offset|
        size    = codec.fixed_size || bytes.bytesize - offset
        slice   = bytes.b.byteslice(offset, size) || ''.b
        value, = codec.decode(slice.reverse, offset: 0)
        [value, size]
      end
      Codec.new(enc, dec)
    end
  end
end
