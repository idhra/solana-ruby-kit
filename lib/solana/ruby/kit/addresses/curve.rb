# typed: strict
# frozen_string_literal: true

require_relative 'address'
require_relative '../errors'

module Solana::Ruby::Kit
  module Addresses
    extend T::Sig
    # OffCurveAddress marks an Address whose 32-byte representation does NOT lie
    # on the Ed25519 curve. PDAs are always off-curve by definition.
    #
    # Mirrors TypeScript:
    #   type OffCurveAddress = Brand<Address, AffinePoint>
    class OffCurveAddress < Address; end

    # ---------------------------------------------------------------------------
    # Ed25519 curve parameters (RFC 8032, Section 5.1)
    # ---------------------------------------------------------------------------

    # Field prime p = 2^255 − 19
    CURVE_P = T.let(T.unsafe(2**255 - 19), Integer)

    # Curve constant d = −121665/121666 mod p  (computed to avoid oversized literals)
    CURVE_D = T.let((-121665 * 121666.pow(CURVE_P - 2, CURVE_P)) % CURVE_P, Integer)

    # sqrt(−1) mod p  =  2^((p−1)/4) mod p
    CURVE_SQRT_M1 = T.let(2.pow((CURVE_P - 1) / 4, CURVE_P), Integer)

    extend self

    # Returns true if the 32-byte binary string represents a point on the
    # Ed25519 twisted-Edwards curve.
    #
    # Algorithm follows RFC 8032, Section 5.1.3 (point decompression):
    #   1. Extract y coordinate and the sign bit of x.
    #   2. Compute x² = (y²−1) / (d·y²+1)  mod p.
    #   3. Recover x using the curve's square-root formula.
    #   4. If no valid x exists the bytes are off-curve → return false.
    sig { params(bytes: String).returns(T::Boolean) }
    def on_ed25519_curve?(bytes)
      return false unless bytes.bytesize == 32

      p = CURVE_P
      d = CURVE_D

      y_arr = bytes.bytes.dup
      x_sign = (y_arr[31] >> 7) & 1
      y_arr[31] &= 0x7f

      # Little-endian byte array → big integer
      y = y_arr.each_with_index.sum { |b, i| b << (8 * i) }
      return false if y >= p

      y2 = y.pow(2, p)
      u  = (y2 - 1) % p       # numerator:   y² − 1
      v  = (d * y2 + 1) % p   # denominator: d·y² + 1

      # RFC 8032 square-root formula:
      #   x = (u·v³) · (u·v⁷)^((p−5)/8)  mod p
      v3   = v.pow(3, p)
      v7   = v.pow(7, p)
      exp  = (p - 5) / 8
      x    = u * v3 % p * (u * v7 % p).pow(exp, p) % p
      vx2  = v * x.pow(2, p) % p

      if vx2 == u % p
        # Valid root found; adjust sign.
        x = (p - x) % p if (x & 1) != x_sign
        return true
      end

      if vx2 == (p - u) % p
        # x must be multiplied by sqrt(−1).
        x = x * CURVE_SQRT_M1 % p
        x = (p - x) % p if (x & 1) != x_sign
        return true
      end

      false
    end

    # Returns true if the address bytes are NOT on the Ed25519 curve.
    sig { params(bytes: String).returns(T::Boolean) }
    def off_curve_bytes?(bytes)
      !on_ed25519_curve?(bytes)
    end

    # Type guard — returns true if the given Address is off-curve.
    # Mirrors `isOffCurveAddress()` in TypeScript.
    sig { params(addr: Address).returns(T::Boolean) }
    def off_curve_address?(addr)
      bytes = decode_address(addr)
      off_curve_bytes?(bytes)
    end

    # Raises SolanaError if the address is on the Ed25519 curve.
    # Mirrors `assertIsOffCurveAddress()` in TypeScript.
    sig { params(addr: Address).void }
    def assert_off_curve_address!(addr)
      Kernel.raise SolanaError.new(SolanaError::ADDRESSES__SEEDS_POINT_ON_CURVE) if on_ed25519_curve?(decode_address(addr))
    end

    # Validates and narrows an Address to OffCurveAddress.
    # Mirrors `offCurveAddress()` in TypeScript.
    sig { params(addr: Address).returns(OffCurveAddress) }
    def off_curve_address(addr)
      assert_off_curve_address!(addr)
      OffCurveAddress.new(addr.value)
    end
  end
end
