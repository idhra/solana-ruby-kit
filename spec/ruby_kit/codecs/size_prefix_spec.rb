# typed: ignore
# frozen_string_literal: true

require 'spec_helper'

# add_codec_size_prefix used to read the prefix and then ignore it, letting the
# inner codec decode from there to wherever it chose to stop. A variable-size
# inner codec such as utf8_codec reads to the end of the buffer, so anything
# after a prefixed string - the next struct field, the next array item - was
# swallowed into it. Upstream's addDecoderSizePrefix bounds the inner decode to
# exactly the prefixed length.
RSpec.describe 'RubyKit::Codecs.add_codec_size_prefix' do
  let(:codecs) { RubyKit::Codecs }
  let(:u32_string) { codecs.add_codec_size_prefix(codecs.utf8_codec, codecs.u32_codec) }

  def b(hex) = [hex].pack('H*')

  it 'round-trips a prefixed string' do
    expect(u32_string.encode('hi').unpack1('H*')).to eq('020000006869')
    expect(u32_string.decode(b('020000006869'))).to eq(['hi', 6])
  end

  it 'stops the inner codec at the prefixed length' do
    expect(u32_string.decode(b('020000006869ffff'))).to eq(['hi', 6])
  end

  it 'leaves the following struct field intact' do
    record = codecs.struct_codec([[:name, u32_string], [:count, codecs.u8_codec]])
    expect(record.decode(record.encode({ name: 'hi', count: 7 }))).to eq([{ name: 'hi', count: 7 }, 7])
  end

  it 'decodes arrays of prefixed strings item by item' do
    strings = codecs.array_codec(u32_string)
    expect(strings.decode(b('0200000001000000610100000062'))).to eq([%w[a b], 14])
  end

  it 'raises when fewer bytes remain than the prefix promises' do
    expect { u32_string.decode(b('0500000061')) }.to raise_error(RubyKit::SolanaError) { |e|
      expect(e.code).to eq(RubyKit::SolanaError::CODECS__INVALID_BYTE_LENGTH)
      expect(e.context).to eq(codec_description: 'addDecoderSizePrefix', expected: 5, actual: 1)
    }
  end

  it 'is fixed-size only when both the prefix and the inner codec are' do
    expect(u32_string.fixed_size).to be_nil
    expect(codecs.add_codec_size_prefix(codecs.u16_codec, codecs.u8_codec).fixed_size).to eq(3)
  end
end
