# typed: strict
# frozen_string_literal: true

require_relative 'compiled_transaction_message'
require_relative 'get_inner_instructions'
require_relative 'get_instructions'
require_relative 'loaded_addresses'
require_relative 'types'

module Solana::Ruby::Kit
  module TransactionIntrospection
    extend T::Sig

    extend self

    # Returns every instruction in a confirmed transaction as
    # TracedInstructions, in the order an explorer displays them: each outer
    # instruction followed immediately by the inner instructions its CPIs
    # produced.
    #
    # If +meta+ is nil, only outer instructions are returned. If
    # +loaded_addresses+ is nil, only static accounts are used to resolve
    # indices — pass the `loadedAddresses` from a `getTransaction` response's
    # `meta` for v0 transactions that load accounts from address lookup tables.
    #
    # Mirrors `walkInstructions({ compiledMessage, loadedAddresses, meta })`.
    sig do
      params(
        compiled_message: CompiledTransactionMessage,
        loaded_addresses: T.nilable(LoadedAddresses),
        meta:             T.nilable(T::Hash[String, T.untyped])
      ).returns(T::Array[TracedInstruction])
    end
    def walk_instructions(compiled_message:, loaded_addresses: nil, meta: nil)
      account_metas      = get_account_metas_from_compiled_transaction_message(compiled_message, loaded_addresses)
      outer_instructions = get_instructions_from_compiled_transaction_message_with_metas(compiled_message, account_metas)

      inner_by_outer_index = T.let({}, T::Hash[Integer, T::Array[TracedInstruction]])
      if meta
        get_inner_instructions_from_meta(meta, account_metas).each do |inner|
          outer_index = inner.trace.fetch(:outer_index)
          (inner_by_outer_index[outer_index] ||= []) << inner
        end
      end

      result = T.let([], T::Array[TracedInstruction])
      outer_instructions.each_with_index do |instruction, index|
        result << TracedInstruction.new(instruction: instruction, trace: { kind: :outer, index: index })
        group = inner_by_outer_index.delete(index)
        result.concat(group) if group
      end
      # Inner groups whose index matches no outer instruction can only come
      # from malformed input (e.g. `meta` paired with the wrong message).
      # Append them rather than dropping them so no instruction is ever lost.
      inner_by_outer_index.each_value { |group| result.concat(group) }

      result
    end
  end
end
