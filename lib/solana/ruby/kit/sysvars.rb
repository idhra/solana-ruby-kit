# typed: strict
# frozen_string_literal: true

require 'base64'

# Mirrors @solana/sysvars.
# Provides addresses and fetch helpers for Solana sysvar accounts.

# Set up the module (extend T::Sig) before requiring sub-files that use `sig`.
module Solana::Ruby::Kit
  module Sysvars
    extend T::Sig

    extend self

    # Decode base64 account data from an RpcContextualValue returned by
    # get_account_info(encoding: 'base64').
    sig { params(res: RpcTypes::RpcContextualValue).returns(String) }
    def _decode_account_data(res)
      info = res.value
      Kernel.raise ArgumentError, 'Account not found' if info.nil?

      raw = T.cast(info, RpcTypes::AccountInfoWithBase64Data)
      Base64.decode64(raw.data.first.to_s).b
    end
  end
end

require_relative 'sysvars/addresses'
require_relative 'sysvars/clock'
require_relative 'sysvars/rent'
require_relative 'sysvars/epoch_schedule'
require_relative 'sysvars/last_restart_slot'
