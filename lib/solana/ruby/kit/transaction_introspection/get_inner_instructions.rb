# typed: strict
# frozen_string_literal: true

require_relative '../encoding/base58'
require_relative '../errors'
require_relative '../instructions/instruction'
require_relative 'types'

module Solana::Ruby::Kit
  module TransactionIntrospection
    extend T::Sig

    extend self

    # Returns the inner instructions in a transaction `meta` as
    # TracedInstructions.
    #
    # The RPC returns inner instructions in a different shape from the wire
    # format: indices reference the same flat account list as the outer
    # instructions, but `data` is a base58-encoded string. This decodes the
    # data, resolves the indices against the supplied AccountMeta list, and
    # tags each instruction with an `inner` trace.
    #
    # +meta+ is the raw (String-keyed) `meta` hash from any method that returns
    # transaction metadata without `jsonParsed` encoding — `getTransaction`,
    # `getTransactionsForAddress`, or `getBlock`. Returns an empty array if it
    # carries no `innerInstructions`.
    #
    # Raises if any `programIdIndex` or account index falls outside the
    # supplied `account_metas` list.
    #
    # Mirrors `getInnerInstructionsFromMeta()`.
    sig do
      params(
        meta:          T.nilable(T::Hash[String, T.untyped]),
        account_metas: T::Array[Instructions::AccountMeta]
      ).returns(T::Array[TracedInstruction])
    end
    def get_inner_instructions_from_meta(meta, account_metas)
      groups = meta && meta['innerInstructions']
      return [] unless groups

      result = T.let([], T::Array[TracedInstruction])

      groups.each do |group|
        outer_index = group['index']

        group['instructions'].each_with_index do |ix, inner_index|
          program_meta = account_metas[ix['programIdIndex']]
          if program_meta.nil?
            Kernel.raise SolanaError.new(
              SolanaError::TRANSACTIONS__FAILED_TO_DECOMPILE_INSTRUCTION_PROGRAM_ADDRESS_NOT_FOUND,
              { index: ix['programIdIndex'] }
            )
          end

          accounts = (ix['accounts'] || []).map do |i|
            account_meta = account_metas[i]
            if account_meta.nil?
              Kernel.raise SolanaError.new(
                SolanaError::TRANSACTION__FAILED_TO_DECOMPILE_INSTRUCTION_ACCOUNT_INDEX_OUT_OF_RANGE,
                { index: i }
              )
            end
            account_meta
          end

          data_b58 = ix['data']
          data     = data_b58.nil? || data_b58.empty? ? nil : Encoding::Base58.decode(data_b58)

          trace = { kind: :inner, outer_index: outer_index, inner_index: inner_index }
          trace[:stack_height] = ix['stackHeight'] unless ix['stackHeight'].nil?

          result << TracedInstruction.new(
            instruction: Instructions::Instruction.new(
              program_address: program_meta.address,
              accounts:        accounts.empty? ? nil : accounts,
              data:            data
            ),
            trace: trace
          )
        end
      end

      result
    end
  end
end
