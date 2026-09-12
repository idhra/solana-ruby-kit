# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Codecs
    # Data-structure codecs — mirrors @solana/codecs-data-structures.
    module DataStructures
      extend T::Sig

      # `extend self`, not `module_function`: both expose these as module
      # methods, but module_function also marks the instance methods PRIVATE,
      # and `Codecs extend DataStructures` then inherits that privacy - which silently
      # defeated the "directly available as Codecs.x" intent in codecs.rb.
      extend self

      # Encode/decode a fixed ordered list of named fields.
      # +fields+ is an Array of [name, codec] pairs (name can be String or Symbol).
      # Encodes to a Hash on decode; expects a Hash for encode.
      sig { params(fields: T::Array[[T.any(String, Symbol), Codec]]).returns(Codec) }
      def struct_codec(fields)
        fixed = fields.all? { |_, c| c.fixed_size }
        total = fixed ? fields.sum { |_, c| T.must(c.fixed_size) } : nil

        enc = Encoder.new(fixed_size: total) do |value|
          h = T.cast(value, T::Hash[T.untyped, T.untyped])
          fields.map { |name, codec| codec.encode(h[name] || h[name.to_s]) }.join.b
        end
        dec = Decoder.new(fixed_size: total) do |bytes, offset|
          result   = {}
          consumed = 0
          fields.each do |name, codec|
            val, n = codec.decode(bytes, offset: offset + consumed)
            result[name.to_sym] = val
            consumed += n
          end
          [result, consumed]
        end
        Codec.new(enc, dec)
      end

      # Encode/decode a fixed positional tuple (Array of values, one codec each).
      sig { params(codecs: T::Array[Codec]).returns(Codec) }
      def tuple_codec(codecs)
        fixed = codecs.all?(&:fixed_size)
        total = fixed ? codecs.sum { |c| T.must(c.fixed_size) } : nil

        enc = Encoder.new(fixed_size: total) do |values|
          arr = T.cast(values, T::Array[T.untyped])
          codecs.each_with_index.map { |c, i| c.encode(arr[i]) }.join.b
        end
        dec = Decoder.new(fixed_size: total) do |bytes, offset|
          result   = []
          consumed = 0
          codecs.each do |c|
            val, n = c.decode(bytes, offset: offset + consumed)
            result << val
            consumed += n
          end
          [result, consumed]
        end
        Codec.new(enc, dec)
      end

      # Encode/decode a variable-length array with a u32LE length prefix.
      # When +size+ is given the array has a fixed element count (no prefix).
      #
      # When the size is stored as a prefix and there are not enough bytes left
      # to read it, the decoder yields an empty array rather than failing. That
      # is deliberate: it lets a program append a collection to an existing
      # account layout and still decode accounts written before the change.
      # Formats that cannot accept that leniency - borsh, for one, requires the
      # prefix to be present - can pass +require_size_prefix: true+ to make a
      # truncated buffer raise instead. The option has no effect when +size+ is
      # given, since a fixed-count array carries no prefix.
      sig do
        params(
          element_codec:       Codec,
          size:                T.nilable(Integer),
          require_size_prefix: T::Boolean
        ).returns(Codec)
      end
      def array_codec(element_codec, size: nil, require_size_prefix: false)
        if size
          fixed = element_codec.fixed_size ? size * T.must(element_codec.fixed_size) : nil
          enc = Encoder.new(fixed_size: fixed) do |values|
            T.cast(values, T::Array[T.untyped]).map { |v| element_codec.encode(v) }.join.b
          end
          dec = Decoder.new(fixed_size: fixed) do |bytes, offset|
            result   = []
            consumed = 0
            size.times do
              val, n = element_codec.decode(bytes, offset: offset + consumed)
              result << val
              consumed += n
            end
            [result, consumed]
          end
          Codec.new(enc, dec)
        else
          prefix = Numbers.u32_codec
          enc = Encoder.new do |values|
            arr    = T.cast(values, T::Array[T.untyped])
            header = prefix.encode(arr.length)
            body   = arr.map { |v| element_codec.encode(v) }.join.b
            header + body
          end
          dec = Decoder.new do |bytes, offset|
            prefix_size = T.must(prefix.fixed_size)
            remaining   = [bytes.b.bytesize - offset, 0].max
            if remaining < prefix_size
              # The prefix is missing or truncated. By default that decodes to
              # an empty collection having consumed nothing; under
              # +require_size_prefix+ it is an error.
              Kernel.raise SolanaError.new(
                SolanaError::CODECS__INVALID_BYTE_LENGTH,
                { expected: prefix_size, actual: remaining }
              ) if require_size_prefix

              next [[], 0]
            end
            len, prefix_bytes = prefix.decode(bytes, offset: offset)
            result   = []
            consumed = prefix_bytes
            len.times do
              val, n = element_codec.decode(bytes, offset: offset + consumed)
              result << val
              consumed += n
            end
            [result, consumed]
          end
          Codec.new(enc, dec)
        end
      end

      # Encode/decode a Hash.
      # Encoded as: [length prefix] + [key, value, key, value, ...]
      # See +array_codec+ for what +require_size_prefix+ does.
      sig do
        params(
          key_codec:           Codec,
          value_codec:         Codec,
          size:                T.nilable(Integer),
          require_size_prefix: T::Boolean
        ).returns(Codec)
      end
      def map_codec(key_codec, value_codec, size: nil, require_size_prefix: false)
        pair_codec = tuple_codec([key_codec, value_codec])
        array_codec(pair_codec, size: size, require_size_prefix: require_size_prefix).transform_decoder do |pairs|
          pairs.each_with_object({}) { |(k, v), h| h[k] = v }
        end.transform_encoder do |hash|
          T.cast(hash, T::Hash[T.untyped, T.untyped]).map { |k, v| [k, v] }
        end
      end

      # Encode/decode a Set (stored as an array of unique elements).
      # See +array_codec+ for what +require_size_prefix+ does.
      sig do
        params(
          element_codec:       Codec,
          size:                T.nilable(Integer),
          require_size_prefix: T::Boolean
        ).returns(Codec)
      end
      def set_codec(element_codec, size: nil, require_size_prefix: false)
        array_codec(element_codec, size: size, require_size_prefix: require_size_prefix)
          .transform_encoder { |s| T.cast(s, T::Set[T.untyped]).to_a }
          .transform_decoder { |arr| Set.new(arr) }
      end

      # Discriminated-union codec.
      # +variants+ is an Array of [tag, codec] pairs; +discriminator_codec+ encodes
      # the tag (typically a u8 codec).
      # Encode expects +[tag, value]+; decode returns +[tag, value]+.
      sig do
        params(
          variants:           T::Array[[T.untyped, Codec]],
          discriminator_codec: Codec
        ).returns(Codec)
      end
      def union_codec(variants, discriminator_codec)
        tag_to_codec  = variants.to_h
        idx_to_tag    = variants.map(&:first)

        enc = Encoder.new do |tagged_value|
          tag, value = T.cast(tagged_value, [T.untyped, T.untyped])
          inner_codec = tag_to_codec.fetch(tag) { Kernel.raise ArgumentError, "Unknown union tag: #{tag}" }
          discriminator_codec.encode(idx_to_tag.index(tag)) + inner_codec.encode(value)
        end
        dec = Decoder.new do |bytes, offset|
          idx, disc_size = discriminator_codec.decode(bytes, offset: offset)
          tag        = idx_to_tag.fetch(idx) { Kernel.raise ArgumentError, "Unknown union discriminant: #{idx}" }
          inner      = tag_to_codec.fetch(tag)
          value, n   = inner.decode(bytes, offset: offset + disc_size)
          [[tag, value], disc_size + n]
        end
        Codec.new(enc, dec)
      end

      # Option codec — 1 byte discriminant (0 = None, 1 = Some) + optional value.
      # Encode expects an Solana::Ruby::Kit::Options::Option; decode returns one.
      sig { params(value_codec: Codec).returns(Codec) }
      def option_codec(value_codec)
        disc = Numbers.u8_codec
        enc = Encoder.new do |option|
          if option.is_a?(Solana::Ruby::Kit::Options::Some)
            disc.encode(1) + value_codec.encode(option.value)
          else
            disc.encode(0)
          end
        end
        dec = Decoder.new do |bytes, offset|
          flag, flag_size = disc.decode(bytes, offset: offset)
          if flag == 1
            val, n = value_codec.decode(bytes, offset: offset + flag_size)
            [Solana::Ruby::Kit::Options::Some.new(val), flag_size + n]
          else
            [Solana::Ruby::Kit::Options::None.constants, flag_size]
          end
        end
        Codec.new(enc, dec)
      end
    end
  end
end
