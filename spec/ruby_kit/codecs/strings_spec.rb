# typed: ignore
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyKit::Codecs::Strings do
  include RubyKit::Codecs::Strings
  include RubyKit::Codecs::Numbers

  describe 'utf8_codec (variable)' do
    let(:codec) { utf8_codec }

    it 'encodes a string to its UTF-8 bytes' do
      expect(codec.encode('hello').bytes).to eq([104, 101, 108, 108, 111])
    end

    it 'round-trips a UTF-8 string' do
      val, = codec.decode(codec.encode('héllo'))
      expect(val).to eq('héllo')
    end
  end

  describe 'utf8_codec (fixed size)' do
    let(:codec) { utf8_codec(size: 10) }

    it 'pads short strings' do
      expect(codec.encode('hi').bytesize).to eq(10)
    end
  end

  describe 'hex_codec' do
    let(:codec) { hex_codec }

    it 'encodes a hex string to bytes' do
      expect(codec.encode('ff00').bytes).to eq([0xFF, 0x00])
    end

    it 'decodes bytes to hex string' do
      val, = codec.decode("\xFF\x00".b)
      expect(val).to eq('ff00')
    end
  end

  describe 'bytes_codec' do
    let(:codec) { bytes_codec(4) }

    it 'passes through exactly 4 bytes' do
      raw = "\x01\x02\x03\x04".b
      val, n = codec.decode(codec.encode(raw))
      expect(val).to eq(raw)
      expect(n).to eq(4)
    end

    it 'raises on wrong size' do
      expect { codec.encode("\x01\x02".b) }.to raise_error(ArgumentError)
    end
  end

  describe 'bit_array_codec' do
    let(:codec) { bit_array_codec(1) }

    it 'encodes bits into a byte' do
      bits  = [true, false, true, false, false, false, false, false]
      bytes = codec.encode(bits)
      expect(bytes.bytes.first).to eq(0b00000101)
    end

    it 'decodes a byte into bits' do
      bits, = codec.decode([0b00000101].pack('C'))
      expect(bits.first(3)).to eq([true, false, true])
    end
  end

  # The UTF-8 codec gained fatal / ignore_bom / remove_null_characters options.
  # By default it substitutes U+FFFD for malformed input, strips a leading byte
  # order mark and strips null characters - the options turn each of those off.
  describe 'utf8_codec options' do
    let(:bom) { "\xEF\xBB\xBF".b }

    describe 'remove_null_characters' do
      it 'strips every null character by default, not just trailing padding' do
        expect(utf8_codec.decode("a\x00b".b).first).to eq('ab')
      end

      it 'keeps null characters when disabled' do
        expect(utf8_codec(remove_null_characters: false).decode("a\x00b".b).first).to eq("a\x00b")
      end

      it 'keeps fixed-size padding when disabled' do
        codec = utf8_codec(size: 5, remove_null_characters: false)
        expect(codec.decode(codec.encode('ab')).first).to eq("ab\x00\x00\x00")
      end

      it 'still strips fixed-size padding by default' do
        codec = utf8_codec(size: 5)
        expect(codec.decode(codec.encode('ab')).first).to eq('ab')
      end
    end

    describe 'ignore_bom' do
      # The name follows TextDecoder: false (the default) STRIPS the mark.
      it 'strips a leading byte order mark by default' do
        expect(utf8_codec.decode(bom + 'a'.b).first).to eq('a')
      end

      it 'keeps a leading byte order mark when enabled' do
        expect(utf8_codec(ignore_bom: true).decode(bom + 'a'.b).first.bytes)
          .to eq([0xEF, 0xBB, 0xBF, 0x61])
      end

      it 'only strips a mark that leads' do
        expect(utf8_codec.decode('a'.b + bom).first.bytes).to eq([0x61, 0xEF, 0xBB, 0xBF])
      end
    end

    describe 'fatal' do
      it 'substitutes the replacement character by default' do
        expect(utf8_codec.decode("a\xFFb".b).first).to eq("a�b")
      end

      it 'raises when decoding malformed bytes' do
        expect { utf8_codec(fatal: true).decode("\xFF".b) }
          .to raise_error(RubyKit::SolanaError, /Invalid UTF-8 byte sequence at offset 0/)
      end

      it 'reports the offset of the malformed sequence' do
        error = nil
        begin
          utf8_codec(fatal: true).decode("ab\xC0\x80".b)
        rescue RubyKit::SolanaError => e
          error = e
        end
        expect(error.context[:offset]).to eq(2)
      end

      it 'raises when encoding a string whose bytes are not valid UTF-8' do
        expect { utf8_codec(fatal: true).encode("a\xC0\x80b".b) }
          .to raise_error(RubyKit::SolanaError, /Invalid UTF-8 string at index 1/)
      end

      it 'accepts well-formed multi-byte text' do
        codec = utf8_codec(fatal: true)
        expect(codec.decode(codec.encode('hello 語')).first).to eq('hello 語')
      end
    end

    it 'round-trips plain text with every option at its default' do
      codec = utf8_codec
      expect(codec.decode(codec.encode('hello 語')).first).to eq('hello 語')
    end
  end

  describe 'remove_null_characters' do
    it 'removes nulls from anywhere in the string' do
      expect(remove_null_characters("\x00a\x00b\x00")).to eq('ab')
    end

    it 'leaves a string without nulls alone' do
      expect(remove_null_characters('ab')).to eq('ab')
    end
  end

  describe 'find_malformed_utf8_sequence_offset' do
    it 'returns -1 for well-formed bytes' do
      expect(find_malformed_utf8_sequence_offset("\xE8\xAA\x9E".b)).to eq(-1)
    end

    it 'returns -1 for ASCII' do
      expect(find_malformed_utf8_sequence_offset('hello'.b)).to eq(-1)
    end

    it 'rejects an overlong encoding' do
      expect(find_malformed_utf8_sequence_offset("a\xC0\x80".b)).to eq(1)
    end

    it 'rejects an encoded surrogate' do
      expect(find_malformed_utf8_sequence_offset("\xED\xA0\x80".b)).to eq(0)
    end

    it 'rejects a code point above U+10FFFF' do
      expect(find_malformed_utf8_sequence_offset("\xF4\x90\x80\x80".b)).to eq(0)
    end

    it 'rejects a truncated sequence' do
      expect(find_malformed_utf8_sequence_offset("\xE8\xAA".b)).to eq(0)
    end

    it 'rejects an unexpected continuation byte' do
      expect(find_malformed_utf8_sequence_offset("\x80".b)).to eq(0)
    end

    it 'honours the starting offset' do
      expect(find_malformed_utf8_sequence_offset("\xFFa".b, 1)).to eq(-1)
    end
  end

  describe 'assert_is_well_formed_utf8_bytes' do
    it 'passes for well-formed bytes' do
      expect { assert_is_well_formed_utf8_bytes("\xE8\xAA\x9E".b) }.not_to raise_error
    end

    it 'raises for an overlong encoding' do
      expect { assert_is_well_formed_utf8_bytes("\xC0\x80".b) }
        .to raise_error(RubyKit::SolanaError, /Invalid UTF-8 byte sequence/)
    end
  end

  describe 'assert_is_well_formed_utf8_string' do
    it 'passes for valid UTF-8 text' do
      expect { assert_is_well_formed_utf8_string('hello 語') }.not_to raise_error
    end

    it 'raises for a string holding invalid UTF-8 bytes' do
      expect { assert_is_well_formed_utf8_string("\xED\xA0\x80".b) }
        .to raise_error(RubyKit::SolanaError, /Invalid UTF-8 string at index 0/)
    end
  end
end
