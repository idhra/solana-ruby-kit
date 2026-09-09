# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Sysvars
    # Rent sysvar — 17 bytes:
    #   lamports_per_byte_year(u64) + exemption_threshold(f64) + burn_percent(u8)
    class SysvarRent < T::Struct
      const :lamports_per_byte_year, Integer
      const :exemption_threshold,    Float
      const :burn_percent,           Integer
    end

    extend self

    sig { params(rpc: Rpc::Client).returns(SysvarRent) }
    def fetch_sysvar_rent(rpc)
      res  = rpc.get_account_info(SYSVAR_RENT_ADDRESS, encoding: 'base64')
      data = _decode_account_data(res)

      unpacked = T.unsafe(data).unpack('Q<EC')
      SysvarRent.new(
        lamports_per_byte_year: unpacked[0],
        exemption_threshold:    unpacked[1],
        burn_percent:           unpacked[2]
      )
    end
  end
end
