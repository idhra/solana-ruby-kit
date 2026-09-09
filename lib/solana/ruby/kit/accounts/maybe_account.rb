# typed: strict
# frozen_string_literal: true

require_relative '../addresses/address'
require_relative '../errors'
require_relative 'account'

module Solana::Ruby::Kit
  module Accounts
    extend T::Sig
    # Represents an account that may or may not exist on-chain.
    # Mirrors TypeScript's discriminated union:
    #   MaybeAccount<TData, TAddress> = Account<TData, TAddress> & { exists: true }
    #                                 | { address: Address<TAddress>; exists: false }
    #
    # In Ruby we use a single class with an `exists` flag rather than a union
    # type, since Sorbet cannot narrow struct unions at runtime as easily.
    class MaybeAccount < T::Struct
      # true  → the account exists; all Account fields are populated.
      # false → the account does not exist; only `address` is set.
      const :exists,          T::Boolean
      const :address,         Addresses::Address
      # The following fields are only valid when exists == true.
      const :data,            T.untyped          # nil when exists == false
      const :executable,      T.nilable(T::Boolean)
      const :lamports,        T.nilable(Integer)
      const :program_address, T.nilable(Addresses::Address)
      const :space,           T.nilable(Integer)
    end

    extend self

    # Builds a MaybeAccount representing a found account.
    sig { params(account: Account).returns(MaybeAccount) }
    def existing_account(account)
      MaybeAccount.new(
        exists:          true,
        address:         account.address,
        data:            account.data,
        executable:      account.executable,
        lamports:        account.lamports,
        program_address: account.program_address,
        space:           account.space
      )
    end

    # Builds a MaybeAccount representing a missing account.
    sig { params(address: Addresses::Address).returns(MaybeAccount) }
    def missing_account(address)
      MaybeAccount.new(
        exists:          false,
        address:         address,
        data:            nil,
        executable:      nil,
        lamports:        nil,
        program_address: nil,
        space:           nil
      )
    end

    # Raises SolanaError if the account does not exist.
    # Mirrors `assertAccountExists()`.
    sig { params(maybe_account: MaybeAccount).void }
    def assert_account_exists!(maybe_account)
      return if maybe_account.exists

      Kernel.raise SolanaError.new(
        :SOLANA_ERROR__ACCOUNTS__ACCOUNT_NOT_FOUND,
        address: maybe_account.address.value
      )
    end

    # Raises SolanaError listing all missing addresses if any account is absent.
    # Mirrors `assertAccountsExist()`.
    sig { params(maybe_accounts: T::Array[MaybeAccount]).void }
    def assert_accounts_exist!(maybe_accounts)
      missing = maybe_accounts.reject(&:exists).map { |a| a.address.value }
      return if missing.empty?

      Kernel.raise SolanaError.new(
        :SOLANA_ERROR__ACCOUNTS__ONE_OR_MORE_ACCOUNTS_NOT_FOUND,
        addresses: missing
      )
    end
  end
end
