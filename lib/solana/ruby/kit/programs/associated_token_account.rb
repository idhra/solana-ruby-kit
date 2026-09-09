# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative '../addresses/program_derived_address'
require_relative '../instructions/instruction'
require_relative '../instructions/accounts'

module Solana::Ruby::Kit
  module Programs
    # Ruby interface for the SPL Associated Token Account on-chain program.
    #
    # An Associated Token Account (ATA) is a Program Derived Address that holds
    # SPL token balances for a given wallet + mint pair.  The ATA address is
    # deterministic: given a wallet and a mint, there is exactly one "canonical"
    # token account for that combination.
    #
    # Seeds used for PDA derivation (all raw 32-byte address buffers):
    #   [ wallet_bytes, token_program_bytes, mint_bytes ]
    # Program: PROGRAM_ID (the Associated Token Account program)
    #
    # Reference: https://github.com/solana-program/associated-token-account
    module AssociatedTokenAccount
      extend T::Sig

      # SPL Associated Token Account program.
      PROGRAM_ID = T.let(
        Addresses::Address.new('ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL'),
        Addresses::Address
      )

      # Original SPL Token program (spl-token).
      TOKEN_PROGRAM_ID = T.let(
        Addresses::Address.new('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'),
        Addresses::Address
      )

      # Token Extensions program (spl-token-2022).
      TOKEN_2022_PROGRAM_ID = T.let(
        Addresses::Address.new('TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb'),
        Addresses::Address
      )

      # Solana System Program.
      SYSTEM_PROGRAM_ID = T.let(
        Addresses::Address.new('11111111111111111111111111111111'),
        Addresses::Address
      )

      extend self

      # Derives the canonical Associated Token Account address (a PDA) for a
      # given wallet and mint.
      #
      # @param wallet           [Addresses::Address]  the account that will own the ATA
      # @param mint             [Addresses::Address]  the token mint
      # @param token_program_id [Addresses::Address]  TOKEN_PROGRAM_ID or TOKEN_2022_PROGRAM_ID
      # @return [Addresses::ProgramDerivedAddress]    the ATA address + bump seed
      sig do
        params(
          wallet:           Addresses::Address,
          mint:             Addresses::Address,
          token_program_id: Addresses::Address
        ).returns(Addresses::ProgramDerivedAddress)
      end
      def get_associated_token_address(wallet:, mint:, token_program_id: TOKEN_PROGRAM_ID)
        wallet_bytes        = Addresses.decode_address(wallet)
        token_program_bytes = Addresses.decode_address(token_program_id)
        mint_bytes          = Addresses.decode_address(mint)

        Addresses.get_program_derived_address(
          program_address: PROGRAM_ID,
          seeds:           [wallet_bytes, token_program_bytes, mint_bytes]
        )
      end

      # Builds an instruction that creates an Associated Token Account.
      #
      # Account layout expected by the on-chain program (in order):
      #   0. payer                    — writable, signer (funds the rent)
      #   1. associated_token_account — writable (the new ATA; derived via PDA)
      #   2. wallet                   — readonly  (the ATA's owner)
      #   3. mint                     — readonly
      #   4. system_program           — readonly
      #   5. token_program            — readonly
      #
      # Instruction data:
      #   nil / empty  →  "Create"         (fails if the ATA already exists)
      #   "\x01"       →  "CreateIdempotent" (no-op if already initialised)
      #
      # @param payer            [Addresses::Address]  pays for rent
      # @param wallet           [Addresses::Address]  will own the ATA
      # @param mint             [Addresses::Address]  token mint
      # @param token_program_id [Addresses::Address]  which token program to use
      # @param idempotent       [Boolean]             use the idempotent variant
      # @return [Instructions::Instruction]
      sig do
        params(
          payer:            Addresses::Address,
          wallet:           Addresses::Address,
          mint:             Addresses::Address,
          token_program_id: Addresses::Address,
          idempotent:       T::Boolean
        ).returns(Instructions::Instruction)
      end
      def create_instruction(
        payer:,
        wallet:,
        mint:,
        token_program_id: TOKEN_PROGRAM_ID,
        idempotent: false
      )
        ata = get_associated_token_address(wallet: wallet, mint: mint, token_program_id: token_program_id)

        # Discriminator: none for "Create", 0x01 for "CreateIdempotent"
        data = idempotent ? "\x01".b : nil

        Instructions::Instruction.new(
          program_address: PROGRAM_ID,
          accounts: [
            Instructions.writable_signer_account(payer),          # 0 payer
            Instructions.writable_account(ata.address),            # 1 ATA to create
            Instructions.readonly_account(wallet),                  # 2 owner (readonly)
            Instructions.readonly_account(mint),                    # 3 mint
            Instructions.readonly_account(SYSTEM_PROGRAM_ID),      # 4 System Program
            Instructions.readonly_account(token_program_id),       # 5 Token Program
          ],
          data: data
        )
      end
    end
  end
end
