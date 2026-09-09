# typed: strict
# frozen_string_literal: true

require_relative '../errors'

module Solana::Ruby::Kit
  module RpcTypes
    extend T::Sig
    # The smallest denomination of SOL (1 SOL = 1_000_000_000 lamports).
    # Mirrors TypeScript's `Lamports` branded bigint.
    # In Ruby, arbitrary-precision Integer replaces JS bigint with no loss of range.
    #
    # Valid range: 0 .. 18_446_744_073_709_551_615  (u64)
    Lamports = T.type_alias { Integer }

    LAMPORTS_U64_MAX = T.let(T.unsafe(2**64 - 1), Integer)

    extend self

    # Returns true if the integer is a valid u64 lamport value.
    # Mirrors `isLamports()`.
    sig { params(value: T.untyped).returns(T::Boolean) }
    def lamports?(value)
      !!(value.is_a?(Integer) && value >= 0 && value <= LAMPORTS_U64_MAX)
    end

    # Raises SolanaError if the value is not a valid lamport amount.
    # Mirrors `assertIsLamports()`.
    sig { params(value: T.untyped).void }
    def assert_lamports!(value)
      Kernel.raise SolanaError.new(:SOLANA_ERROR__LAMPORTS__AMOUNT_MUST_BE_POSITIVE) if value.is_a?(Integer) && value < 0
      Kernel.raise SolanaError.new(:SOLANA_ERROR__LAMPORTS__AMOUNT_OUT_OF_RANGE) unless lamports?(value)
    end

    # Validates and returns the lamport value.
    # Mirrors `lamports()`.
    sig { params(value: Integer).returns(Integer) }
    def lamports(value)
      assert_lamports!(value)
      value
    end
  end
end
