# typed: strict
# frozen_string_literal: true

require 'rbnacl'
require_relative '../errors'

module Solana::Ruby::Kit
  module Keys
    extend T::Sig
    extend self

    # Derives the Ed25519 verification (public) key from a signing (private) key.
    #
    # Mirrors `getPublicKeyFromPrivateKey(privateKey, extractable)` in TypeScript.
    # TypeScript exports the JWK representation of the private key and re-imports
    # only the public component because Web Crypto keys are opaque handles.
    # In Ruby, RbNaCl::SigningKey#verify_key returns the VerifyKey directly.
    #
    # @param signing_key [RbNaCl::SigningKey]
    # @param extractable [Boolean] advisory flag for API parity with TypeScript
    # @return [RbNaCl::VerifyKey]
    sig { params(signing_key: T.untyped, extractable: T::Boolean).returns(T.untyped) }
    def get_public_key_from_private_key(signing_key, extractable: false)
      unless signing_key.respond_to?(:verify_key)
        Kernel.raise SolanaError.new(SolanaError::ADDRESSES__INVALID_ED25519_PUBLIC_KEY)
      end

      signing_key.verify_key
    end
  end
end
