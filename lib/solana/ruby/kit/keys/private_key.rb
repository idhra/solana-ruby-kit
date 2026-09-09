# typed: strict
# frozen_string_literal: true

require 'rbnacl'
require_relative '../errors'

module Solana::Ruby::Kit
  module Keys
    extend T::Sig
    extend self

    # Creates an Ed25519 signing key from a raw 32-byte private key seed.
    #
    # Mirrors `createPrivateKeyFromBytes(bytes, extractable)` in TypeScript.
    # TypeScript wraps the raw seed in a PKCS#8 ASN.1 header before calling
    # `crypto.subtle.importKey` because the Web Crypto API requires PKCS#8 format.
    # In Ruby, RbNaCl::SigningKey accepts raw 32-byte seeds directly, so no
    # wrapping is necessary.
    #
    # The `extractable` parameter exists for API parity with the TypeScript
    # original. RbNaCl::SigningKey always allows seed extraction via `#to_bytes`.
    # Pass `extractable: false` to signal intent; enforcement is caller-side.
    #
    # @param bytes      [String] 32-byte binary string (Ed25519 private key seed)
    # @param extractable [Boolean] whether the raw seed may be re-exported (advisory)
    # @return [RbNaCl::SigningKey]
    sig { params(bytes: String, extractable: T::Boolean).returns(T.untyped) }
    def create_private_key_from_bytes(bytes, extractable: false)
      if bytes.bytesize != 32
        Kernel.raise SolanaError.new(
          SolanaError::KEYS__INVALID_KEY_PAIR_BYTE_LENGTH,
          byte_length: bytes.bytesize
        )
      end

      RbNaCl::SigningKey.new(bytes.b)
    end
  end
end
