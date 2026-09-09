# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative '../instructions/instruction'
require_relative '../instructions/accounts'

module Solana::Ruby::Kit
  module Programs
    # Ruby interface for the Solana System Program (11111111111111111111111111111111).
    #
    # The System Program is responsible for creating accounts, transferring SOL,
    # and other low-level operations.  Instruction data uses little-endian encoding:
    # a u32 discriminator identifying the instruction variant, followed by any
    # instruction-specific fields.
    #
    # Reference: https://github.com/solana-program/system
    module SystemProgram
      extend T::Sig

      # The System Program address (all zeros, encoded in base58).
      PROGRAM_ID = T.let(
        Addresses::Address.new('11111111111111111111111111111111'),
        Addresses::Address
      )

      # Instruction discriminators (u32 little-endian).
      DISCRIMINATOR_TRANSFER = T.let(2, Integer)

      extend self

      # Builds a System Program Transfer instruction that moves +lamports+ from
      # +sender+ to +recipient+.
      #
      # Instruction data layout (12 bytes):
      #   [0..3]  u32 LE  — discriminator (2)
      #   [4..11] u64 LE  — lamports
      #
      # Accounts:
      #   0. sender    — writable, signer (source of SOL)
      #   1. recipient — writable         (destination)
      #
      # @param sender    [Addresses::Address]
      # @param recipient [Addresses::Address]
      # @param lamports  [Integer]  amount to transfer (1 SOL = 1_000_000_000 lamports)
      # @return [Instructions::Instruction]
      sig do
        params(
          sender:    Addresses::Address,
          recipient: Addresses::Address,
          lamports:  Integer
        ).returns(Instructions::Instruction)
      end
      def transfer_instruction(sender:, recipient:, lamports:)
        # Pack as: u32 LE discriminator || u64 LE lamports
        data = [DISCRIMINATOR_TRANSFER, lamports].pack('VQ<').b

        Instructions::Instruction.new(
          program_address: PROGRAM_ID,
          accounts: [
            Instructions.writable_signer_account(sender),    # 0 sender
            Instructions.writable_account(recipient),         # 1 recipient
          ],
          data: data
        )
      end
    end
  end
end
