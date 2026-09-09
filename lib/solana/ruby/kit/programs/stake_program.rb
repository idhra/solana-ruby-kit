# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative '../encoding/base58'
require_relative '../instructions/instruction'
require_relative '../instructions/accounts'
require_relative '../sysvars/addresses'
require_relative 'system_program'

module Solana::Ruby::Kit
  module Programs
    # Ruby interface for the Solana Stake Program.
    #
    # The Stake Program manages stake accounts used for delegating SOL to
    # validators and earning staking rewards.  Instruction data uses
    # little-endian encoding: a u32 discriminator followed by any
    # instruction-specific fields.
    #
    # Reference: https://github.com/solana-labs/solana-web3.js/blob/master/packages/library-legacy/src/programs/stake.ts
    module StakeProgram
      extend T::Sig

      # The Stake Program address.
      PROGRAM_ID = T.let(
        Addresses::Address.new('Stake11111111111111111111111111111111111111'),
        Addresses::Address
      )

      # The Stake Config sysvar / config account.
      STAKE_CONFIG_ID = T.let(
        Addresses::Address.new('StakeConfig11111111111111111111111111111111'),
        Addresses::Address
      )

      # Number of bytes required to store a stake account on-chain.
      STAKE_ACCOUNT_SPACE = T.let(200, Integer)

      # Instruction discriminators (u32 little-endian).
      DISCRIMINATOR_INITIALIZE    = T.let(0, Integer)
      DISCRIMINATOR_DELEGATE      = T.let(2, Integer)

      extend self

      # Builds the two instructions needed to create and initialise a new stake
      # account funded from +from+.
      #
      # Instruction 0 — System Program createAccount
      #   Data layout (52 bytes):
      #     [0..3]   u32 LE = 0          (CREATE_ACCOUNT discriminant)
      #     [4..11]  u64 LE = lamports
      #     [12..19] u64 LE = 200        (STAKE_ACCOUNT_SPACE)
      #     [20..51] 32 bytes            (Stake Program ID — the owner to assign)
      #   Pack string: 'VQ<Q<a32'
      #
      # Instruction 1 — Stake Program Initialize
      #   Data layout (116 bytes):
      #     [0..3]    u32 LE = 0          (Initialize discriminant)
      #     [4..35]   32 bytes            (authorized staker pubkey)
      #     [36..67]  32 bytes            (authorized withdrawer pubkey)
      #     [68..75]  i64 LE = 0          (lockup unix_timestamp — no lockup)
      #     [76..83]  u64 LE = 0          (lockup epoch — no lockup)
      #     [84..115] 32 bytes = \x00*32  (lockup custodian — zero pubkey)
      #   Pack string: 'Va32a32q<Q<a32'
      #
      # @param from          [Addresses::Address]  funding account (writable, signer)
      # @param stake_account [Addresses::Address]  new stake account (writable, signer)
      # @param authorized    [Addresses::Address]  pubkey set as both staker and withdrawer
      # @param lamports      [Integer]             total lamports to fund the stake account
      # @return [T::Array[Instructions::Instruction]]
      sig do
        params(
          from:          Addresses::Address,
          stake_account: Addresses::Address,
          authorized:    Addresses::Address,
          lamports:      Integer
        ).returns(T::Array[Instructions::Instruction])
      end
      def create_account_instructions(from:, stake_account:, authorized:, lamports:)
        stake_program_bytes = Encoding::Base58.decode(PROGRAM_ID.value)
        authorized_bytes    = Encoding::Base58.decode(authorized.value)
        zero_pubkey         = ("\x00" * 32).b

        # Instruction 0: System Program createAccount (discriminant = 0)
        create_data = [0, lamports, STAKE_ACCOUNT_SPACE, stake_program_bytes].pack('VQ<Q<a32').b

        create_account_ix = Instructions::Instruction.new(
          program_address: SystemProgram::PROGRAM_ID,
          accounts: [
            Instructions.writable_signer_account(from),          # 0 from
            Instructions.writable_signer_account(stake_account), # 1 stake_account
          ],
          data: create_data
        )

        # Instruction 1: Stake Program Initialize
        initialize_data = [
          DISCRIMINATOR_INITIALIZE,
          authorized_bytes,  # staker
          authorized_bytes,  # withdrawer
          0,                 # lockup.unix_timestamp (i64)
          0,                 # lockup.epoch (u64)
          zero_pubkey        # lockup.custodian
        ].pack('Va32a32q<Q<a32').b

        initialize_ix = Instructions::Instruction.new(
          program_address: PROGRAM_ID,
          accounts: [
            Instructions.writable_account(stake_account),                                       # 0 stake_account
            Instructions.readonly_account(Addresses::Address.new(Sysvars::SYSVAR_RENT_ADDRESS)), # 1 sysvar rent
          ],
          data: initialize_data
        )

        [create_account_ix, initialize_ix]
      end

      # Builds a DelegateStake instruction that delegates an initialised stake
      # account to a validator vote account.
      #
      # Data layout (4 bytes):
      #   [0..3] u32 LE = 2   (DelegateStake discriminant)
      # Pack string: 'V'
      #
      # Accounts:
      #   0. stake_account        — writable, not signer
      #   1. vote_account         — readonly, not signer
      #   2. SYSVAR_CLOCK         — readonly, not signer
      #   3. SYSVAR_STAKE_HISTORY — readonly, not signer
      #   4. STAKE_CONFIG_ID      — readonly, not signer
      #   5. authorized           — readonly, signer
      #
      # @param stake_account [Addresses::Address]  stake account to delegate
      # @param vote_account  [Addresses::Address]  validator's vote account
      # @param authorized    [Addresses::Address]  authorised staker (must sign)
      # @return [Instructions::Instruction]
      sig do
        params(
          stake_account: Addresses::Address,
          vote_account:  Addresses::Address,
          authorized:    Addresses::Address
        ).returns(Instructions::Instruction)
      end
      def delegate_instruction(stake_account:, vote_account:, authorized:)
        data = [DISCRIMINATOR_DELEGATE].pack('V').b

        Instructions::Instruction.new(
          program_address: PROGRAM_ID,
          accounts: [
            Instructions.writable_account(stake_account),                                             # 0 stake_account
            Instructions.readonly_account(vote_account),                                               # 1 vote_account
            Instructions.readonly_account(Addresses::Address.new(Sysvars::SYSVAR_CLOCK_ADDRESS)),      # 2 clock
            Instructions.readonly_account(Addresses::Address.new(Sysvars::SYSVAR_STAKE_HISTORY_ADDRESS)), # 3 stake history
            Instructions.readonly_account(STAKE_CONFIG_ID),                                            # 4 stake config
            Instructions.readonly_signer_account(authorized),                                          # 5 authorized staker
          ],
          data: data
        )
      end
    end
  end
end
