# typed: ignore
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyKit::Codecs::Numbers do
  include RubyKit::Codecs::Numbers

  describe 'u8_codec' do
    let(:codec) { u8_codec }

    it 'round-trips 0' do
      expect(codec.decode(codec.encode(0)).first).to eq(0)
    end

    it 'round-trips 255' do
      expect(codec.decode(codec.encode(255)).first).to eq(255)
    end

    it 'has fixed_size 1' do
      expect(codec.fixed_size).to eq(1)
    end
  end

  describe 'u16_codec (little-endian)' do
    let(:codec) { u16_codec }

    it 'encodes 256 as [0x00, 0x01]' do
      expect(codec.encode(256).bytes).to eq([0x00, 0x01])
    end

    it 'round-trips 1000' do
      expect(codec.decode(codec.encode(1000)).first).to eq(1000)
    end
  end

  describe 'u32_codec' do
    let(:codec) { u32_codec }

    it 'round-trips 100_000' do
      expect(codec.decode(codec.encode(100_000)).first).to eq(100_000)
    end

    it 'has fixed_size 4' do
      expect(codec.fixed_size).to eq(4)
    end
  end

  describe 'u64_codec' do
    let(:codec) { u64_codec }

    it 'round-trips a large value' do
      big = 1_000_000_000_000
      expect(codec.decode(codec.encode(big)).first).to eq(big)
    end
  end

  describe 'i64_codec' do
    let(:codec) { i64_codec }

    it 'round-trips a negative value' do
      expect(codec.decode(codec.encode(-42)).first).to eq(-42)
    end
  end

  describe 'u128_codec' do
    let(:codec) { u128_codec }

    it 'round-trips a 128-bit value' do
      val = (2**64) + 1
      expect(codec.decode(codec.encode(val)).first).to eq(val)
    end
  end

  describe 'f64_codec' do
    let(:codec) { f64_codec }

    it 'round-trips 3.14' do
      val, = codec.decode(codec.encode(3.14))
      expect(val).to be_within(1e-10).of(3.14)
    end
  end

  describe 'compact_u16_codec' do
    let(:codec) { compact_u16_codec }

    it 'encodes 0 as single byte' do
      expect(codec.encode(0).bytesize).to eq(1)
    end

    it 'round-trips 127' do
      expect(codec.decode(codec.encode(127)).first).to eq(127)
    end

    it 'round-trips 128 in 2 bytes' do
      encoded = codec.encode(128)
      expect(encoded.bytesize).to eq(2)
      expect(codec.decode(encoded).first).to eq(128)
    end

    it 'round-trips 300' do
      expect(codec.decode(codec.encode(300)).first).to eq(300)
    end
  end

  # u256/i256 were added upstream alongside a refactor that routes u128, i128,
  # u256 and i256 through one shared word-combining helper. Ruby's Integer is
  # arbitrary precision, so `big_int_codec` does the same job by shifting bytes;
  # these specs pin both the new widths and the refactored 128-bit ones.
  describe 'u256_codec' do
    let(:codec) { u256_codec }

    it 'is 32 bytes wide' do
      expect(codec.fixed_size).to eq(32)
    end

    it 'encodes 1 little-endian' do
      expect(codec.encode(1).unpack('C*')).to eq([1] + ([0] * 31))
    end

    it 'encodes 1 big-endian' do
      expect(u256_codec(endian: :big).encode(1).unpack('C*')).to eq(([0] * 31) + [1])
    end

    it 'round-trips the maximum value' do
      max = (1 << 256) - 1
      expect(codec.decode(codec.encode(max)).first).to eq(max)
    end

    it 'round-trips a value beyond 128 bits' do
      value = 1 << 200
      expect(codec.decode(codec.encode(value)).first).to eq(value)
    end

    it 'round-trips big-endian' do
      be = u256_codec(endian: :big)
      value = (1 << 255) - 12_345
      expect(be.decode(be.encode(value)).first).to eq(value)
    end
  end

  describe 'i256_codec' do
    let(:codec) { i256_codec }

    it 'is 32 bytes wide' do
      expect(codec.fixed_size).to eq(32)
    end

    it 'encodes -1 as all ones' do
      expect(codec.encode(-1).unpack('C*')).to eq([255] * 32)
    end

    it 'round-trips the minimum value' do
      min = -(1 << 255)
      expect(codec.decode(codec.encode(min)).first).to eq(min)
    end

    it 'round-trips the maximum value' do
      max = (1 << 255) - 1
      expect(codec.decode(codec.encode(max)).first).to eq(max)
    end

    it 'round-trips a negative value big-endian' do
      be = i256_codec(endian: :big)
      expect(be.decode(be.encode(-123_456_789)).first).to eq(-123_456_789)
    end
  end

  describe 'u128_codec / i128_codec after the shared-helper refactor' do
    it 'still encodes u128 1 little-endian' do
      expect(u128_codec.encode(1).unpack('C*')).to eq([1] + ([0] * 15))
    end

    it 'still encodes i128 -1 as all ones' do
      expect(i128_codec.encode(-1).unpack('C*')).to eq([255] * 16)
    end

    it 'still round-trips the u128 maximum' do
      max = (1 << 128) - 1
      expect(u128_codec.decode(u128_codec.encode(max)).first).to eq(max)
    end

    it 'still round-trips the i128 bounds' do
      [(1 << 127) - 1, -(1 << 127)].each do |value|
        expect(i128_codec.decode(i128_codec.encode(value)).first).to eq(value)
      end
    end
  end
end
