# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Codecs
    # A size strategy for +array_codec+ / +map_codec+ / +set_codec+ where the
    # collection ends when the bytes at the next item position match a constant
    # +sentinel+. Mirrors upstream's `ArrayLikeCodecSentinelSize`
    # (`{ __kind: 'sentinel', sentinel, strategy? }`), itself a mirror of
    # Codama's `sentinelCountNode`.
    #
    # Unlike a sentinel searched for in the byte stream, this one is compared at
    # item boundaries only, so its bytes may occur *inside* an item without
    # terminating the collection.
    #
    # +strategy+ controls whether the sentinel is written and required:
    # - +:required+ (default) - written after the last item; decoding raises
    #   +CODECS__SENTINEL_MISSING_AT_END_OF_BYTES+ if the bytes run out first.
    # - +:optional+ - written, but decoding also stops at the end of the bytes,
    #   to tolerate tightly sized or legacy data that lacks it.
    # - +:omitted+ - never written; decoding stops at the end of the bytes, and
    #   consumes the sentinel if one happens to be there.
    #
    # Two invariants must hold for a round trip, and - as upstream - the codec
    # does NOT enforce them:
    # 1. No item may *begin* with the sentinel's bytes; decoding cannot tell
    #    such an item from the terminator and stops early.
    # 2. Under +:optional+ / +:omitted+ the sentinel must be no wider than the
    #    smallest possible item, or a short trailing item is silently dropped:
    #    decoding stops once fewer bytes than the sentinel remain.
    class SentinelSize < T::Struct
      STRATEGIES = T.let(%i[required optional omitted].freeze, T::Array[Symbol])

      const :sentinel, String
      const :strategy, Symbol, default: :required
    end

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
      # Decodes to a Hash with Symbol keys. Encode takes a Hash keyed by either
      # form, whichever way the field was named, so a decoded value re-encodes.
      sig { params(fields: T::Array[[T.any(String, Symbol), Codec]]).returns(Codec) }
      def struct_codec(fields)
        fixed = fields.all? { |_, c| c.fixed_size }
        total = fixed ? fields.sum { |_, c| T.must(c.fixed_size) } : nil

        enc = Encoder.new(fixed_size: total) do |value|
          h = T.cast(value, T::Hash[T.untyped, T.untyped])
          fields.map do |name, codec|
            # key? rather than `h[name] || ...`, which would skip a false value.
            key = [name, name.to_sym, name.to_s].find { |k| h.key?(k) }
            codec.encode(key.nil? ? nil : h[key])
          end.join.b
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

      # Encode/decode an array, one +element_codec+ value per item. +size+
      # picks how the item count is stored - mirrors upstream's
      # `ArrayLikeCodecSize`:
      #
      # - +nil+ (default): a u32 little-endian count prefix.
      # - a Codec, e.g. +u16_codec+ or +compact_u16_codec+: the count prefix is
      #   written and read with that codec instead.
      # - an Integer: a fixed item count with no prefix. Encoding an array of
      #   any other length raises +CODECS__INVALID_NUMBER_OF_ITEMS+.
      # - +:remainder+: no prefix; decoding reads items until the bytes run out,
      #   so the array must be the last thing in the buffer.
      # - a SentinelSize: no prefix; the array ends at a sentinel. See
      #   SentinelSize for the strategies and the invariants you must uphold.
      #
      # When the count is a prefix and there are not enough bytes left to read
      # it, the decoder yields an empty array rather than failing. That is
      # deliberate: it lets a program append a collection to an existing
      # account layout and still decode accounts written before the change.
      # Formats that cannot accept that leniency - borsh, for one, requires the
      # prefix to be present - can pass +require_size_prefix: true+ to make a
      # truncated buffer raise instead. The option has no effect on the other
      # strategies, none of which carries a prefix.
      #
      # +description+ names the codec in errors; it defaults to +'array'+.
      sig do
        params(
          element_codec:       Codec,
          size:                T.nilable(T.any(Integer, Symbol, Codec, SentinelSize)),
          require_size_prefix: T::Boolean,
          description:         T.nilable(String)
        ).returns(Codec)
      end
      def array_codec(element_codec, size: nil, require_size_prefix: false, description: nil)
        description ||= 'array'
        case size
        when nil          then ArrayLikeSize.prefixed(element_codec, Numbers.u32_codec, require_size_prefix)
        when Codec        then ArrayLikeSize.prefixed(element_codec, size, require_size_prefix)
        when Integer      then ArrayLikeSize.fixed_count(element_codec, size, description)
        when SentinelSize then ArrayLikeSize.sentinel(element_codec, size, description)
        when :remainder   then ArrayLikeSize.remainder(element_codec)
        else
          Kernel.raise ArgumentError,
                       "Unknown array size #{size.inspect}; expected nil, a number Codec, an Integer, " \
                       ':remainder or a SentinelSize'
        end
      end

      # Encode/decode a Hash.
      # Encoded as: [length prefix] + [key, value, key, value, ...]
      # See +array_codec+ for what +size+ and +require_size_prefix+ do; +size+
      # counts entries, and a SentinelSize is compared at entry (key)
      # boundaries.
      sig do
        params(
          key_codec:           Codec,
          value_codec:         Codec,
          size:                T.nilable(T.any(Integer, Symbol, Codec, SentinelSize)),
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
      # See +array_codec+ for what +size+ and +require_size_prefix+ do.
      sig do
        params(
          element_codec:       Codec,
          size:                T.nilable(T.any(Integer, Symbol, Codec, SentinelSize)),
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

    # The per-strategy builders behind +array_codec+ (and so +map_codec+ and
    # +set_codec+). Call those instead. Kept out of DataStructures on purpose:
    # everything there is re-exported as a public +Codecs.*+ helper, and these
    # are an implementation detail.
    module ArrayLikeSize
      extend T::Sig
      extend self

      # A count prefix written and read with +prefix+.
      sig { params(element_codec: Codec, prefix: Codec, require_size_prefix: T::Boolean).returns(Codec) }
      def prefixed(element_codec, prefix, require_size_prefix)
        enc = Encoder.new do |values|
          arr = T.cast(values, T::Array[T.untyped])
          prefix.encode(arr.length) + arr.map { |v| element_codec.encode(v) }.join.b
        end
        dec = Decoder.new do |bytes, offset|
          # A fixed-size prefix needs all its bytes; a variable-size one (e.g.
          # compact_u16) needs at least one, and raises for itself if the rest
          # are missing.
          prefix_size = prefix.fixed_size || 1
          remaining   = [bytes.bytesize - offset, 0].max
          if remaining < prefix_size
            # The prefix is missing or truncated. By default that decodes to an
            # empty collection having consumed nothing; under
            # +require_size_prefix+ it is an error.
            Kernel.raise SolanaError.new(
              SolanaError::CODECS__INVALID_BYTE_LENGTH,
              { expected: prefix_size, actual: remaining }
            ) if require_size_prefix

            next [[], 0]
          end
          count, consumed = prefix.decode(bytes, offset: offset)
          result = Array.new(Kernel.Integer(count)) do
            val, n = element_codec.decode(bytes, offset: offset + consumed)
            consumed += n
            val
          end
          [result, consumed]
        end
        Codec.new(enc, dec)
      end

      # Exactly +count+ items and no prefix. Fixed-size when the items are - and
      # always for a count of zero, whatever the item.
      sig { params(element_codec: Codec, count: Integer, description: String).returns(Codec) }
      def fixed_count(element_codec, count, description)
        item_size = element_codec.fixed_size
        fixed     = count.zero? ? 0 : (item_size && count * item_size)
        enc = Encoder.new(fixed_size: fixed) do |values|
          arr = T.cast(values, T::Array[T.untyped])
          unless arr.length == count
            Kernel.raise SolanaError.new(
              SolanaError::CODECS__INVALID_NUMBER_OF_ITEMS,
              { codec_description: description, expected: count, actual: arr.length }
            )
          end
          arr.map { |v| element_codec.encode(v) }.join.b
        end
        dec = Decoder.new(fixed_size: fixed) do |bytes, offset|
          consumed = 0
          result = Array.new(count) do
            val, n = element_codec.decode(bytes, offset: offset + consumed)
            consumed += n
            val
          end
          [result, consumed]
        end
        Codec.new(enc, dec)
      end

      # No prefix; decoding reads items until the bytes run out.
      sig { params(element_codec: Codec).returns(Codec) }
      def remainder(element_codec)
        enc = Encoder.new do |values|
          T.cast(values, T::Array[T.untyped]).map { |v| element_codec.encode(v) }.join.b
        end
        dec = Decoder.new do |bytes, offset|
          result   = []
          consumed = 0
          while offset + consumed < bytes.bytesize
            val, n = element_codec.decode(bytes, offset: offset + consumed)
            # An item that consumes nothing would never reach the end.
            Kernel.raise ArgumentError, 'a :remainder array item decoded zero bytes' if n.zero?

            result << val
            consumed += n
          end
          [result, consumed]
        end
        Codec.new(enc, dec)
      end

      # Ends at a sentinel instead of carrying a count. Always variable-size:
      # the item count is only known by reading up to the sentinel.
      sig { params(element_codec: Codec, size: SentinelSize, description: String).returns(Codec) }
      def sentinel(element_codec, size, description)
        sentinel = size.sentinel.b
        strategy = size.strategy
        # Raised at construction, as upstream does for both the encoder and the
        # decoder: an empty sentinel matches everywhere and delimits nothing.
        Kernel.raise SolanaError.new(SolanaError::CODECS__SENTINEL_MUST_NOT_BE_EMPTY) if sentinel.empty?
        unless SentinelSize::STRATEGIES.include?(strategy)
          Kernel.raise ArgumentError,
                       "Unknown sentinel strategy #{strategy.inspect}; expected one of #{SentinelSize::STRATEGIES.inspect}"
        end

        enc = Encoder.new do |values|
          body = T.cast(values, T::Array[T.untyped]).map { |v| element_codec.encode(v) }.join.b
          strategy == :omitted ? body : body + sentinel
        end
        dec = Decoder.new do |bytes, offset|
          result   = []
          consumed = 0
          Kernel.loop do
            position = offset + consumed
            if position + sentinel.bytesize > bytes.bytesize
              # Not enough bytes remain to hold the sentinel.
              if strategy == :required
                Kernel.raise SolanaError.new(
                  SolanaError::CODECS__SENTINEL_MISSING_AT_END_OF_BYTES,
                  { codec_description: description, hex_sentinel: sentinel.unpack1('H*'), sentinel: sentinel }
                )
              end
              break
            end
            if Bytes.contains_bytes?(bytes, sentinel, offset: position)
              # The sentinel is present; consume it and stop.
              consumed += sentinel.bytesize
              break
            end
            val, n = element_codec.decode(bytes, offset: position)
            result << val
            consumed += n
          end
          [result, consumed]
        end
        Codec.new(enc, dec)
      end
    end
  end
end
