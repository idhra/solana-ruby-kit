# typed: strict
# frozen_string_literal: true

require 'base64'
require_relative 'errors'
require_relative 'functional'
require_relative 'transaction_messages'
require_relative 'transaction_messages/compute_budget'
require_relative 'transactions'

module Solana::Ruby::Kit
  # Utilities for estimating and setting transaction resource limits (compute units and
  # loaded accounts data size) via simulation.
  #
  # Mirrors `estimateResourceLimitsFactory`, `estimateAndSetResourceLimitsFactory`,
  # and `fillTransactionMessageProvisoryResourceLimits` from @solana/kit.
  module ResourceLimitEstimation
    extend T::Sig

    PROVISORY_LIMIT = T.let(0, Integer)

    extend self

    # Returns a callable that estimates the resource limits required by a transaction message
    # by simulating it with maximum limits set, then reading back the actual consumption.
    #
    # The returned callable accepts a TransactionMessage and optional keyword args:
    #   commitment:        Symbol (nil uses RPC default)
    #   min_context_slot:  Integer
    #
    # Returns a Hash with:
    #   :compute_unit_limit              Integer (always present)
    #   :loaded_accounts_data_size_limit Integer (present when the RPC returns it)
    #
    # Raises SolanaError with TRANSACTION__FAILED_TO_ESTIMATE_LOADED_ACCOUNTS_DATA_SIZE_LIMIT
    # if the message is version 1 but the RPC does not return loadedAccountsDataSize.
    # Raises SolanaError with TRANSACTION__FAILED_WHEN_SIMULATING_TO_ESTIMATE_RESOURCE_LIMITS
    # if the simulated transaction itself fails.
    # Raises SolanaError with TRANSACTION__FAILED_TO_ESTIMATE_COMPUTE_LIMIT for any other error.
    #
    # Mirrors `estimateResourceLimitsFactory({ rpc })` from @solana/kit.
    sig { params(rpc: T.untyped).returns(T.untyped) }
    def estimate_resource_limits_factory(rpc:)
      ->(transaction_message, commitment: nil, min_context_slot: nil) do
        replace_recent_blockhash = !TransactionMessages.durable_nonce_lifetime?(transaction_message)
        is_v1 = transaction_message.version == 1

        tx_for_sim = Functional.pipe(
          transaction_message,
          ->(m) { TransactionMessages.set_transaction_message_compute_unit_limit(TransactionMessages::MAX_COMPUTE_UNIT_LIMIT, m) },
          ->(m) { is_v1 ? TransactionMessages.set_transaction_message_loaded_accounts_data_size_limit(TransactionMessages::MAX_LOADED_ACCOUNTS_DATA_SIZE_LIMIT, m) : m }
        )

        transaction = Transactions.compile_transaction_message(tx_for_sim)
        wire_bytes  = Transactions.wire_encode_transaction(transaction)
        encoded     = Base64.strict_encode64(wire_bytes)

        sim_opts = { replace_recent_blockhash: replace_recent_blockhash }
        sim_opts[:commitment]       = commitment       if commitment
        sim_opts[:min_context_slot] = min_context_slot if min_context_slot

        begin
          sim_value = rpc.simulate_transaction(encoded, **sim_opts).value

          transaction_error         = sim_value['err']
          units_consumed            = sim_value['unitsConsumed']
          loaded_accounts_data_size = sim_value['loadedAccountsDataSize']

          if is_v1 && loaded_accounts_data_size.nil?
            Kernel.raise SolanaError.new(SolanaError::TRANSACTION__FAILED_TO_ESTIMATE_LOADED_ACCOUNTS_DATA_SIZE_LIMIT)
          end

          if transaction_error
            Kernel.raise SolanaError.new(
              SolanaError::TRANSACTION__FAILED_WHEN_SIMULATING_TO_ESTIMATE_RESOURCE_LIMITS
            )
          end

          compute_unit_limit = [units_consumed.to_i, 4_294_967_295].min

          estimate = { compute_unit_limit: compute_unit_limit }
          estimate[:loaded_accounts_data_size_limit] = loaded_accounts_data_size.to_i unless loaded_accounts_data_size.nil?
          estimate
        rescue SolanaError => e
          known = [
            SolanaError::TRANSACTION__FAILED_WHEN_SIMULATING_TO_ESTIMATE_RESOURCE_LIMITS,
            SolanaError::TRANSACTION__FAILED_TO_ESTIMATE_LOADED_ACCOUNTS_DATA_SIZE_LIMIT
          ]
          Kernel.raise if known.include?(e.code)
          Kernel.raise SolanaError.new(SolanaError::TRANSACTION__FAILED_TO_ESTIMATE_COMPUTE_LIMIT)
        rescue StandardError
          Kernel.raise SolanaError.new(SolanaError::TRANSACTION__FAILED_TO_ESTIMATE_COMPUTE_LIMIT)
        end
      end
    end

    # Returns a callable that estimates resource limits for a transaction message and
    # sets them on the message, unless they are already explicitly configured.
    #
    # A limit of 0 (the provisory value) or the maximum (1,400,000 for CU) is treated
    # as non-explicit and will be replaced with the estimate.
    #
    # Mirrors `estimateAndSetResourceLimitsFactory(estimator)` from @solana/kit.
    sig { params(estimate_resource_limits: T.untyped).returns(T.untyped) }
    def estimate_and_set_resource_limits_factory(estimate_resource_limits)
      ->(transaction_message, **opts) do
        existing_cu = TransactionMessages.get_transaction_message_compute_unit_limit(transaction_message)
        cu_explicit = !existing_cu.nil? &&
                      existing_cu != PROVISORY_LIMIT &&
                      existing_cu != TransactionMessages::MAX_COMPUTE_UNIT_LIMIT

        is_v1 = transaction_message.version == 1
        loaded_explicit = true
        if is_v1
          existing_loaded = TransactionMessages.get_transaction_message_loaded_accounts_data_size_limit(transaction_message)
          loaded_explicit = !existing_loaded.nil? && existing_loaded != PROVISORY_LIMIT
        end

        return transaction_message if cu_explicit && loaded_explicit

        estimate = estimate_resource_limits.call(transaction_message, **opts)

        result = transaction_message
        unless cu_explicit
          result = TransactionMessages.set_transaction_message_compute_unit_limit(estimate[:compute_unit_limit], result)
        end
        if is_v1 && !loaded_explicit && estimate.key?(:loaded_accounts_data_size_limit)
          result = TransactionMessages.set_transaction_message_loaded_accounts_data_size_limit(estimate[:loaded_accounts_data_size_limit], result)
        end
        result
      end
    end

    # Sets compute unit limit (and, for V1, loaded accounts data size limit) to the
    # provisory value of 0 on the message, unless a limit is already present.
    #
    # Use this during message construction to reserve space for limits that will later
    # be replaced with actual estimates via `estimate_and_set_resource_limits_factory`.
    #
    # Mirrors `fillTransactionMessageProvisoryResourceLimits` from @solana/kit.
    sig do
      params(message: TransactionMessages::TransactionMessage)
        .returns(TransactionMessages::TransactionMessage)
    end
    def fill_transaction_message_provisory_resource_limits(message)
      result = message
      if TransactionMessages.get_transaction_message_compute_unit_limit(result).nil?
        result = TransactionMessages.set_transaction_message_compute_unit_limit(PROVISORY_LIMIT, result)
      end
      if result.version == 1 && TransactionMessages.get_transaction_message_loaded_accounts_data_size_limit(result).nil?
        result = TransactionMessages.set_transaction_message_loaded_accounts_data_size_limit(PROVISORY_LIMIT, result)
      end
      result
    end
  end
end
