# typed: ignore
# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe RubyKit::TransactionIntrospection do
  let(:fee_payer_kp) { RbNaCl::SigningKey.generate }
  let(:fee_payer) { RubyKit::Addresses.get_address_from_public_key(fee_payer_kp.verify_key) }
  let(:other_kp) { RbNaCl::SigningKey.generate }
  let(:writable_account) { RubyKit::Addresses.get_address_from_public_key(other_kp.verify_key) }
  let(:program_address) { RubyKit::Addresses.address('11111111111111111111111111111111') }
  let(:blockhash_constraint) do
    RubyKit::TransactionMessages::BlockhashLifetimeConstraint.new(
      blockhash: '4PZNQ5MjgFMRSAEKFbMrgCkKAJAV2VEDiJFy1JoqyN3f',
      last_valid_block_height: 9999
    )
  end
  let(:instruction) do
    RubyKit::Instructions::Instruction.new(
      program_address: program_address,
      accounts:        [RubyKit::Instructions.writable_account(writable_account)],
      data:            "\x01\x02\x03".b
    )
  end
  let(:message) do
    RubyKit::TransactionMessages.create_transaction_message(version: :legacy)
      .then { |m| RubyKit::TransactionMessages.set_fee_payer(fee_payer, m) }
      .then { |m| RubyKit::TransactionMessages.set_blockhash_lifetime(blockhash_constraint, m) }
      .then { |m| RubyKit::TransactionMessages.append_instructions(m, [instruction]) }
  end
  let(:transaction) { RubyKit::Transactions.compile_transaction_message(message) }
  let(:signed_transaction) { RubyKit::Transactions.sign_transaction([fee_payer_kp], transaction) }
  let(:wire_bytes) { RubyKit::Transactions.wire_encode_transaction(signed_transaction) }

  describe '.decode_transaction_from_rpc_response' do
    it 'round-trips a base64-encoded getTransaction response' do
      rpc_tx = {
        'transaction' => [Base64.strict_encode64(wire_bytes), 'base64'],
        'meta'        => nil
      }

      decoded = described_class.decode_transaction_from_rpc_response(rpc_tx)

      expect(decoded.transaction.message_bytes).to eq(transaction.message_bytes)
      expect(decoded.compiled_message.version).to eq(:legacy)
      expect(decoded.compiled_message.static_accounts.map(&:value)).to include(fee_payer.value, writable_account.value, program_address.value)
      expect(decoded.compiled_message.instructions.length).to eq(1)
      expect(decoded.compiled_message.instructions.first.data).to eq("\x01\x02\x03".b)
    end

    it 'round-trips a base58-encoded getTransaction response' do
      rpc_tx = {
        'transaction' => [RubyKit::Encoding::Base58.encode(wire_bytes), 'base58'],
        'meta'        => nil
      }

      decoded = described_class.decode_transaction_from_rpc_response(rpc_tx)
      expect(decoded.transaction.message_bytes).to eq(transaction.message_bytes)
    end

    it 'decodes a json-encoded getTransaction response without wire bytes' do
      rpc_tx = {
        'transaction' => {
          'message' => {
            'header' => {
              'numRequiredSignatures' => 1,
              'numReadonlySignedAccounts' => 0,
              'numReadonlyUnsignedAccounts' => 1
            },
            'accountKeys'     => [fee_payer.value, writable_account.value, program_address.value],
            'recentBlockhash' => blockhash_constraint.blockhash,
            'instructions'    => [
              { 'programIdIndex' => 2, 'accounts' => [1], 'data' => RubyKit::Encoding::Base58.encode("\x01\x02\x03".b) }
            ]
          }
        },
        'meta' => nil
      }

      decoded = described_class.decode_transaction_from_rpc_response(rpc_tx)

      expect(decoded.transaction).to be_nil
      expect(decoded.compiled_message.version).to eq(:legacy)
      expect(decoded.compiled_message.instructions.first.data).to eq("\x01\x02\x03".b)
    end

    # A getTransactionsForAddress / getBlock element carries the same
    # transaction/meta/version envelope as a getTransaction response, plus
    # slot/blockTime/transactionIndex. The decoder reads only the envelope.
    it 'decodes a getTransactionsForAddress-shaped result, ignoring the extra fields' do
      rpc_tx = {
        'blockTime'        => 1_700_000_000,
        'meta'             => { 'loadedAddresses' => { 'readonly' => [], 'writable' => [] } },
        'slot'             => 100,
        'transaction'      => [Base64.strict_encode64(wire_bytes), 'base64'],
        'transactionIndex' => 3
      }

      decoded = described_class.decode_transaction_from_rpc_response(rpc_tx)

      expect(decoded.compiled_message.version).to eq(:legacy)
      expect(decoded.transaction).not_to be_nil
    end

    it 'treats an explicitly null version as legacy on the json path' do
      rpc_tx = {
        'transaction' => {
          'message' => {
            'header' => {
              'numRequiredSignatures' => 1,
              'numReadonlySignedAccounts' => 0,
              'numReadonlyUnsignedAccounts' => 1
            },
            'accountKeys'     => [fee_payer.value, writable_account.value, program_address.value],
            'recentBlockhash' => blockhash_constraint.blockhash,
            'instructions'    => []
          }
        },
        'meta'    => nil,
        'version' => nil
      }

      expect(described_class.decode_transaction_from_rpc_response(rpc_tx).compiled_message.version)
        .to eq(:legacy)
    end

    it 'preserves a v0 version on the json path' do
      rpc_tx = {
        'transaction' => {
          'message' => {
            'header' => {
              'numRequiredSignatures' => 1,
              'numReadonlySignedAccounts' => 0,
              'numReadonlyUnsignedAccounts' => 1
            },
            'accountKeys'     => [fee_payer.value, writable_account.value, program_address.value],
            'recentBlockhash' => blockhash_constraint.blockhash,
            'instructions'    => []
          }
        },
        'meta'    => nil,
        'version' => 0
      }

      expect(described_class.decode_transaction_from_rpc_response(rpc_tx).compiled_message.version)
        .to eq(0)
    end

    it 'raises for a jsonParsed response' do
      rpc_tx = {
        'transaction' => {
          'message' => {
            'accountKeys'  => [{ 'pubkey' => fee_payer.value, 'signer' => true, 'writable' => true }],
            'instructions' => []
          }
        }
      }

      expect { described_class.decode_transaction_from_rpc_response(rpc_tx) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::TRANSACTION_INTROSPECTION__CANNOT_DECODE_JSON_PARSED_TRANSACTION)
        }
    end

    it 'raises for an unrecognized response shape' do
      expect { described_class.decode_transaction_from_rpc_response({ 'transaction' => 'nonsense' }) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::TRANSACTION_INTROSPECTION__UNRECOGNIZED_GET_TRANSACTION_RESPONSE)
        }
    end
  end

  describe '.decode_compiled_transaction_message' do
    # A legacy message is a 3-byte header followed by a shortU16 account count.
    # Since kit 56b49609 that count is bounded to three bytes and the u16 domain.
    it 'rejects an account count whose shortU16 chain exceeds three bytes' do
      bytes = [1, 0, 0, 0xff, 0xff, 0xff, 0x00].pack('C*')
      expect { described_class.decode_compiled_transaction_message(bytes) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::CODECS__INVALID_BYTE_LENGTH)
        }
    end

    it 'rejects an account count whose shortU16 decodes above 65535' do
      bytes = [1, 0, 0, 0x80, 0x80, 0x04].pack('C*')
      expect { described_class.decode_compiled_transaction_message(bytes) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::CODECS__NUMBER_OUT_OF_RANGE)
        }
    end

    it 'still reports a truncated shortU16 chain as a malformed message' do
      expect { described_class.decode_compiled_transaction_message([1, 0, 0, 0x80].pack('C*')) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::TRANSACTION_INTROSPECTION__MALFORMED_COMPILED_MESSAGE)
        }
    end
  end

  describe '.get_instructions_from_compiled_transaction_message' do
    it 'resolves account indices back to the original AccountMetas' do
      compiled = described_class.decode_compiled_transaction_message(transaction.message_bytes)
      resolved = described_class.get_instructions_from_compiled_transaction_message(compiled)

      expect(resolved.length).to eq(1)
      ix = resolved.first
      expect(ix.program_address).to eq(program_address)
      expect(ix.accounts.map(&:address)).to eq([writable_account])
      expect(ix.accounts.first.role).to eq(RubyKit::Instructions::AccountRole::WRITABLE)
      expect(ix.data).to eq("\x01\x02\x03".b)
    end
  end

  describe '.walk_instructions' do
    it 'interleaves outer instructions with their traced inner instructions' do
      compiled = described_class.decode_compiled_transaction_message(transaction.message_bytes)
      meta = {
        'innerInstructions' => [
          {
            'index' => 0,
            'instructions' => [
              { 'programIdIndex' => 2, 'accounts' => [1], 'data' => RubyKit::Encoding::Base58.encode('inner'.b), 'stackHeight' => 2 }
            ]
          }
        ]
      }

      traced = described_class.walk_instructions(compiled_message: compiled, meta: meta)

      expect(traced.length).to eq(2)
      expect(traced[0].trace).to eq({ kind: :outer, index: 0 })
      expect(traced[1].trace).to eq({ kind: :inner, outer_index: 0, inner_index: 0, stack_height: 2 })
      expect(traced[1].instruction.data).to eq('inner'.b)
    end

    it 'returns only outer instructions when meta is absent' do
      compiled = described_class.decode_compiled_transaction_message(transaction.message_bytes)
      traced   = described_class.walk_instructions(compiled_message: compiled)

      expect(traced.length).to eq(1)
      expect(traced.first.trace).to eq({ kind: :outer, index: 0 })
    end
  end
end
