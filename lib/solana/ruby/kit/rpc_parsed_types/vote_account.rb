# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module RpcParsedTypes
    extend T::Sig
    VoteState = T.let(
      Struct.new(:node, :authorized_voter, :authorized_withdrawer, :commission,
                 :votes, :root_slot, :epoch_credits, keyword_init: true),
      T.untyped
    )

    ParsedVoteAccount = T.let(
      Struct.new(:program, :parsed, :space, keyword_init: true),
      T.untyped
    )

    extend self

    sig { params(raw: T::Hash[String, T.untyped]).returns(T.untyped) }
    def parse_vote_account(raw)
      info = raw.dig('parsed', 'info') || {}
      ParsedVoteAccount.new(
        program: raw['program'],
        space:   raw['space'],
        parsed:  VoteState.new(
          node:                  info['nodePubkey'],
          authorized_voter:      info['authorizedVoters'],
          authorized_withdrawer: info['authorizedWithdrawer'],
          commission:            info['commission'] ? Kernel.Integer(info['commission']) : nil,
          votes:                 info['votes'],
          root_slot:             info['rootSlot'] ? Kernel.Integer(info['rootSlot']) : nil,
          epoch_credits:         info['epochCredits']
        )
      )
    end
  end
end
