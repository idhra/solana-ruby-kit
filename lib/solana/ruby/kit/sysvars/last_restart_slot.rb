# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Sysvars
    # LastRestartSlot sysvar — 8 bytes: last_restart_slot(u64 LE)
    class SysvarLastRestartSlot < T::Struct
      const :last_restart_slot, Integer
    end

    extend self

    sig { params(rpc: Rpc::Client).returns(SysvarLastRestartSlot) }
    def fetch_sysvar_last_restart_slot(rpc)
      res  = rpc.get_account_info(SYSVAR_LAST_RESTART_SLOT_ADDRESS, encoding: 'base64')
      data = _decode_account_data(res)

      slot = data.unpack1('Q<')
      SysvarLastRestartSlot.new(last_restart_slot: slot)
    end
  end
end
