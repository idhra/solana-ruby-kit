# typed: ignore
# frozen_string_literal: true

require 'spec_helper'

# kit 5be269c6 exposed these helpers so custom message packers can enforce the
# same limits the built-in packers do.
RSpec.describe RubyKit::InstructionPlans do
  def solana_error(code, context = {})
    RubyKit::SolanaError.new(code, context)
  end

  describe '.resolve_max_instructions_per_transaction' do
    it 'defaults to 16 when no value is provided' do
      expect(described_class.resolve_max_instructions_per_transaction).to eq(16)
      expect(described_class.resolve_max_instructions_per_transaction(nil)).to eq(16)
    end

    it 'returns a valid provided value as-is' do
      expect(described_class.resolve_max_instructions_per_transaction(1)).to eq(1)
      expect(described_class.resolve_max_instructions_per_transaction(64)).to eq(64)
    end

    [0, -1, 65].each do |invalid|
      it "raises INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION for #{invalid}" do
        expect { described_class.resolve_max_instructions_per_transaction(invalid) }
          .to raise_error(RubyKit::SolanaError) { |e|
            expect(e.code).to eq(RubyKit::SolanaError::INSTRUCTION_PLANS__INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION)
            expect(e.context).to eq(max_instructions: invalid, transaction_instruction_limit: 64)
          }
      end
    end

    it 'rejects a non-integer via its signature' do
      expect { described_class.resolve_max_instructions_per_transaction(1.5) }.to raise_error(TypeError)
    end
  end

  describe '.assert_max_instructions_per_transaction' do
    it 'passes when the number of instructions is within the maximum' do
      expect { described_class.assert_max_instructions_per_transaction(16, 16) }.not_to raise_error
    end

    it 'raises when the number of instructions exceeds the maximum' do
      expect { described_class.assert_max_instructions_per_transaction(17, 16) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED)
          expect(e.context).to eq(max_instructions: 16, num_instructions: 17)
        }
    end
  end

  describe '.assert_message_can_accommodate_size' do
    it 'passes when the next size is within the limit' do
      expect { described_class.assert_message_can_accommodate_size(current_size: 100, next_size: 1232, size_limit: 1232) }
        .not_to raise_error
    end

    it 'raises with the required and free bytes when the next size exceeds the limit' do
      expect { described_class.assert_message_can_accommodate_size(current_size: 1000, next_size: 1300, size_limit: 1232) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN)
          expect(e.context).to eq(num_bytes_required: 300, num_free_bytes: 232)
        }
    end
  end

  describe '.message_packer_error_that_requires_new_candidate?' do
    [
      RubyKit::SolanaError::INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED,
      RubyKit::SolanaError::INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN,
      RubyKit::SolanaError::INSTRUCTION_PLANS__MESSAGE_REJECTED_BY_PACKER
    ].each do |code|
      it "is true for #{code}" do
        expect(described_class.message_packer_error_that_requires_new_candidate?(solana_error(code))).to be(true)
      end
    end

    it 'is false for other SolanaErrors' do
      error = solana_error(RubyKit::SolanaError::INSTRUCTION_PLANS__MESSAGE_PACKER_ALREADY_COMPLETE)
      expect(described_class.message_packer_error_that_requires_new_candidate?(error)).to be(false)
    end

    it 'is false for errors that are not SolanaErrors, and for non-errors' do
      expect(described_class.message_packer_error_that_requires_new_candidate?(ArgumentError.new)).to be(false)
      expect(described_class.message_packer_error_that_requires_new_candidate?(nil)).to be(false)
    end
  end

  # kit 75653e9b: a total size that was an exact multiple of the realloc limit
  # used to end in a zero-sized instruction, because the last chunk was sized
  # `total_size % REALLOC_LIMIT`.
  describe '.get_realloc_message_packer_instruction_plan' do
    let(:system_program) { RubyKit::Addresses.address('11111111111111111111111111111111') }
    let(:fee_payer) { RubyKit::Addresses.get_address_from_public_key(RbNaCl::SigningKey.generate.verify_key) }
    let(:message) do
      RubyKit::TransactionMessages.create_transaction_message(version: :legacy)
        .then { |m| RubyKit::TransactionMessages.set_fee_payer(fee_payer, m) }
        .then do |m|
          RubyKit::TransactionMessages.set_blockhash_lifetime(
            RubyKit::TransactionMessages::BlockhashLifetimeConstraint.new(
              blockhash: '4PZNQ5MjgFMRSAEKFbMrgCkKAJAV2VEDiJFy1JoqyN3f', last_valid_block_height: 9999
            ),
            m
          )
        end
    end
    let(:get_instruction) do
      ->(size) { RubyKit::Instructions::Instruction.new(program_address: system_program, accounts: [], data: "Size: #{size}") }
    end

    def packer_for(total_size)
      described_class.get_realloc_message_packer_instruction_plan(total_size: total_size, get_instruction: get_instruction)
                     .get_message_packer.call
    end

    it 'splits the remainder into a final, smaller chunk' do
      packer = packer_for(25_000)
      expect(packer.pack_message_to_capacity(message).instructions.map(&:data))
        .to eq(['Size: 10240', 'Size: 10240', 'Size: 4520'])
      expect(packer.done?).to be(true)
    end

    it 'creates a single full-sized instruction when the total size equals the realloc limit' do
      packer = packer_for(10_240)
      expect(packer.pack_message_to_capacity(message).instructions.map(&:data)).to eq(['Size: 10240'])
      expect(packer.done?).to be(true)
    end

    it 'creates only full-sized instructions when the total size is a multiple of the realloc limit' do
      packer = packer_for(20_480)
      expect(packer.pack_message_to_capacity(message).instructions.map(&:data)).to eq(['Size: 10240', 'Size: 10240'])
      expect(packer.done?).to be(true)
    end

    it 'creates no instructions when the total size is zero' do
      packer = packer_for(0)
      expect(packer.done?).to be(true)
      expect { packer.pack_message_to_capacity(message) }.to raise_error(RubyKit::SolanaError) { |e|
        expect(e.code).to eq(RubyKit::SolanaError::INSTRUCTION_PLANS__MESSAGE_PACKER_ALREADY_COMPLETE)
      }
    end
  end
end
