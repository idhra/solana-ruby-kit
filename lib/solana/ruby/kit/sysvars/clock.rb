# typed: strict
# frozen_string_literal: true

require 'base64'

module Solana::Ruby::Kit
  module Sysvars
    # Clock sysvar — 40 bytes little-endian layout:
    #   slot(u64) + epoch_start_timestamp(i64) + epoch(u64) + leader_schedule_epoch(u64) + unix_timestamp(i64)
    class SysvarClock < T::Struct
      const :slot,                   Integer
      const :epoch_start_timestamp,  Integer   # Unix seconds (i64)
      const :epoch,                  Integer
      const :leader_schedule_epoch,  Integer
      const :unix_timestamp,         Integer   # Unix seconds (i64)
    end

    CLOCK_SIZE = T.let(40, Integer)

    extend self

    sig { params(rpc: Rpc::Client).returns(SysvarClock) }
    def fetch_sysvar_clock(rpc)
      res  = rpc.get_account_info(SYSVAR_CLOCK_ADDRESS, encoding: 'base64')
      data = _decode_account_data(res)

      unpacked = T.cast(T.unsafe(data).unpack('Q<q<Q<Q<q<'), T::Array[Integer])
      SysvarClock.new(
        slot:                  T.must(unpacked[0]),
        epoch_start_timestamp: T.must(unpacked[1]),
        epoch:                 T.must(unpacked[2]),
        leader_schedule_epoch: T.must(unpacked[3]),
        unix_timestamp:        T.must(unpacked[4])
      )
    end
  end
end
