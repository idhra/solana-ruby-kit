# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Sysvars
    # EpochSchedule sysvar — 33 bytes:
    #   slots_per_epoch(u64) + leader_schedule_slot_offset(u64)
    #   + warmup(bool/u8) + first_normal_epoch(u64) + first_normal_slot(u64)
    class SysvarEpochSchedule < T::Struct
      const :slots_per_epoch,              Integer
      const :leader_schedule_slot_offset,  Integer
      const :warmup,                       T::Boolean
      const :first_normal_epoch,           Integer
      const :first_normal_slot,            Integer
    end

    extend self

    sig { params(rpc: Rpc::Client).returns(SysvarEpochSchedule) }
    def fetch_sysvar_epoch_schedule(rpc)
      res  = rpc.get_account_info(SYSVAR_EPOCH_SCHEDULE_ADDRESS, encoding: 'base64')
      data = _decode_account_data(res)

      unpacked = T.unsafe(data).unpack('Q<Q<CQ<Q<')
      SysvarEpochSchedule.new(
        slots_per_epoch:             unpacked[0],
        leader_schedule_slot_offset: unpacked[1],
        warmup:                      unpacked[2] == 1,
        first_normal_epoch:          unpacked[3],
        first_normal_slot:           unpacked[4]
      )
    end
  end
end
