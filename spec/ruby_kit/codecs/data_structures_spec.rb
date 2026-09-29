# typed: ignore
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyKit::Codecs::DataStructures do
  include RubyKit::Codecs::DataStructures
  include RubyKit::Codecs::Numbers
  include RubyKit::Codecs::Strings

  describe 'struct_codec' do
    let(:codec) do
      struct_codec([
        [:name,  utf8_codec(size: 4)],
        [:value, u32_codec]
      ])
    end

    it 'round-trips a hash' do
      original = { name: 'abc', value: 42 }
      name_b   = 'abc'.b + "\x00".b
      value_b  = [42].pack('V')
      encoded  = name_b + value_b

      decoded, = codec.decode(codec.encode(original))
      expect(decoded[:value]).to eq(42)
    end

    # Encode used to look up `h[name] || h[name.to_s]`: a String-named field
    # never found a Symbol key - so decode's own output would not re-encode -
    # and a false value fell through to nil.
    it 're-encodes its own decoded output when fields are named with Strings' do
      string_named = struct_codec([['value', u32_codec]])
      decoded, = string_named.decode(string_named.encode({ 'value' => 42 }))
      expect(decoded).to eq({ value: 42 })
      expect(string_named.encode(decoded)).to eq([42].pack('V'))
    end

    it 'encodes a false field value rather than skipping it' do
      flag = RubyKit::Codecs::Codec.new(
        RubyKit::Codecs::Encoder.new(fixed_size: 1) do |v|
          raise ArgumentError, 'flag is missing' if v.nil?

          v ? "\x01".b : "\x00".b
        end,
        RubyKit::Codecs::Decoder.new(fixed_size: 1) { |bytes, offset| [bytes.getbyte(offset) == 1, 1] }
      )
      checked = struct_codec([[:enabled, flag], [:locked, flag]])
      expect(checked.encode({ enabled: true, locked: false }).bytes).to eq([1, 0])
      expect(checked.encode({ 'enabled' => false, 'locked' => true }).bytes).to eq([0, 1])
    end
  end

  describe 'array_codec (prefixed)' do
    let(:codec) { array_codec(u8_codec) }

    it 'round-trips an array' do
      arr     = [1, 2, 3]
      decoded, = codec.decode(codec.encode(arr))
      expect(decoded).to eq(arr)
    end
  end

  describe 'array_codec (fixed size)' do
    let(:codec) { array_codec(u8_codec, size: 3) }

    it 'encodes without a length prefix' do
      expect(codec.encode([1, 2, 3]).bytesize).to eq(3)
    end

    it 'is fixed-size when its items are' do
      expect(codec.fixed_size).to eq(3)
      expect(array_codec(u16_codec, size: 42).fixed_size).to eq(84)
      expect(array_codec(utf8_codec, size: 3).fixed_size).to be_nil
    end

    it 'is fixed-size zero for a count of zero, whatever the item' do
      zero = array_codec(utf8_codec, size: 0)
      expect(zero.fixed_size).to eq(0)
      expect(zero.encode([])).to eq(''.b)
      expect(zero.decode(''.b)).to eq([[], 0])
    end

    it 'raises when encoding an array of a different length' do
      expect { codec.encode([1, 2]) }.to raise_error(RubyKit::SolanaError) { |e|
        expect(e.code).to eq(RubyKit::SolanaError::CODECS__INVALID_NUMBER_OF_ITEMS)
        expect(e.context).to eq(codec_description: 'array', expected: 3, actual: 2)
      }
      expect { array_codec(u8_codec, size: 2, description: 'myDescription').encode([1, 2, 3]) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.context).to eq(codec_description: 'myDescription', expected: 2, actual: 3)
          expect(e.message).to eq('Expected [myDescription] to have 2 items, got 3.')
        }
    end
  end

  describe 'array_codec (custom size prefix)' do
    def b(hex) = [hex].pack('H*')
    def hex(bytes) = bytes.unpack1('H*')

    it 'writes and reads the count with the given codec' do
      codec = array_codec(u8_codec, size: u8_codec)
      expect(hex(codec.encode([]))).to eq('00')
      expect(codec.decode(b('00'))).to eq([[], 1])
      expect(hex(codec.encode([42, 1, 2]))).to eq('032a0102')
      expect(codec.decode(b('032a0102'))).to eq([[42, 1, 2], 4])
      expect(codec.decode(b('ffff032a0102'), offset: 2)).to eq([[42, 1, 2], 4])
    end

    it 'accepts a wider fixed-size prefix' do
      codec = array_codec(u8_codec, size: u16_codec)
      expect(hex(codec.encode([42, 1, 2]))).to eq('03002a0102')
      expect(codec.decode(b('03002a0102'))).to eq([[42, 1, 2], 5])
    end

    it 'accepts a variable-size prefix such as compact_u16' do
      codec   = array_codec(u8_codec, size: compact_u16_codec)
      encoded = codec.encode([7] * 200)
      expect(encoded.byteslice(0, 2).bytes).to eq([0xc8, 0x01])
      expect(codec.decode(encoded)).to eq([[7] * 200, 202])
    end

    it 'decodes an exhausted buffer to an empty array unless the prefix is required' do
      expect(array_codec(u8_codec, size: u8_codec).decode(''.b)).to eq([[], 0])
      expect(array_codec(u8_codec, size: compact_u16_codec).decode(''.b)).to eq([[], 0])
      expect { array_codec(u8_codec, size: u8_codec, require_size_prefix: true).decode(''.b) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::CODECS__INVALID_BYTE_LENGTH)
        }
    end

    it 'lets a variable-size prefix raise for itself when truncated' do
      expect { array_codec(u8_codec, size: compact_u16_codec).decode(b('80')) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::CODECS__INVALID_BYTE_LENGTH)
          expect(e.context[:codec_description]).to eq('shortU16')
        }
    end

    it 'applies to map_codec and set_codec' do
      map = map_codec(u8_codec, u8_codec, size: u8_codec)
      expect(hex(map.encode({ 1 => 2 }))).to eq('010102')
      expect(map.decode(b('010102'))).to eq([{ 1 => 2 }, 3])

      set = set_codec(u8_codec, size: u16_codec)
      expect(hex(set.encode(Set[1, 2]))).to eq('02000102')
      expect(set.decode(b('02000102'))).to eq([Set[1, 2], 4])
    end
  end

  describe 'array_codec (remainder)' do
    def b(hex) = [hex].pack('H*')
    def hex(bytes) = bytes.unpack1('H*')

    let(:codec) { array_codec(u8_codec, size: :remainder) }

    it 'writes the items with no prefix' do
      expect(hex(codec.encode([]))).to eq('')
      expect(hex(codec.encode([42, 1, 2]))).to eq('2a0102')
    end

    it 'reads items until the bytes run out' do
      expect(codec.decode(''.b)).to eq([[], 0])
      expect(codec.decode(b('2a0102'))).to eq([[42, 1, 2], 3])
      expect(codec.decode(b('ffff2a0102'), offset: 2)).to eq([[42, 1, 2], 3])
    end

    it 'works with variable-size items that bound themselves' do
      prefixed_string = RubyKit::Codecs.add_codec_size_prefix(utf8_codec, u8_codec)
      strings         = array_codec(prefixed_string, size: :remainder)
      expect(hex(strings.encode(%w[a bc]))).to eq('0161026263')
      expect(strings.decode(b('0161026263'))).to eq([%w[a bc], 5])
    end

    it 'is unaffected by require_size_prefix and has no fixed size' do
      expect(array_codec(u8_codec, size: :remainder, require_size_prefix: true).decode(''.b)).to eq([[], 0])
      expect(codec.fixed_size).to be_nil
    end

    it 'raises rather than loop forever when an item consumes no bytes' do
      empty_item = RubyKit::Codecs::Codec.new(
        RubyKit::Codecs::Encoder.new { |_| ''.b },
        RubyKit::Codecs::Decoder.new { |_, _| [nil, 0] }
      )
      expect { array_codec(empty_item, size: :remainder).decode(b('00')) }
        .to raise_error(ArgumentError, /decoded zero bytes/)
    end

    it 'applies to map_codec and set_codec' do
      map = map_codec(u8_codec, u8_codec, size: :remainder)
      expect(hex(map.encode({ 1 => 2, 3 => 4 }))).to eq('01020304')
      expect(map.decode(b('01020304'))).to eq([{ 1 => 2, 3 => 4 }, 4])
      expect(set_codec(u8_codec, size: :remainder).decode(b('0102'))).to eq([Set[1, 2], 2])
    end
  end

  describe 'array_codec (unknown size)' do
    it 'rejects an unknown size symbol' do
      expect { array_codec(u8_codec, size: :rest) }.to raise_error(ArgumentError, /Unknown array size :rest/)
    end
  end

  describe 'tuple_codec' do
    let(:codec) { tuple_codec([u8_codec, u16_codec]) }

    it 'round-trips a positional array' do
      decoded, = codec.decode(codec.encode([7, 300]))
      expect(decoded).to eq([7, 300])
    end
  end

  describe 'option_codec' do
    let(:codec) { option_codec(u32_codec) }

    it 'encodes None as a single 0x00 byte' do
      expect(codec.encode(RubyKit::Options.none)).to eq("\x00".b)
    end

    it 'round-trips Some(42)' do
      some    = RubyKit::Options::Some.new(42)
      decoded, = codec.decode(codec.encode(some))
      expect(decoded).to be_a(RubyKit::Options::Some)
      expect(decoded.value).to eq(42)
    end
  end

  # A prefixed collection decodes an exhausted buffer to an empty collection so
  # that a program can append a collection to an existing account layout and
  # still read accounts written before the change. Formats that cannot accept
  # that - borsh requires the prefix - opt into failing via require_size_prefix.
  describe 'require_size_prefix' do
    it 'decodes an exhausted buffer to an empty array by default' do
      expect(array_codec(u8_codec).decode(''.b)).to eq([[], 0])
    end

    it 'consumes nothing when the prefix is absent' do
      _value, consumed = array_codec(u8_codec).decode(''.b)
      expect(consumed).to eq(0)
    end

    it 'decodes a truncated prefix to an empty array by default' do
      expect(array_codec(u8_codec).decode("\x01\x00".b)).to eq([[], 0])
    end

    it 'raises when the prefix is absent and required' do
      expect { array_codec(u8_codec, require_size_prefix: true).decode(''.b) }
        .to raise_error(RubyKit::SolanaError, /Expected 4 bytes but got 0/)
    end

    it 'raises when the prefix is truncated and required' do
      expect { array_codec(u8_codec, require_size_prefix: true).decode("\x01\x00".b) }
        .to raise_error(RubyKit::SolanaError, /Expected 4 bytes but got 2/)
    end

    it 'still round-trips normally when required' do
      codec = array_codec(u8_codec, require_size_prefix: true)
      expect(codec.decode(codec.encode([1, 2, 3])).first).to eq([1, 2, 3])
    end

    it 'is ignored for fixed-count arrays, which carry no prefix' do
      codec = array_codec(u8_codec, size: 2, require_size_prefix: true)
      expect(codec.decode("\x07\x08".b)).to eq([[7, 8], 2])
    end

    it 'applies to set_codec' do
      expect(set_codec(u8_codec).decode(''.b).first).to eq(Set.new)
      expect { set_codec(u8_codec, require_size_prefix: true).decode(''.b) }
        .to raise_error(RubyKit::SolanaError)
    end

    it 'applies to map_codec' do
      expect(map_codec(u8_codec, u8_codec).decode(''.b).first).to eq({})
      expect { map_codec(u8_codec, u8_codec, require_size_prefix: true).decode(''.b) }
        .to raise_error(RubyKit::SolanaError)
    end
  end

  # kit 0e767414: a sentinel size strategy for array-like codecs. The sentinel
  # is compared only at item boundaries, never searched for inside an item.
  describe 'SentinelSize' do
    def b(hex) = [hex].pack('H*')
    def hex(bytes) = bytes.unpack1('H*')
    def sentinel(hex_sentinel, strategy: :required)
      RubyKit::Codecs::SentinelSize.new(sentinel: b(hex_sentinel), strategy: strategy)
    end

    context 'with the default required strategy' do
      let(:codec) { array_codec(u8_codec, size: sentinel('00')) }

      it 'defaults the strategy to :required' do
        expect(RubyKit::Codecs::SentinelSize.new(sentinel: b('00')).strategy).to eq(:required)
      end

      it 'writes only the sentinel for an empty array' do
        expect(hex(codec.encode([]))).to eq('00')
        expect(codec.decode(b('00'))).to eq([[], 1])
      end

      it 'appends the sentinel after the items' do
        expect(hex(codec.encode([42, 1, 2]))).to eq('2a010200')
        expect(codec.decode(b('2a010200'))).to eq([[42, 1, 2], 4])
      end

      it 'decodes from an offset, reporting bytes consumed' do
        expect(codec.decode(b('ffff2a010200'), offset: 2)).to eq([[42, 1, 2], 4])
      end

      it 'supports multi-byte sentinels' do
        wide = array_codec(u8_codec, size: sentinel('ffff'))
        expect(hex(wide.encode([42, 1, 2]))).to eq('2a0102ffff')
        expect(wide.decode(b('2a0102ffff'))).to eq([[42, 1, 2], 5])
      end

      it 'lets the sentinel appear inside an item' do
        # Each big-endian u16 item here contains a 00 byte, but only item
        # boundaries are compared. This holds only because every item is >= 256.
        be = array_codec(u16_codec(endian: :big), size: sentinel('00'))
        expect(hex(be.encode([256, 258]))).to eq('0100010200')
        expect(be.decode(b('0100010200'))).to eq([[256, 258], 5])
      end

      it 'raises when the bytes run out before the sentinel' do
        expect { codec.decode(b('2a0102')) }.to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::CODECS__SENTINEL_MISSING_AT_END_OF_BYTES)
          expect(e.context).to eq(codec_description: 'array', hex_sentinel: '00', sentinel: b('00'))
        }
        expect { codec.decode(''.b) }.to raise_error(RubyKit::SolanaError)
      end

      it 'names the codec by its description in that error' do
        named = array_codec(u8_codec, size: sentinel('00'), description: 'myList')
        expect { named.decode(b('2a0102')) }.to raise_error(RubyKit::SolanaError) { |e|
          expect(e.context[:codec_description]).to eq('myList')
          expect(e.message).to include('Codec [myList] expected sentinel [00]')
        }
      end

      it 'has no fixed size' do
        expect(codec.fixed_size).to be_nil
      end
    end

    context 'with the optional strategy' do
      let(:codec) { array_codec(u8_codec, size: sentinel('00', strategy: :optional)) }

      it 'writes the sentinel and consumes it when present' do
        expect(hex(codec.encode([42, 1, 2]))).to eq('2a010200')
        expect(codec.decode(b('2a010200'))).to eq([[42, 1, 2], 4])
      end

      it 'tolerates a missing sentinel at the end of the bytes' do
        expect(codec.decode(b('2a0102'))).to eq([[42, 1, 2], 3])
        expect(codec.decode(''.b)).to eq([[], 0])
      end
    end

    context 'with the omitted strategy' do
      let(:codec) { array_codec(u8_codec, size: sentinel('00', strategy: :omitted)) }

      it 'never writes the sentinel' do
        expect(hex(codec.encode([42, 1, 2]))).to eq('2a0102')
        expect(codec.encode([])).to eq(''.b)
      end

      it 'ends at the end of the bytes, still consuming a sentinel that is present' do
        expect(codec.decode(b('2a0102'))).to eq([[42, 1, 2], 3])
        expect(codec.decode(b('2a010200'))).to eq([[42, 1, 2], 4])
        expect(codec.decode(''.b)).to eq([[], 0])
      end
    end

    it 'rejects an empty sentinel at construction time' do
      expect { array_codec(u8_codec, size: sentinel('')) }.to raise_error(RubyKit::SolanaError) { |e|
        expect(e.code).to eq(RubyKit::SolanaError::CODECS__SENTINEL_MUST_NOT_BE_EMPTY)
      }
    end

    it 'rejects an unknown strategy at construction time' do
      expect { array_codec(u8_codec, size: sentinel('00', strategy: :sometimes)) }
        .to raise_error(ArgumentError, /Unknown sentinel strategy/)
    end

    # The two invariants the codec documents but, like upstream, does not enforce.
    it 'stops decoding early when an item begins with the sentinel bytes' do
      codec = array_codec(u16_codec, size: sentinel('00'))
      # 00 inside each little-endian item does not terminate the array...
      expect(codec.decode(b('01000200030000'))).to eq([[1, 2, 3], 7])
      # ...but an item that *begins* with 00 is indistinguishable from the terminator.
      expect(codec.decode(b('01000000'))).to eq([[1], 3])
    end

    it 'skips a short tail when an optional sentinel is wider than the smallest item' do
      expect(array_codec(u8_codec, size: sentinel('ffff', strategy: :optional)).decode(b('01022a')))
        .to eq([[1, 2], 2])
      expect(array_codec(u8_codec, size: sentinel('ff', strategy: :optional)).decode(b('01022a')))
        .to eq([[1, 2, 42], 3])
    end

    it 'applies to map_codec' do
      required = map_codec(u8_codec, u8_codec, size: sentinel('00'))
      expect(hex(required.encode({ 1 => 2 }))).to eq('010200')
      expect(required.decode(b('010200'))).to eq([{ 1 => 2 }, 3])

      omitted = map_codec(u8_codec, u8_codec, size: sentinel('00', strategy: :omitted))
      expect(hex(omitted.encode({ 1 => 2 }))).to eq('0102')
      expect(omitted.decode(b('0102'))).to eq([{ 1 => 2 }, 2])
    end

    it 'applies to set_codec' do
      required = set_codec(u8_codec, size: sentinel('00'))
      expect(hex(required.encode(Set[42, 1, 2]))).to eq('2a010200')
      expect(required.decode(b('2a010200'))).to eq([Set[42, 1, 2], 4])

      omitted = set_codec(u8_codec, size: sentinel('00', strategy: :omitted))
      expect(hex(omitted.encode(Set[42, 1, 2]))).to eq('2a0102')
      expect(omitted.decode(b('2a0102'))).to eq([Set[42, 1, 2], 3])
    end

    it 'ignores require_size_prefix, since a sentinel array has no prefix' do
      codec = array_codec(u8_codec, size: sentinel('00', strategy: :optional), require_size_prefix: true)
      expect(codec.decode(''.b)).to eq([[], 0])
    end
  end
end
