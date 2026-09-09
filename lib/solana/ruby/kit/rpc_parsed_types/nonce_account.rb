# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module RpcParsedTypes
    extend T::Sig
    NonceAccountData = T.let(
      Struct.new(:authority, :blockhash, :fee_calculator, keyword_init: true),
      T.untyped
    )

    ParsedNonceAccount = T.let(
      Struct.new(:program, :parsed, :space, keyword_init: true),
      T.untyped
    )

    extend self

    sig { params(raw: T::Hash[String, T.untyped]).returns(T.untyped) }
    def parse_nonce_account(raw)
      info = raw.dig('parsed', 'info') || {}
      ParsedNonceAccount.new(
        program: raw['program'],
        space:   raw['space'],
        parsed:  NonceAccountData.new(
          authority:      info['authority'],
          blockhash:      info['blockhash'],
          fee_calculator: info['feeCalculator']
        )
      )
    end
  end
end
