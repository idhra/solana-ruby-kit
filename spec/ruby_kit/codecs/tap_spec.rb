# typed: ignore
# frozen_string_literal: true

require 'spec_helper'

# Tap combinators wrap a codec in one that observes a value - or the bytes -
# without changing it, for validation guards, logging or other read-only side
# effects. A tap that raises aborts the operation.
#
# Upstream's byte taps take (bytes, pre_offset, post_offset) because encoders
# there write into a shared buffer. A Ruby Encoder returns a standalone byte
# String, so the encode-side taps receive exactly the bytes that were written.
RSpec.describe 'RubyKit::Codecs tap combinators' do
  include RubyKit::Codecs
  include RubyKit::Codecs::Numbers

  describe 'tap_encoder' do
    it 'observes the value without changing the output' do
      seen    = []
      encoder = tap_encoder(u8_codec.encoder) { |value| seen << value }
      expect(encoder.encode(42)).to eq("\x2a".b)
      expect(seen).to eq([42])
    end

    it 'preserves the wrapped encoder fixed size' do
      expect(tap_encoder(u8_codec.encoder) { |_| }.fixed_size).to eq(1)
    end

    it 'aborts encoding when the tap raises' do
      encoder = tap_encoder(u8_codec.encoder) do |value|
        raise ArgumentError, 'Value must not exceed 100' if value > 100
      end
      expect(encoder.encode(42)).to eq("\x2a".b)
      expect { encoder.encode(200) }.to raise_error(ArgumentError, 'Value must not exceed 100')
    end
  end

  describe 'tap_decoder' do
    it 'observes the decoded value without changing it' do
      seen    = []
      decoder = tap_decoder(u8_codec.decoder) { |value| seen << value }
      expect(decoder.decode("\x2a".b)).to eq([42, 1])
      expect(seen).to eq([42])
    end

    it 'aborts decoding when the tap raises' do
      decoder = tap_decoder(u8_codec.decoder) do |value|
        raise ArgumentError, 'Value must not be zero' if value.zero?
      end
      expect(decoder.decode("\x2a".b).first).to eq(42)
      expect { decoder.decode("\x00".b) }.to raise_error(ArgumentError, 'Value must not be zero')
    end
  end

  describe 'tap_codec' do
    it 'observes both sides' do
      encoded = []
      decoded = []
      codec   = tap_codec(
        u8_codec,
        encode_tap: ->(value) { encoded << value },
        decode_tap: ->(value) { decoded << value }
      )
      bytes = codec.encode(7)
      expect(codec.decode(bytes).first).to eq(7)
      expect(encoded).to eq([7])
      expect(decoded).to eq([7])
    end

    it 'leaves decoding untouched when no decode tap is given' do
      codec = tap_codec(u8_codec, encode_tap: ->(_) {})
      expect(codec.decode(codec.encode(9)).first).to eq(9)
    end

    it 'aborts each side independently' do
      codec = tap_codec(
        u8_codec,
        encode_tap: ->(value) { raise ArgumentError, 'too big' if value > 100 },
        decode_tap: ->(value) { raise ArgumentError, 'zero' if value.zero? }
      )
      expect { codec.encode(200) }.to raise_error(ArgumentError, 'too big')
      expect { codec.decode("\x00".b) }.to raise_error(ArgumentError, 'zero')
    end
  end

  describe 'tap_encoder_bytes' do
    it 'observes the encoded bytes without changing them' do
      seen    = []
      encoder = tap_encoder_bytes(u16_codec.encoder) { |bytes| seen << bytes }
      expect(encoder.encode(1)).to eq("\x01\x00".b)
      expect(seen).to eq(["\x01\x00".b])
    end

    it 'aborts encoding when the tap raises' do
      encoder = tap_encoder_bytes(u8_codec.encoder) do |bytes|
        raise ArgumentError, 'no high bit' if bytes.bytes.first > 0x7f
      end
      expect(encoder.encode(1)).to eq("\x01".b)
      expect { encoder.encode(0xff) }.to raise_error(ArgumentError, 'no high bit')
    end
  end

  describe 'tap_decoder_bytes' do
    it 'observes the raw bytes and offset before decoding' do
      seen    = []
      decoder = tap_decoder_bytes(u8_codec.decoder) { |bytes, offset| seen << [bytes, offset] }
      expect(decoder.decode("\x00\x2a".b, offset: 1)).to eq([42, 1])
      expect(seen).to eq([["\x00\x2a".b, 1]])
    end

    it 'aborts decoding when the tap raises' do
      decoder = tap_decoder_bytes(u8_codec.decoder) do |bytes, offset|
        raise ArgumentError, 'Expected a 0 or a 1 for booleans' if bytes.bytes[offset] > 1
      end
      expect(decoder.decode("\x01".b).first).to eq(1)
      expect { decoder.decode("\x02".b) }.to raise_error(ArgumentError, 'Expected a 0 or a 1 for booleans')
    end
  end

  describe 'tap_codec_bytes' do
    it 'observes the bytes on both sides' do
      encoded = []
      decoded = []
      codec   = tap_codec_bytes(
        u8_codec,
        encode_tap: ->(bytes) { encoded << bytes },
        decode_tap: ->(bytes, offset) { decoded << [bytes, offset] }
      )
      expect(codec.decode(codec.encode(5)).first).to eq(5)
      expect(encoded).to eq(["\x05".b])
      expect(decoded).to eq([["\x05".b, 0]])
    end

    it 'leaves decoding untouched when no decode tap is given' do
      codec = tap_codec_bytes(u8_codec, encode_tap: ->(_) {})
      expect(codec.decode(codec.encode(3)).first).to eq(3)
    end
  end

  it 'composes with other combinators without changing the result' do
    codec = tap_codec(reverse_codec(u16_codec), encode_tap: ->(_) {})
    expect(codec.encode(1)).to eq("\x00\x01".b)
    expect(codec.decode(codec.encode(1)).first).to eq(1)
  end
end
