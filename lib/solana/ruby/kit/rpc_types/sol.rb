# typed: strict
# frozen_string_literal: true

require 'bigdecimal'
require_relative '../errors'
require_relative 'lamports'

module Solana::Ruby::Kit
  module RpcTypes
    # SOL amounts expressed as a decimal fixed-point value with 9 decimal places.
    # 1 SOL == 1_000_000_000 lamports, so Sol#raw is the exact Lamports count.
    #
    # Mirrors TypeScript's Sol (DecimalFixedPoint<'unsigned', 64, 9>).
    class Sol
      extend T::Sig

      # The Lamports count as an unsigned integer (u64 range).
      sig { returns(Integer) }
      attr_reader :raw

      sig { params(raw: Integer).void }
      def initialize(raw)
        @raw = T.let(raw, Integer)
        freeze
      end

      # Returns the decimal string representation (e.g. "1.5", "0.000000001").
      sig { returns(String) }
      def to_s
        whole    = @raw / 10**9
        fraction = @raw % 10**9
        return whole.to_s if fraction.zero?

        frac_str = fraction.to_s.rjust(9, '0').sub(/0+\z/, '')
        "#{whole}.#{frac_str}"
      end

      sig { returns(String) }
      def inspect = "#<#{self.class} #{self}>"

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Sol)

        @raw == other.raw
      end

      sig { returns(Integer) }
      def hash = @raw.hash

      alias eql? ==
    end

    SOL_DECIMALS    = T.let(9,         Integer)
    SOL_SCALE       = T.let(1_000_000_000, Integer)
    SOL_RAW_MAX     = T.let(Kernel.Integer(2**64 - 1), Integer)

    extend self

    # Parses a decimal string and returns a Sol value.
    # Raises FIXED_POINTS__STRICT_MODE_PRECISION_LOSS if the string has more
    # than 9 fractional digits (mirrors TypeScript's default 'strict' mode).
    #
    # Examples:
    #   sol('1.5')           # => Sol(raw: 1_500_000_000)
    #   sol('0.000000001')   # => Sol(raw: 1) — one lamport
    #
    # Mirrors TypeScript's sol(value, rounding?).
    sig { params(value: String).returns(Sol) }
    def sol(value)
      bd = Kernel.BigDecimal(value)
      Kernel.raise SolanaError.new(SolanaError::FIXED_POINTS__STRICT_MODE_PRECISION_LOSS) if bd < 0

      scaled = bd * SOL_SCALE
      raw    = scaled.to_i

      unless scaled == Kernel.BigDecimal(raw.to_s)
        Kernel.raise SolanaError.new(SolanaError::FIXED_POINTS__STRICT_MODE_PRECISION_LOSS)
      end

      Kernel.raise SolanaError.new(SolanaError::LAMPORTS_OUT_OF_RANGE) if raw > SOL_RAW_MAX

      Sol.new(raw)
    end

    # Converts a Sol value to its equivalent Lamports integer.
    # The conversion is exact — Sol#raw is the Lamports count.
    #
    # Mirrors TypeScript's solToLamports(value).
    sig { params(value: Sol).returns(Lamports) }
    def sol_to_lamports(value)
      value.raw
    end

    # Converts a Lamports integer to its equivalent Sol value.
    # The conversion is exact.
    #
    # Mirrors TypeScript's lamportsToSol(value).
    sig { params(value: Lamports).returns(Sol) }
    def lamports_to_sol(value)
      Sol.new(value)
    end
  end
end
