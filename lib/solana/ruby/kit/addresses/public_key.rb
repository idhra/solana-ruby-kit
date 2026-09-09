# typed: strict
# frozen_string_literal: true

require 'rbnacl'
require_relative 'address'
require_relative '../errors'

module Solana::Ruby::Kit
  module Addresses
    extend T::Sig
    extend self

    # Given an RbNaCl::VerifyKey (Ed25519 public key), returns its Solana Address.
    #
    # Mirrors TypeScript's `getAddressFromPublicKey(publicKey: CryptoKey)`.
    # In TypeScript this is async because it uses Web Crypto API's `exportKey`.
    # In Ruby, RbNaCl exposes the raw bytes directly, so no async overhead is needed.
    sig { params(verify_key: T.untyped).returns(Address) }
    def get_address_from_public_key(verify_key)
      unless verify_key.is_a?(RbNaCl::VerifyKey)
        Kernel.raise SolanaError.new(SolanaError::ADDRESSES__INVALID_ED25519_PUBLIC_KEY)
      end

      Address.new(encode_address(verify_key.to_bytes))
    end

    # Given a Solana Address, returns the corresponding RbNaCl::VerifyKey.
    # Raises SolanaError if the address bytes are not a valid Ed25519 public key.
    #
    # Mirrors TypeScript's `getPublicKeyFromAddress(address: Address)`.
    sig { params(addr: Address).returns(T.untyped) }
    def get_public_key_from_address(addr)
      bytes = decode_address(addr)
      RbNaCl::VerifyKey.new(bytes)
    rescue RangeError, ScriptError => e
      Kernel.raise SolanaError.new(SolanaError::ADDRESSES__INVALID_ED25519_PUBLIC_KEY)
    end
  end
end
