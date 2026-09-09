# typed: strict
# frozen_string_literal: true

require 'base64'
require_relative '../addresses'
require_relative '../encoding/base58'
require_relative '../errors'
require_relative '../transactions/transaction'
require_relative '../wallet_standard'
require_relative 'compiled_transaction_message'
require_relative 'loaded_addresses'

module Solana::Ruby::Kit
  module TransactionIntrospection
    extend T::Sig

    # The result of decoding a confirmed-transaction RPC response: the
    # CompiledTransactionMessage, the loaded ALT addresses pulled from `meta`
    # (if any), and — for `'base64'` and `'base58'` responses — the
    # re-encodable wire-format Transactions::Transaction.
    #
    # `transaction` is nil for `encoding: 'json'` responses: the server has
    # already decompiled the wire format, so there are no message bytes to
    # round-trip. Fetch with `encoding: 'base64'` if you need a re-encodable
    # Transaction.
    #
    # Mirrors `DecodedRpcTransaction` from @solana/transaction-introspection.
    class DecodedRpcTransaction < T::Struct
      const :compiled_message, CompiledTransactionMessage
      const :loaded_addresses, LoadedAddresses
      const :transaction,      T.nilable(Transactions::Transaction)
    end

    extend self

    # Decodes a confirmed-transaction RPC response (any of `encoding: 'base64'`,
    # `'base58'`, or `'json'`) into a CompiledTransactionMessage plus, for
    # `'base64'` and `'base58'`, a re-encodable Transactions::Transaction.
    # The JSON path does not produce a Transaction: the server has already
    # decompiled the wire format, so there are no message bytes to carry.
    #
    # +rpc_tx+ is a raw (String-keyed) JSON hash. Only the `transaction` /
    # `meta` / `version` envelope is read — not a method-specific response
    # shape — so results from any method that returns confirmed transactions in
    # these encodings work, and extra fields (`slot`, `blockTime`,
    # `transactionIndex`, …) are ignored:
    #
    #   # getTransaction — a single response hash
    #   rpc_tx = rpc.get_transaction(signature, encoding: 'base64')
    #   TransactionIntrospection.decode_transaction_from_rpc_response(rpc_tx)
    #
    #   # getTransactionsForAddress — one hash per element of `data`
    #   page = rpc.get_transactions_for_address(
    #     address, transaction_details: :full, encoding: 'base64',
    #     max_supported_transaction_version: 0
    #   )
    #   page.data.map { |tx| TransactionIntrospection.decode_transaction_from_rpc_response(tx) }
    #
    # `'jsonParsed'` is not supported — its instructions arrive pre-parsed by
    # the server and lack raw bytes, so they cannot be round-tripped. Passing
    # a `'jsonParsed'` response raises
    # SolanaError::TRANSACTION_INTROSPECTION__CANNOT_DECODE_JSON_PARSED_TRANSACTION;
    # any other unrecognized input raises
    # SolanaError::TRANSACTION_INTROSPECTION__UNRECOGNIZED_GET_TRANSACTION_RESPONSE.
    #
    # A transaction version this decoder cannot handle (anything but legacy
    # or v0) raises SolanaError::TRANSACTION__VERSION_NUMBER_NOT_SUPPORTED —
    # Ruby's wire compiler does not produce v1 transactions either, so there
    # is nothing to decompile for that version yet.
    #
    # Mirrors `decodeTransactionFromRpcResponse()`.
    sig { params(rpc_tx: T::Hash[String, T.untyped]).returns(DecodedRpcTransaction) }
    def decode_transaction_from_rpc_response(rpc_tx)
      tx_field = rpc_tx['transaction']

      if tx_field.is_a?(Array)
        encoding = tx_field[1]
        return decode_from_base64(rpc_tx) if encoding == 'base64'
        return decode_from_base58(rpc_tx) if encoding == 'base58'
      elsif tx_field.is_a?(Hash) && tx_field['message'].is_a?(Hash)
        # An `encoding: 'json'` message carries the compiled-message `header`
        # (signer/readonly counts). A `jsonParsed` message has no `header` —
        # the server has already resolved account roles onto `accountKeys` —
        # so checking for it distinguishes the two encodings.
        return decode_from_json(rpc_tx) if tx_field['message']['header'].is_a?(Hash)

        Kernel.raise SolanaError.new(SolanaError::TRANSACTION_INTROSPECTION__CANNOT_DECODE_JSON_PARSED_TRANSACTION)
      end

      Kernel.raise SolanaError.new(SolanaError::TRANSACTION_INTROSPECTION__UNRECOGNIZED_GET_TRANSACTION_RESPONSE)
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    sig { params(meta: T.untyped).returns(LoadedAddresses) }
    def get_loaded_addresses(meta)
      loaded = meta.is_a?(Hash) ? meta['loadedAddresses'] : nil
      return EMPTY_LOADED_ADDRESSES unless loaded.is_a?(Hash)

      LoadedAddresses.new(
        readonly: (loaded['readonly'] || []).map { |a| Addresses.address(a) },
        writable: (loaded['writable'] || []).map { |a| Addresses.address(a) }
      )
    end
    private_class_method :get_loaded_addresses

    sig { params(rpc_tx: T::Hash[String, T.untyped]).returns(DecodedRpcTransaction) }
    def decode_from_base64(rpc_tx)
      b64         = rpc_tx['transaction'][0]
      transaction = WalletStandard.decode_wire_transaction(b64)
      DecodedRpcTransaction.new(
        compiled_message: decode_compiled_transaction_message(transaction.message_bytes),
        loaded_addresses: get_loaded_addresses(rpc_tx['meta']),
        transaction:      transaction
      )
    end
    private_class_method :decode_from_base64

    sig { params(rpc_tx: T::Hash[String, T.untyped]).returns(DecodedRpcTransaction) }
    def decode_from_base58(rpc_tx)
      b58         = rpc_tx['transaction'][0]
      transaction = WalletStandard.decode_wire_transaction(Encoding::Base58.decode(b58))
      DecodedRpcTransaction.new(
        compiled_message: decode_compiled_transaction_message(transaction.message_bytes),
        loaded_addresses: get_loaded_addresses(rpc_tx['meta']),
        transaction:      transaction
      )
    end
    private_class_method :decode_from_base58

    sig { params(rpc_tx: T::Hash[String, T.untyped]).returns(DecodedRpcTransaction) }
    def decode_from_json(rpc_tx)
      message = rpc_tx['transaction']['message']

      header = CompiledTransactionMessageHeader.new(
        num_signer_accounts:              message['header']['numRequiredSignatures'],
        num_readonly_signer_accounts:      message['header']['numReadonlySignedAccounts'],
        num_readonly_non_signer_accounts:  message['header']['numReadonlyUnsignedAccounts']
      )

      instructions = message['instructions'].map do |ix|
        data_b58 = ix['data']
        CompiledInstruction.new(
          program_address_index: ix['programIdIndex'],
          account_indices:       ix['accounts'] || [],
          data:                  data_b58.nil? || data_b58.empty? ? ''.b : Encoding::Base58.decode(data_b58)
        )
      end

      # The envelope only carries `version` when `maxSupportedTransactionVersion`
      # was set on the request; otherwise the response is necessarily legacy.
      # A `version` key that is present but null counts as absent — some methods
      # include the key unconditionally. Ruby's `||` is safe here where
      # TypeScript needs `??`: 0 (v0) is truthy in Ruby, so a real v0 survives.
      version = rpc_tx['version'] || :legacy
      version = :legacy if version == 'legacy'

      compiled_message = CompiledTransactionMessage.new(
        version:         version,
        header:          header,
        static_accounts: message['accountKeys'].map { |a| Addresses.address(a) },
        instructions:    instructions,
        # For durable-nonce transactions, `recentBlockhash` is the nonce value, not a
        # blockhash — either way it is the message's lifetime token.
        lifetime_token:  message['recentBlockhash']
      )

      DecodedRpcTransaction.new(
        compiled_message: compiled_message,
        loaded_addresses: get_loaded_addresses(rpc_tx['meta']),
        transaction:      nil
      )
    end
    private_class_method :decode_from_json
  end
end
