# typed: strict
# frozen_string_literal: true

require 'digest'
require_relative 'address'
require_relative 'curve'
require_relative '../errors'

module Solana::Ruby::Kit
  module Addresses
    extend T::Sig
    # The integer bump seed used when deriving a PDA.  Must be in [0, 255].
    # Mirrors TypeScript: `type ProgramDerivedAddressBump = Brand<number, 'ProgramDerivedAddressBump'>`
    ProgramDerivedAddressBump = T.type_alias { Integer }

    # A PDA is an (address, bump_seed) pair.
    # Mirrors TypeScript: `type ProgramDerivedAddress = [Address, ProgramDerivedAddressBump]`
    class ProgramDerivedAddress < T::Struct
      const :address, Address
      const :bump,    Integer   # 0–255
    end

    # Accepted seed types mirror TypeScript's `Seeds` union:
    #   type Seed = ReadonlyUint8Array | string
    # In Ruby, a seed is either a binary String or an Integer Array.
    Seed = T.type_alias { T.any(String, T::Array[Integer]) }

    # ---------------------------------------------------------------------------
    # Constants
    # ---------------------------------------------------------------------------

    # Maximum byte length of a single seed.
    MAX_SEED_LENGTH = T.let(32, Integer)

    # Maximum number of seeds per PDA derivation.
    MAX_SEEDS = T.let(16, Integer)

    # Marker bytes appended during hashing: UTF-8 "ProgramDerivedAddress".
    PDA_MARKER_BYTES = T.let('ProgramDerivedAddress'.b, String)

    extend self

    # Returns true if the value is a well-formed ProgramDerivedAddress.
    # Mirrors `isProgramDerivedAddress()` in TypeScript.
    sig { params(value: T.untyped).returns(T::Boolean) }
    def program_derived_address?(value)
      return false unless value.is_a?(ProgramDerivedAddress)
      return false unless address?(value.address.value)

      bump = value.bump
      bump.between?(0, 255)
    end

    # Raises SolanaError if the value is not a valid ProgramDerivedAddress.
    # Mirrors `assertIsProgramDerivedAddress()` in TypeScript.
    sig { params(value: T.untyped).void }
    def assert_program_derived_address!(value)
      Kernel.raise SolanaError.new(SolanaError::ADDRESSES__INVALID_SEEDS_POINT_ON_CURVE) unless value.is_a?(ProgramDerivedAddress)
      Kernel.raise SolanaError.new(SolanaError::ADDRESSES__PDA_BUMP_SEED_OUT_OF_RANGE) unless value.bump.between?(0, 255)
    end

    # Derives the Program Derived Address for a given program and up to 16 seeds.
    #
    # Searches from bump seed 255 down to 0, returning the first address whose
    # 32-byte SHA-256 hash does NOT lie on the Ed25519 curve.
    #
    # Mirrors `getProgramDerivedAddress()` in TypeScript.
    sig do
      params(
        program_address: Address,
        seeds:           T::Array[Seed]
      ).returns(ProgramDerivedAddress)
    end
    def get_program_derived_address(program_address:, seeds:)
      if seeds.length > MAX_SEEDS
        Kernel.raise SolanaError.new(SolanaError::ADDRESSES__TOO_MANY_SEEDS)
      end

      seeds.each do |seed|
        seed_bytes = seed_to_bytes(seed)
        if seed_bytes.bytesize > MAX_SEED_LENGTH
          Kernel.raise SolanaError.new(
            SolanaError::ADDRESSES__MAX_SEED_LENGTH_EXCEEDED,
            actual_length: seed_bytes.bytesize
          )
        end
      end

      program_bytes = decode_address(program_address)

      255.downto(0) do |bump|
        seed_bytes_list = seeds.map { |s| seed_to_bytes(s) }
        bump_bytes       = [bump].pack('C').b

        # hash_input = seed1 || seed2 || ... || bump || program_address || "ProgramDerivedAddress"
        hash_input = (seed_bytes_list + [bump_bytes, program_bytes, PDA_MARKER_BYTES]).join

        candidate_bytes = Digest::SHA256.digest(hash_input)

        next if on_ed25519_curve?(candidate_bytes)

        candidate_address = Address.new(encode_address(candidate_bytes))
        return ProgramDerivedAddress.new(address: candidate_address, bump: bump)
      end

      Kernel.raise SolanaError.new(SolanaError::ADDRESSES__FAILED_TO_FIND_VIABLE_PDA_BUMP_SEED)
    end

    # Derives an address from a base address, program address, and an arbitrary seed.
    # Uses SHA-256 of (base_address || seed || program_address).
    #
    # Mirrors `createAddressWithSeed()` in TypeScript.
    sig do
      params(
        base_address:    Address,
        program_address: Address,
        seed:            String
      ).returns(Address)
    end
    def create_address_with_seed(base_address:, program_address:, seed:)
      seed_bytes = seed.b

      if seed_bytes.bytesize > MAX_SEED_LENGTH
        Kernel.raise SolanaError.new(
          SolanaError::ADDRESSES__MAX_SEED_LENGTH_EXCEEDED,
          actual_length: seed_bytes.bytesize
        )
      end

      base_bytes    = decode_address(base_address)
      program_bytes = decode_address(program_address)

      # hash_input = base_address || seed || program_address
      hash_input   = base_bytes + seed_bytes + program_bytes
      result_bytes = Digest::SHA256.digest(hash_input)

      Address.new(encode_address(result_bytes))
    end

    # ---------------------------------------------------------------------------
    # Private helpers
    # ---------------------------------------------------------------------------

    # Converts a Seed (binary String or Integer Array) to a binary String.
    sig { params(seed: Seed).returns(String) }
    def seed_to_bytes(seed)
      case seed
      when String then seed.b
      when Array  then seed.pack('C*').b
      else T.absurd(seed)
      end
    end
    private_class_method :seed_to_bytes
  end
end
