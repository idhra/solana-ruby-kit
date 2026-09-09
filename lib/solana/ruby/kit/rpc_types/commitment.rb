# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module RpcTypes
    extend T::Sig
    # Network confirmation level for an RPC request.
    # Mirrors TypeScript's `Commitment = 'finalized' | 'confirmed' | 'processed'`.
    #
    # Each level is a measure of how many validators have confirmed a block:
    #   - :finalized  — the block has been voted on by a supermajority and is permanent.
    #   - :confirmed  — the block has been voted on by a supermajority (not yet rooted).
    #   - :processed  — the node has seen the block but it may yet be rolled back.
    Commitment = T.type_alias { Symbol }

    FINALIZED = T.let(:finalized, Symbol)
    CONFIRMED = T.let(:confirmed, Symbol)
    PROCESSED = T.let(:processed, Symbol)

    VALID_COMMITMENTS = T.let(
      [FINALIZED, CONFIRMED, PROCESSED].freeze,
      T::Array[Symbol]
    )

    extend self

    # Returns a numeric score for a commitment level (higher = more confirmed).
    # Mirrors `getCommitmentScore()`.
    sig { params(commitment: Symbol).returns(Integer) }
    def commitment_score(commitment)
      case commitment
      when FINALIZED then 2
      when CONFIRMED then 1
      when PROCESSED then 0
      else Kernel.raise ArgumentError, "Unknown commitment: #{commitment.inspect}"
      end
    end

    # Compares two commitment levels.  Returns -1, 0, or 1.
    # Mirrors `commitmentComparator()`.
    sig { params(a: Symbol, b: Symbol).returns(Integer) }
    def commitment_comparator(a, b)
      commitment_score(a) <=> commitment_score(b)
    end

    # Returns true if the symbol is a valid commitment level.
    sig { params(value: T.untyped).returns(T::Boolean) }
    def commitment?(value)
      VALID_COMMITMENTS.include?(value)
    end
  end
end
