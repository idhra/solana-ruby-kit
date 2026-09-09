# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module RpcParsedTypes
    extend T::Sig
    # Parsed SPL Token amount.
    TokenAmount = T.let(
      Struct.new(:amount, :decimals, :ui_amount, :ui_amount_string, keyword_init: true),
      T.untyped
    )

    # Parsed SPL Token account data (inside jsonParsed account info).
    TokenAccountInfo = T.let(
      Struct.new(:is_native, :mint, :owner, :state, :token_amount, keyword_init: true),
      T.untyped
    )

    # Full parsed token account wrapper.
    ParsedTokenAccount = T.let(
      Struct.new(:program, :parsed, :space, keyword_init: true),
      T.untyped
    )

    extend self

    sig { params(raw: T::Hash[String, T.untyped]).returns(T.untyped) }
    def parse_token_account(raw)
      info_raw = raw.dig('parsed', 'info') || {}
      ta_raw   = info_raw['tokenAmount'] || {}

      info = TokenAccountInfo.new(
        is_native:    info_raw['isNative'],
        mint:         info_raw['mint'],
        owner:        info_raw['owner'],
        state:        info_raw['state'],
        token_amount: TokenAmount.new(
          amount:           ta_raw['amount'],
          decimals:         Kernel.Integer(ta_raw.fetch('decimals', 0)),
          ui_amount:        ta_raw['uiAmount'],
          ui_amount_string: ta_raw['uiAmountString']
        )
      )

      ParsedTokenAccount.new(
        program: raw['program'],
        parsed:  info,
        space:   raw['space']
      )
    end
  end
end
