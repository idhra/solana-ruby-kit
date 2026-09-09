# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module RpcParsedTypes
    extend T::Sig
    AddressLookupTableData = T.let(
      Struct.new(:deactivation_slot, :last_extended_slot, :addresses, keyword_init: true),
      T.untyped
    )

    ParsedAddressLookupTable = T.let(
      Struct.new(:program, :parsed, :space, keyword_init: true),
      T.untyped
    )

    extend self

    sig { params(raw: T::Hash[String, T.untyped]).returns(T.untyped) }
    def parse_address_lookup_table(raw)
      info = raw.dig('parsed', 'info') || {}
      ParsedAddressLookupTable.new(
        program: raw['program'],
        space:   raw['space'],
        parsed:  AddressLookupTableData.new(
          deactivation_slot:  info['deactivationSlot'] ? Kernel.Integer(info['deactivationSlot']) : nil,
          last_extended_slot: info['lastExtendedSlot']  ? Kernel.Integer(info['lastExtendedSlot']) : nil,
          addresses:          Kernel.Array(info['addresses'])
        )
      )
    end
  end
end
