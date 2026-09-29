# typed: ignore
# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe RubyKit::WalletStandard do
  # ── Fixtures ─────────────────────────────────────────────────────────────────
  # Build a real signed transaction using the existing compile/sign pipeline so
  # that decode_wire_transaction round-trips correctly with wire_encode_transaction.

  let(:signer)        { RubyKit::Signers.generate_key_pair_signer }
  let(:other_signer)  { RubyKit::Signers.generate_key_pair_signer }
  let(:blockhash_str) { '4PZNQ5MjgFMRSAEKFbMrgCkKAJAV2VEDiJFy1JoqyN3f' }

  let(:constraint) do
    RubyKit::TransactionMessages::BlockhashLifetimeConstraint.new(
      blockhash:               blockhash_str,
      last_valid_block_height: 9_999_999
    )
  end

  let(:message) do
    msg = RubyKit::TransactionMessages.create_transaction_message(version: :legacy)
    msg = RubyKit::TransactionMessages.set_fee_payer(signer.address, msg)
    RubyKit::TransactionMessages.set_blockhash_lifetime(constraint, msg)
  end

  let(:compiled)   { RubyKit::Transactions.compile_transaction_message(message) }
  let(:signed)     { RubyKit::Transactions.sign_transaction([signer.key_pair.signing_key], compiled) }
  let(:wire_bytes) { RubyKit::Transactions.wire_encode_transaction(signed) }
  let(:wire_b64)   { Base64.strict_encode64(wire_bytes) }

  # ── Feature constants ─────────────────────────────────────────────────────
  describe 'feature identifier constants' do
    it 'SIGN_TRANSACTION equals "solana:signTransaction"' do
      expect(described_class::SIGN_TRANSACTION).to eq('solana:signTransaction')
    end

    it 'SIGN_AND_SEND_TRANSACTION equals "solana:signAndSendTransaction"' do
      expect(described_class::SIGN_AND_SEND_TRANSACTION).to eq('solana:signAndSendTransaction')
    end

    it 'SIGN_MESSAGE equals "solana:signMessage"' do
      expect(described_class::SIGN_MESSAGE).to eq('solana:signMessage')
    end

    it 'CONNECT equals "standard:connect"' do
      expect(described_class::CONNECT).to eq('standard:connect')
    end
  end

  # ── decode_wire_transaction ───────────────────────────────────────────────
  describe '.decode_wire_transaction' do
    context 'with binary wire bytes' do
      subject(:tx) { described_class.decode_wire_transaction(wire_bytes) }

      it 'returns a Transaction' do
        expect(tx).to be_a(RubyKit::Transactions::Transaction)
      end

      it 'round-trips message_bytes exactly' do
        expect(tx.message_bytes).to eq(signed.message_bytes)
      end

      it 'includes the signer address in the signatures map' do
        expect(tx.signatures).to have_key(signer.address.value)
      end

      it 'restores the raw signature bytes' do
        expected = signed.signatures[signer.address.value]
        expect(tx.signatures[signer.address.value]).to eq(expected)
      end
    end

    context 'with base64-encoded wire bytes' do
      subject(:tx) { described_class.decode_wire_transaction(wire_b64) }

      it 'returns a Transaction' do
        expect(tx).to be_a(RubyKit::Transactions::Transaction)
      end

      it 'produces the same result as the binary decode' do
        binary_tx = described_class.decode_wire_transaction(wire_bytes)
        expect(tx.message_bytes).to eq(binary_tx.message_bytes)
        expect(tx.signatures).to    eq(binary_tx.signatures)
      end
    end

    context 'with a partially-signed transaction (nil slot present)' do
      # partially_sign_transaction leaves slots for absent signers as nil;
      # wire_encode_transaction fills nil slots with 64 zero bytes.
      let(:partial) { RubyKit::Transactions.partially_sign_transaction([signer.key_pair.signing_key], compiled) }
      let(:partial_wire) { RubyKit::Transactions.wire_encode_transaction(partial) }

      it 'decodes with the signer signature filled' do
        tx = described_class.decode_wire_transaction(partial_wire)
        expect(tx.signatures[signer.address.value]).not_to be_nil
      end
    end

    context 'with malformed input' do
      it 'raises WALLET_STANDARD__INVALID_WIRE_FORMAT for an empty string' do
        expect { described_class.decode_wire_transaction(''.b) }
          .to raise_error(RubyKit::SolanaError) do |e|
            expect(e.code).to eq(:SOLANA_ERROR__WALLET_STANDARD__INVALID_WIRE_FORMAT)
          end
      end

      it 'raises WALLET_STANDARD__INVALID_WIRE_FORMAT for truncated signature data' do
        # Keep only the first 10 bytes — guaranteed to be inside a sig slot.
        expect { described_class.decode_wire_transaction(wire_bytes[0, 10].b) }
          .to raise_error(RubyKit::SolanaError) do |e|
            expect(e.code).to eq(:SOLANA_ERROR__WALLET_STANDARD__INVALID_WIRE_FORMAT)
          end
      end

      # The signature count is a shortU16; since kit 56b49609 a chain longer than
      # three bytes, or one decoding past 65535, is rejected rather than read on.
      it 'rejects a signature count whose shortU16 chain exceeds three bytes' do
        expect { described_class.decode_wire_transaction([0xff, 0xff, 0xff, 0x00].pack('C*')) }
          .to raise_error(RubyKit::SolanaError) { |e|
            expect(e.code).to eq(RubyKit::SolanaError::CODECS__INVALID_BYTE_LENGTH)
          }
      end

      it 'rejects a signature count whose shortU16 decodes above 65535' do
        expect { described_class.decode_wire_transaction([0x80, 0x80, 0x04].pack('C*')) }
          .to raise_error(RubyKit::SolanaError) { |e|
            expect(e.code).to eq(RubyKit::SolanaError::CODECS__NUMBER_OUT_OF_RANGE)
          }
      end

      it 'raises WALLET_STANDARD__INVALID_WIRE_FORMAT when the message section is absent' do
        # compact-u16(0) with no message bytes after it
        expect { described_class.decode_wire_transaction("\x00".b) }
          .to raise_error(RubyKit::SolanaError) do |e|
            expect(e.code).to eq(:SOLANA_ERROR__WALLET_STANDARD__INVALID_WIRE_FORMAT)
          end
      end
    end
  end

  # ── verify_transaction_signatures! ───────────────────────────────────────
  describe '.verify_transaction_signatures!' do
    let(:decoded) { described_class.decode_wire_transaction(wire_bytes) }

    it 'does not raise for a correctly signed transaction' do
      expect { described_class.verify_transaction_signatures!(decoded) }.not_to raise_error
    end

    it 'silently skips nil (unfilled) signature slots' do
      tx_nil = RubyKit::Transactions::Transaction.new(
        message_bytes: decoded.message_bytes,
        signatures:    { signer.address.value => nil }
      )
      expect { described_class.verify_transaction_signatures!(tx_nil) }.not_to raise_error
    end

    it 'raises WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED for a bad signature' do
      tx_bad = RubyKit::Transactions::Transaction.new(
        message_bytes: decoded.message_bytes,
        signatures:    { signer.address.value => ("\x42" * 64).b }
      )
      expect { described_class.verify_transaction_signatures!(tx_bad) }
        .to raise_error(RubyKit::SolanaError) do |e|
          expect(e.code).to eq(:SOLANA_ERROR__WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED)
          expect(e.context[:address]).to eq(signer.address.value)
        end
    end

    it 'raises WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED when message bytes are tampered' do
      tampered = decoded.message_bytes.b.dup
      tampered.setbyte(-1, tampered.getbyte(-1) ^ 0xFF)
      tx_tampered = RubyKit::Transactions::Transaction.new(
        message_bytes: tampered,
        signatures:    decoded.signatures
      )
      expect { described_class.verify_transaction_signatures!(tx_tampered) }
        .to raise_error(RubyKit::SolanaError) do |e|
          expect(e.code).to eq(:SOLANA_ERROR__WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED)
        end
    end
  end

  # ── verify_signed_transaction! ───────────────────────────────────────────
  describe '.verify_signed_transaction!' do
    it 'returns the decoded Transaction for valid binary wire bytes' do
      tx = described_class.verify_signed_transaction!(wire_bytes)
      expect(tx).to be_a(RubyKit::Transactions::Transaction)
      expect(tx.message_bytes).to eq(signed.message_bytes)
    end

    it 'returns the decoded Transaction for valid base64 wire bytes' do
      tx = described_class.verify_signed_transaction!(wire_b64)
      expect(tx.message_bytes).to eq(signed.message_bytes)
    end

    it 'raises SolanaError for an invalid wire format' do
      expect { described_class.verify_signed_transaction!("\x00".b) }
        .to raise_error(RubyKit::SolanaError) do |e|
          expect(e.code).to eq(:SOLANA_ERROR__WALLET_STANDARD__INVALID_WIRE_FORMAT)
        end
    end

    it 'raises SolanaError when a signature does not verify' do
      # Decode, corrupt the signature, re-encode
      tx     = described_class.decode_wire_transaction(wire_bytes)
      bad_tx = RubyKit::Transactions::Transaction.new(
        message_bytes: tx.message_bytes,
        signatures:    { signer.address.value => ("\xAB" * 64).b }
      )
      bad_wire = RubyKit::Transactions.wire_encode_transaction(bad_tx)
      expect { described_class.verify_signed_transaction!(bad_wire) }
        .to raise_error(RubyKit::SolanaError) do |e|
          expect(e.code).to eq(:SOLANA_ERROR__WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED)
        end
    end
  end

  # ── signed_by? ───────────────────────────────────────────────────────────
  describe '.signed_by?' do
    let(:decoded) { described_class.decode_wire_transaction(wire_bytes) }

    it 'returns true when the address has a valid signature' do
      expect(described_class.signed_by?(decoded, signer.address)).to be true
    end

    it 'returns false when the address is not in the signatures map at all' do
      expect(described_class.signed_by?(decoded, other_signer.address)).to be false
    end

    it 'returns false when the signature slot is nil' do
      tx_nil = RubyKit::Transactions::Transaction.new(
        message_bytes: decoded.message_bytes,
        signatures:    { signer.address.value => nil }
      )
      expect(described_class.signed_by?(tx_nil, signer.address)).to be false
    end

    it 'returns false when the signature bytes do not verify' do
      tx_bad = RubyKit::Transactions::Transaction.new(
        message_bytes: decoded.message_bytes,
        signatures:    { signer.address.value => ("\x00" * 64).b }
      )
      expect(described_class.signed_by?(tx_bad, signer.address)).to be false
    end
  end
end
