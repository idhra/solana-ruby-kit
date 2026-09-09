# typed: strict
# frozen_string_literal: true

require_relative '../errors'
require_relative 'data_publisher'

module Solana::Ruby::Kit
  module Subscribable
    extend T::Sig

    # Lifecycle snapshot of a ReactiveStreamStore — a single frozen value
    # capturing status, last-known data, and any error.
    #
    # status values:
    #   'loading'  — waiting for first value; data is nil
    #   'loaded'   — value has arrived, no active error
    #   'error'    — stream failed; data is last known value (may be nil)
    #   'retrying' — retry in progress after error; data preserved
    #
    # Mirrors TypeScript's ReactiveState<T>.
    class ReactiveState
      extend T::Sig

      sig { returns(String) }
      attr_reader :status

      sig { returns(T.untyped) }
      attr_reader :data

      sig { returns(T.untyped) }
      attr_reader :error

      sig { params(status: String, data: T.untyped, error: T.untyped).void }
      def initialize(status:, data: nil, error: nil)
        @status = T.let(status, String)
        @data   = T.let(data,   T.untyped)
        @error  = T.let(error,  T.untyped)
        freeze
      end

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        other.is_a?(ReactiveState) &&
          @status == other.status &&
          @data.equal?(other.data) &&
          @error.equal?(other.error)
      end
    end

    REACTIVE_LOADING_STATE = T.let(
      ReactiveState.new(status: 'loading').freeze,
      ReactiveState
    )

    # Thread-safe store that tracks the latest value published to a data channel
    # and notifies subscribers on every state change.
    #
    # Compatible with any observer pattern that expects a
    #   { subscribe, get_unified_state } contract.
    #
    # Mirrors TypeScript's ReactiveStreamStore<T>.
    class ReactiveStreamStore
      extend T::Sig

      sig { void }
      def initialize
        @state       = T.let(REACTIVE_LOADING_STATE, ReactiveState)
        @subscribers = T.let([], T::Array[T.proc.void])
        @mutex       = T.let(Mutex.new, Mutex)
      end

      # Returns the current lifecycle snapshot.
      sig { returns(ReactiveState) }
      def get_unified_state
        @mutex.synchronize { @state }
      end

      # Returns the most recent data value, or nil if no value has arrived yet.
      # @deprecated Use get_unified_state instead.
      sig { returns(T.untyped) }
      def get_state
        @mutex.synchronize { @state.data }
      end

      # Returns the current error, or nil if no error has occurred.
      # @deprecated Use get_unified_state instead.
      sig { returns(T.untyped) }
      def get_error
        @mutex.synchronize { @state.error }
      end

      # Re-opens the stream after an error. Raises RETRY_NOT_SUPPORTED on
      # DataPublisher-backed stores — use create_reactive_store_from_data_publisher_factory
      # for a retryable store.
      sig { void }
      def retry
        Kernel.raise SolanaError.new(SolanaError::SUBSCRIBABLE__RETRY_NOT_SUPPORTED)
      end

      # Registers a callback invoked on every state change.
      # Returns an unsubscribe lambda.
      sig { params(callback: T.proc.void).returns(T.proc.void) }
      def subscribe(&callback)
        @mutex.synchronize { @subscribers << callback }
        lambda { @mutex.synchronize { @subscribers.delete(callback) } }
      end

      # Internal: transition state and notify all subscribers.
      sig { params(new_state: ReactiveState).void }
      def _set_state(new_state)
        subs = T.let(nil, T.nilable(T::Array[T.proc.void]))
        @mutex.synchronize do
          return if @state.equal?(new_state)
          @state = new_state
          subs = @subscribers.dup
        end
        subs&.each(&:call)
      end
    end

    # Deprecated alias — use ReactiveStreamStore.
    ReactiveStore = ReactiveStreamStore

    # A ReactiveStreamStore that supports retry() by re-invoking a factory proc
    # to get a fresh DataPublisher on each connection attempt.
    # Mirrors TypeScript's createReactiveStoreFromDataPublisherFactory result.
    class RetryableReactiveStreamStore < ReactiveStreamStore
      extend T::Sig

      sig do
        params(
          data_channel:     T.untyped,
          error_channel:    T.untyped,
          create_publisher: T.proc.returns(DataPublisher),
          signal:           T.nilable(T.proc.void)
        ).void
      end
      def initialize(data_channel:, error_channel:, create_publisher:, signal: nil)
        super()
        @data_channel     = T.let(data_channel,     T.untyped)
        @error_channel    = T.let(error_channel,    T.untyped)
        @outer_signal     = T.let(signal,            T.nilable(T.proc.void))
        @create_publisher = T.let(create_publisher,  T.proc.returns(DataPublisher))
        @stopped          = T.let(false,             T::Boolean)
        # Per-connection active flag shared with subscriber lambdas via closure.
        @conn_active      = T.let([false],            T::Array[T::Boolean])
        _connect
      end

      sig { override.void }
      def retry
        stopped = @mutex.synchronize { @stopped }
        return if stopped
        return unless get_unified_state.status == 'error'

        stale_data = get_unified_state.data
        # Deactivate old connection's subscribers
        @mutex.synchronize { @conn_active[0] = false }
        _set_state(ReactiveState.new(status: 'retrying', data: stale_data))
        _connect
      end

      private

      sig { void }
      def _connect
        return if @mutex.synchronize { @stopped }

        # Fresh active flag for this connection window
        active = T.let([true], T::Array[T::Boolean])
        @mutex.synchronize { @conn_active = active }

        # inner_signal fires (raises) once this connection is superseded or errors out,
        # which causes DataPublisher to prune those subscribers automatically.
        inner_signal = lambda do
          @outer_signal&.call
          Kernel.raise 'connection_inactive' unless active[0]
        end

        begin
          publisher = @create_publisher.call
        rescue => e
          active[0] = false
          stale_data = get_unified_state.data
          _set_state(ReactiveState.new(status: 'error', data: stale_data, error: e))
          return
        end

        publisher.on(@data_channel, signal: inner_signal) do |data|
          _set_state(ReactiveState.new(status: 'loaded', data: data))
        end

        publisher.on(@error_channel, signal: inner_signal) do |err|
          next unless active[0] && get_unified_state.status != 'error'
          active[0] = false
          last_data = get_unified_state.data
          _set_state(ReactiveState.new(status: 'error', data: last_data, error: err))
        end
      end
    end

    extend self

    # Creates a ReactiveStreamStore backed by a ready-made DataPublisher.
    # retry() is not supported — see create_reactive_store_from_data_publisher_factory.
    #
    # Mirrors TypeScript's createReactiveStoreFromDataPublisher (deprecated in TS).
    sig do
      params(
        publisher:     DataPublisher,
        data_channel:  T.untyped,
        error_channel: T.untyped,
        signal:        T.nilable(T.proc.void)
      ).returns(ReactiveStreamStore)
    end
    def create_reactive_store_from_data_publisher(publisher, data_channel:, error_channel:, signal: nil)
      store = ReactiveStreamStore.new

      publisher.on(data_channel, signal: signal) do |data|
        store._set_state(ReactiveState.new(status: 'loaded', data: data))
      end

      publisher.on(error_channel, signal: signal) do |err|
        unified = store.get_unified_state
        next if unified.status == 'error'
        store._set_state(ReactiveState.new(status: 'error', data: unified.data, error: err))
      end

      store
    end

    # Creates a retryable ReactiveStreamStore from a DataPublisher factory proc.
    # The factory is called once immediately and again on each retry().
    #
    # Mirrors TypeScript's createReactiveStoreFromDataPublisherFactory.
    sig do
      params(
        data_channel:  T.untyped,
        error_channel: T.untyped,
        signal:        T.nilable(T.proc.void),
        blk:           T.proc.returns(DataPublisher)
      ).returns(ReactiveStreamStore)
    end
    def create_reactive_store_from_data_publisher_factory(
      data_channel:, error_channel:, signal: nil, &blk
    )
      RetryableReactiveStreamStore.new(
        data_channel:     data_channel,
        error_channel:    error_channel,
        create_publisher: T.let(blk, T.proc.returns(DataPublisher)),
        signal:           signal
      )
    end
  end
end
