# typed: strict
# frozen_string_literal: true

require 'timeout'

# Mirrors @solana/transaction-confirmation.
# Provides synchronous polling strategies that wait for a transaction to reach
# a desired commitment level.
module Solana::Ruby::Kit
  module TransactionConfirmation
    extend T::Sig

    extend self

    # Poll getSignatureStatuses until +signature+ reaches +commitment+ or
    # the blockheight/timeout deadline is exceeded.
    #
    # @param rpc          [Rpc::Client]
    # @param signature    [Keys::Signature, String]
    # @param commitment   [:processed, :confirmed, :finalized]
    # @param timeout_secs [Integer]
    # @param poll_interval [Float]
    # @return [Rpc::Api::SignatureStatus]
    # @raise [Timeout::Error] if the deadline is reached
    # @raise [Solana::Ruby::Kit::SolanaError] if the transaction failed
    sig do
      params(
        rpc:           Rpc::Client,
        signature:     T.any(Keys::Signature, String),
        commitment:    Symbol,
        timeout_secs:  Integer,
        poll_interval: Float
      ).returns(T.untyped) # Rpc::Api::SignatureStatus
    end
    def wait_for_confirmation(
      rpc,
      signature,
      commitment:    :confirmed,
      timeout_secs:  30,
      poll_interval: 0.5
    )
      sig_str    = signature.respond_to?(:value) ? T.cast(signature, Keys::Signature).value : signature.to_s
      commitment_order = %i[processed confirmed finalized]
      min_order  = commitment_order.index(commitment) || 1

      Timeout.timeout(timeout_secs) do
        Kernel.loop do
          res    = rpc.get_signature_statuses([sig_str], search_transaction_history: false)
          status = res.value.first
          next Kernel.sleep(poll_interval) if status.nil?

          err = status.respond_to?(:err) ? status.err : status[:err]
          Kernel.raise SolanaError.new(SolanaError::TRANSACTIONS__FAILED_TRANSACTION_PLAN, err: err.inspect) if err

          current_commitment = status.respond_to?(:confirmation_status) ? status.confirmation_status : status[:confirmation_status]
          current_order      = commitment_order.index(current_commitment) || 0

          return status if current_order >= min_order

          Kernel.sleep(poll_interval)
        end
      end
    end

    # Wait until the transaction is confirmed or the blockhash lifetime expires
    # (i.e. the current block height exceeds +last_valid_block_height+).
    sig do
      params(
        rpc:                    Rpc::Client,
        signature:              T.any(Keys::Signature, String),
        last_valid_block_height: Integer,
        commitment:             Symbol,
        poll_interval:          Float
      ).returns(T.untyped)
    end
    def wait_for_blockheight_lifetime(
      rpc,
      signature,
      last_valid_block_height:,
      commitment:    :confirmed,
      poll_interval: 0.5
    )
      sig_str = signature.respond_to?(:value) ? T.cast(signature, Keys::Signature).value : signature.to_s
      commitment_order = %i[processed confirmed finalized]
      min_order        = commitment_order.index(commitment) || 1

      Kernel.loop do
        # Check if blockheight has been exceeded
        current_height = rpc.get_block_height
        Kernel.raise Timeout::Error, 'Transaction lifetime expired (blockheight)' if current_height > last_valid_block_height

        res    = rpc.get_signature_statuses([sig_str], search_transaction_history: false)
        status = res.value.first
        next Kernel.sleep(poll_interval) if status.nil?

        err = status.respond_to?(:err) ? status.err : status[:err]
        Kernel.raise SolanaError.new(SolanaError::TRANSACTIONS__FAILED_TRANSACTION_PLAN, err: err.inspect) if err

        current_commitment = status.respond_to?(:confirmation_status) ? status.confirmation_status : status[:confirmation_status]
        current_order      = commitment_order.index(current_commitment) || 0

        return status if current_order >= min_order

        Kernel.sleep(poll_interval)
      end
    end

    # Wait for confirmation using a durable nonce strategy.
    # The transaction is considered expired once the nonce account's blockhash
    # changes (indicating the nonce was advanced by someone else or the TX landed).
    sig do
      params(
        rpc:           Rpc::Client,
        signature:     T.any(Keys::Signature, String),
        nonce_account: String,
        nonce:         String,
        commitment:    Symbol,
        timeout_secs:  Integer,
        poll_interval: Float
      ).returns(T.untyped)
    end
    def wait_for_nonce_invalidation(
      rpc,
      signature,
      nonce_account:,
      nonce:,
      commitment:    :confirmed,
      timeout_secs:  120,
      poll_interval: 1.0
    )
      sig_str          = signature.respond_to?(:value) ? T.cast(signature, Keys::Signature).value : signature.to_s
      commitment_order = %i[processed confirmed finalized]
      min_order        = commitment_order.index(commitment) || 1

      Timeout.timeout(timeout_secs) do
        Kernel.loop do
          # First check if transaction already confirmed
          res    = rpc.get_signature_statuses([sig_str], search_transaction_history: false)
          status = res.value.first
          unless status.nil?
            err = status.respond_to?(:err) ? status.err : status[:err]
            Kernel.raise SolanaError.new(SolanaError::TRANSACTIONS__FAILED_TRANSACTION_PLAN, err: err.inspect) if err

            current_commitment = status.respond_to?(:confirmation_status) ? status.confirmation_status : status[:confirmation_status]
            current_order      = commitment_order.index(current_commitment) || 0
            return status if current_order >= min_order
          end

          # Check if nonce has advanced (transaction expired without confirming)
          nonce_res = rpc.get_account_info(nonce_account, encoding: 'jsonParsed')
          current_nonce_hash = nonce_res.value&.respond_to?(:data) ? nonce_res.value.data&.dig('parsed', 'info', 'blockhash') : nil
          Kernel.raise Timeout::Error, 'Nonce advanced — transaction expired' if current_nonce_hash && current_nonce_hash != nonce

          Kernel.sleep(poll_interval)
        end
      end
    end
  end
end
