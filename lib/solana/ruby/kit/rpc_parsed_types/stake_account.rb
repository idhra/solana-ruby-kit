# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module RpcParsedTypes
    extend T::Sig
    StakeDelegation = T.let(
      Struct.new(:stake, :voter, :activation_epoch, :deactivation_epoch,
                 :warmup_cooldown_rate, keyword_init: true),
      T.untyped
    )

    StakeAccountData = T.let(
      Struct.new(:type, :stake, :meta, keyword_init: true),
      T.untyped
    )

    ParsedStakeAccount = T.let(
      Struct.new(:program, :parsed, :space, keyword_init: true),
      T.untyped
    )

    extend self

    sig { params(raw: T::Hash[String, T.untyped]).returns(T.untyped) }
    def parse_stake_account(raw)
      parsed = raw['parsed'] || {}
      info   = parsed['info'] || {}
      stake  = info['stake'] || {}
      deleg  = stake.dig('delegation') || {}

      delegation = StakeDelegation.new(
        stake:               deleg['stake'] ? Kernel.Integer(deleg['stake']) : nil,
        voter:               deleg['voter'],
        activation_epoch:    deleg['activationEpoch'] ? Kernel.Integer(deleg['activationEpoch']) : nil,
        deactivation_epoch:  deleg['deactivationEpoch'] ? Kernel.Integer(deleg['deactivationEpoch']) : nil,
        warmup_cooldown_rate: deleg['warmupCooldownRate']&.to_f
      )

      ParsedStakeAccount.new(
        program: raw['program'],
        space:   raw['space'],
        parsed:  StakeAccountData.new(
          type:  parsed['type'],
          stake: delegation,
          meta:  info['meta']
        )
      )
    end
  end
end
