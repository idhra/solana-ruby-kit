# typed: ignore
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyKit::InstructionPlans do
  let(:system_program) { RubyKit::Addresses.address('11111111111111111111111111111111') }
  let(:fee_payer_kp) { RbNaCl::SigningKey.generate }
  let(:fee_payer) { RubyKit::Addresses.get_address_from_public_key(fee_payer_kp.verify_key) }
  let(:blockhash_constraint) do
    RubyKit::TransactionMessages::BlockhashLifetimeConstraint.new(
      blockhash: '4PZNQ5MjgFMRSAEKFbMrgCkKAJAV2VEDiJFy1JoqyN3f',
      last_valid_block_height: 9999
    )
  end
  let(:create_transaction_message) do
    -> {
      RubyKit::TransactionMessages.create_transaction_message(version: :legacy)
        .then { |m| RubyKit::TransactionMessages.set_fee_payer(fee_payer, m) }
        .then { |m| RubyKit::TransactionMessages.set_blockhash_lifetime(blockhash_constraint, m) }
    }
  end
  let(:dummy_instruction) do
    RubyKit::Instructions::Instruction.new(
      program_address: system_program,
      accounts:        [],
      data:            ''
    )
  end

  def instructions(count)
    Array.new(count) { dummy_instruction }
  end

  describe '.create_transaction_planner' do
    it 'packs instructions under the default 16-per-transaction cap into a single message' do
      planner = described_class.create_transaction_planner(create_transaction_message: create_transaction_message)
      plan    = planner.call(described_class.sequential_instruction_plan(instructions(16)))

      expect(plan.kind).to eq(:single)
      expect(plan.message.instructions.length).to eq(16)
    end

    it 'splits across transactions once the default 16-per-transaction cap is exceeded' do
      planner = described_class.create_transaction_planner(create_transaction_message: create_transaction_message)
      plan    = planner.call(described_class.sequential_instruction_plan(instructions(17)))

      expect(plan.kind).to eq(:sequential)
      expect(plan.plans.map { |p| p.message.instructions.length }).to eq([16, 1])
    end

    it 'honors a configured max_instructions_per_transaction' do
      planner = described_class.create_transaction_planner(
        create_transaction_message: create_transaction_message,
        max_instructions_per_transaction: 2
      )
      plan = planner.call(described_class.sequential_instruction_plan(instructions(5)))

      expect(plan.kind).to eq(:sequential)
      expect(plan.plans.map { |p| p.message.instructions.length }).to eq([2, 2, 1])
    end

    it 'lets a per-call max_instructions_per_transaction override the config default' do
      planner = described_class.create_transaction_planner(
        create_transaction_message: create_transaction_message,
        max_instructions_per_transaction: 2
      )
      plan = planner.call(
        described_class.sequential_instruction_plan(instructions(3)),
        max_instructions_per_transaction: 3
      )

      expect(plan.kind).to eq(:single)
      expect(plan.message.instructions.length).to eq(3)
    end

    it 'caps a message packer plan at the configured max_instructions_per_transaction' do
      planner = described_class.create_transaction_planner(
        create_transaction_message: create_transaction_message,
        max_instructions_per_transaction: 3
      )
      packer_plan = described_class.get_message_packer_instruction_plan_from_instructions(instructions(7))
      plan        = planner.call(packer_plan)

      expect(plan.kind).to eq(:sequential)
      expect(plan.plans.map { |p| p.message.instructions.length }).to eq([3, 3, 1])
    end

    it 'raises for a zero max_instructions_per_transaction' do
      planner = described_class.create_transaction_planner(
        create_transaction_message: create_transaction_message,
        max_instructions_per_transaction: 0
      )

      expect { planner.call(described_class.sequential_instruction_plan(instructions(1))) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::INSTRUCTION_PLANS__INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION)
        }
    end

    it 'raises for a max_instructions_per_transaction above the 64-instruction transaction format limit' do
      planner = described_class.create_transaction_planner(
        create_transaction_message: create_transaction_message,
        max_instructions_per_transaction: 65
      )

      expect { planner.call(described_class.sequential_instruction_plan(instructions(1))) }
        .to raise_error(RubyKit::SolanaError) { |e|
          expect(e.code).to eq(RubyKit::SolanaError::INSTRUCTION_PLANS__INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION)
        }
    end
  end

  # kit 5be269c6: a custom message packer can refuse a message for a reason of
  # its own by raising MESSAGE_REJECTED_BY_PACKER, and the planner treats that
  # like any other capacity error.
  describe 'custom message packer rejections' do
    def instruction(tag)
      RubyKit::Instructions::Instruction.new(program_address: system_program, accounts: [], data: tag)
    end

    # A packer over +ixs+ that packs one instruction per call, but first asks
    # +reject_reason+ whether to refuse the message it was handed.
    def rejecting_packer_plan(ixs, &reject_reason)
      RubyKit::InstructionPlans::MessagePackerInstructionPlan.new(
        get_message_packer: -> {
          idx = 0
          RubyKit::InstructionPlans::MessagePacker.new(
            done_proc: -> { idx >= ixs.length },
            pack_proc: ->(message, _max_instructions) {
              reason = reject_reason.call(message)
              if reason
                raise RubyKit::SolanaError.new(
                  RubyKit::SolanaError::INSTRUCTION_PLANS__MESSAGE_REJECTED_BY_PACKER, { reason: reason }
                )
              end
              ix = ixs[idx]
              idx += 1
              RubyKit::TransactionMessages.append_instructions(message, [ix])
            }
          )
        }
      )
    end

    let(:reject_non_empty) { ->(message) { 'message is not empty' unless message.instructions.empty? } }
    let(:planner) { described_class.create_transaction_planner(create_transaction_message: create_transaction_message) }

    def data_per_message(plan)
      plan.plans.map { |p| p.message.instructions.map(&:data) }
    end

    it 'opens a new transaction message when a message packer rejects the candidate message' do
      plan = planner.call(
        described_class.sequential_instruction_plan(
          [
            described_class.single_instruction_plan(instruction('A')),
            rejecting_packer_plan([instruction('B'), instruction('C')], &reject_non_empty)
          ]
        )
      )

      expect(plan.kind).to eq(:sequential)
      expect(data_per_message(plan)).to eq([['A'], ['B'], ['C']])
    end

    it 'falls back to a new message when a packer rejects the parent candidate of a non-divisible plan' do
      plan = planner.call(
        described_class.sequential_instruction_plan(
          [
            described_class.single_instruction_plan(instruction('A')),
            described_class.non_divisible_sequential_instruction_plan(
              [rejecting_packer_plan([instruction('B')], &reject_non_empty)]
            )
          ]
        )
      )

      expect(plan.kind).to eq(:sequential)
      expect(data_per_message(plan)).to eq([['A'], ['B']])
    end

    it 'propagates the rejection when a packer rejects even a fresh transaction message' do
      always_rejecting = rejecting_packer_plan([instruction('A')]) { 'this packer rejects every message' }

      expect { planner.call(always_rejecting) }.to raise_error(RubyKit::SolanaError) { |e|
        expect(e.code).to eq(RubyKit::SolanaError::INSTRUCTION_PLANS__MESSAGE_REJECTED_BY_PACKER)
        expect(e.context).to eq(reason: 'this packer rejects every message')
        expect(e.message).to eq('The message packer rejected the provided transaction message: this packer rejects every message.')
      }
    end

    it 'still propagates errors that do not call for a new candidate' do
      boom = RubyKit::InstructionPlans::MessagePackerInstructionPlan.new(
        get_message_packer: -> {
          RubyKit::InstructionPlans::MessagePacker.new(
            done_proc: -> { false },
            pack_proc: ->(_message, _max) { raise RubyKit::SolanaError.new(RubyKit::SolanaError::INVALID_NONCE) }
          )
        }
      )
      plan = described_class.sequential_instruction_plan([described_class.single_instruction_plan(instruction('A')), boom])

      expect { planner.call(plan) }.to raise_error(RubyKit::SolanaError) { |e|
        expect(e.code).to eq(RubyKit::SolanaError::INVALID_NONCE)
      }
    end
  end
end
