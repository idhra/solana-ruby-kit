# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  # Function composition utilities.
  # Mirrors the TypeScript package @solana/functional.
  module Functional
    extend T::Sig
    extend self

    # Passes an initial value through a series of single-argument callables,
    # returning the final result.
    #
    # Mirrors TypeScript's `pipe(init, fn1, fn2, ...)`.  TypeScript requires
    # 10 overloads for static typing; Ruby achieves the same with a single
    # variadic implementation.
    #
    # @example Building a transaction message
    #   msg = Solana::Ruby::Kit::Functional.pipe(
    #     Solana::Ruby::Kit::TransactionMessages.create_transaction_message(version: 0),
    #     ->(tx) { Solana::Ruby::Kit::TransactionMessages.set_fee_payer(fee_payer_address, tx) },
    #     ->(tx) { Solana::Ruby::Kit::TransactionMessages.set_blockhash_lifetime(blockhash, tx) },
    #   )
    sig { params(value: T.untyped, fns: T.proc.params(arg0: T.untyped).returns(T.untyped)).returns(T.untyped) }
    def pipe(value, *fns)
      fns.reduce(value) { |acc, fn| T.unsafe(fn).call(acc) }
    end
  end
end
