# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative 'roles'

module Solana::Ruby::Kit
  module Instructions
    extend T::Sig
    # Metadata for a single account referenced by an instruction.
    # Mirrors TypeScript's `AccountMeta<TAddress>`.
    #
    # Combines an address with an `AccountRole` that declares whether the
    # account is a signer, writable, or both.
    class AccountMeta < T::Struct
      const :address, Addresses::Address
      const :role,    Integer  # one of AccountRole constants
    end

    # AccountMeta subtypes — mirrors the four TypeScript convenience types.

    extend self

    # Creates a read-only account reference.
    sig { params(address: Addresses::Address).returns(AccountMeta) }
    def readonly_account(address)
      AccountMeta.new(address: address, role: AccountRole::READONLY)
    end

    # Creates a writable account reference.
    sig { params(address: Addresses::Address).returns(AccountMeta) }
    def writable_account(address)
      AccountMeta.new(address: address, role: AccountRole::WRITABLE)
    end

    # Creates a read-only signer account reference.
    sig { params(address: Addresses::Address).returns(AccountMeta) }
    def readonly_signer_account(address)
      AccountMeta.new(address: address, role: AccountRole::READONLY_SIGNER)
    end

    # Creates a writable signer account reference.
    sig { params(address: Addresses::Address).returns(AccountMeta) }
    def writable_signer_account(address)
      AccountMeta.new(address: address, role: AccountRole::WRITABLE_SIGNER)
    end

    # -------------------------------------------------------------------
    # Address lookup table accounts
    # Mirrors TypeScript's `AccountLookupMeta<TAddress, TLookupTableAddress>`.
    # Accounts resolved through a lookup table cannot act as signers.
    # -------------------------------------------------------------------
    class AccountLookupMeta < T::Struct
      const :address,              Addresses::Address
      const :address_index,        Integer
      const :lookup_table_address, Addresses::Address
      const :role,                 Integer  # READONLY or WRITABLE only
    end

    sig { params(address: Addresses::Address, lookup_table_address: Addresses::Address, address_index: Integer).returns(AccountLookupMeta) }
    def readonly_lookup_account(address, lookup_table_address:, address_index:)
      AccountLookupMeta.new(
        address: address,
        address_index: address_index,
        lookup_table_address: lookup_table_address,
        role: AccountRole::READONLY
      )
    end

    sig { params(address: Addresses::Address, lookup_table_address: Addresses::Address, address_index: Integer).returns(AccountLookupMeta) }
    def writable_lookup_account(address, lookup_table_address:, address_index:)
      AccountLookupMeta.new(
        address: address,
        address_index: address_index,
        lookup_table_address: lookup_table_address,
        role: AccountRole::WRITABLE
      )
    end
  end
end
