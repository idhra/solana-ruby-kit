# typed: strict
# frozen_string_literal: true

require_relative '../errors'
require_relative 'reactive_stream_store'

module Solana::Ruby::Kit
  module Subscribable
    extend T::Sig

    extend self

    # Adapts a ReactiveStreamStore into an Enumerator, so a *push*-based
    # reactive store can be driven by *pull*-based code that consumes it with
    # `#each`, `#next`, `#take`, or any other Enumerable method.
    #
    # The bridge only *observes* the store; it does not open or tear down the
    # connection. The caller owns the store's lifecycle. The bridge subscribes,
    # yields the store's current and subsequent values, and unsubscribes when
    # iteration ends — however it ends (exhaustion, error, `break`, or abort).
    # It does not reset the store; that is the caller's decision.
    #
    # This is the store-backed counterpart to AsyncIterable.from_publisher.
    # That helper turns a raw DataPublisher into an Enumerator and queues every
    # message so none are dropped. `bridge_store_to_async_iterable` instead sits
    # on top of a ReactiveStreamStore, so it reflects the store's
    # loading/loaded/error/retrying lifecycle — and, because a store only ever
    # holds the *latest* snapshot, it is latest-wins rather than fully buffered.
    #
    # On iteration it seeds from the store's current snapshot, then yields its
    # lifecycle:
    # - 'loaded'   → yields the value (the one already present when iteration
    #                begins, then each subsequent update), unless the optional
    #                +should_yield+ predicate rejects it. Latest-wins: if several
    #                notifications land between pulls, only the most recent
    #                unconsumed value is yielded.
    # - 'error'    → raises, so the consuming loop propagates it. Substitutes a
    #                SolanaError::SUBSCRIBABLE__STREAM_CLOSED_WITHOUT_ERROR
    #                sentinel when the store reports an error with a nil payload.
    #                An error takes precedence over a buffered value: if a loaded
    #                value is still pending when an error arrives, that value is
    #                dropped and the error propagates.
    # - 'loading' / 'retrying' → carry no new value and no error; nothing to yield.
    #
    # +signal+ follows the same convention as the rest of Subscribable: a lambda
    # called to test for abort, which *raises* once aborted. When it raises,
    # iteration ends cleanly (no error) — an abort is teardown, so the store's
    # incidental abort-driven error state is not surfaced. Because a Ruby
    # consumer parks in a blocking wait rather than on an event loop, the signal
    # is re-tested every +poll_interval+ seconds while parked; it is checked
    # immediately on every store change regardless. With no +signal+, the
    # enumerator parks indefinitely between values — a subscription never
    # completes on its own, so `break` out of the loop to stop.
    #
    # @param store [ReactiveStreamStore] a store to observe. Connect it yourself.
    # @param signal [Proc, nil] raises once aborted; ends iteration cleanly.
    # @param should_yield [Proc, nil] gate run against each loaded value before
    #   it is yielded. Return false to drop the value.
    # @param poll_interval [Float] seconds between signal re-tests while parked.
    # @return [Enumerator]
    #
    # @example
    #   store = Subscribable.create_reactive_store_from_data_publisher(
    #     publisher, data_channel: :slotNotification, error_channel: :error
    #   )
    #   Subscribable.bridge_store_to_async_iterable(store).each do |notification|
    #     puts "Latest slot: #{notification['slot']}"
    #   end
    #
    # Mirrors bridgeStoreToAsyncIterable from @solana/subscribable.
    sig do
      params(
        store:         ReactiveStreamStore,
        signal:        T.nilable(T.proc.void),
        should_yield:  T.nilable(T.proc.params(value: T.untyped).returns(T::Boolean)),
        poll_interval: Float
      ).returns(T::Enumerator[T.untyped])
    end
    def bridge_store_to_async_iterable(store, signal: nil, should_yield: nil, poll_interval: 0.05)
      Enumerator.new do |yielder|
        mutex = Mutex.new
        cond  = ConditionVariable.new
        # Latest-wins single-slot buffer. Both are one-element arrays used as
        # "present or nil" boxes so a legitimately-nil value is distinguishable
        # from "nothing buffered".
        latest  = T.let(nil, T.nilable(T::Array[T.untyped]))
        failure = T.let(nil, T.nilable(T::Array[T.untyped]))

        on_change = Kernel.lambda do
          state = store.get_unified_state
          case state.status
          when 'loaded'
            # Drop a value the gate rejects; park again rather than yielding it.
            next if should_yield && !should_yield.call(state.data)
            mutex.synchronize do
              latest = [state.data]
              cond.broadcast
            end
          when 'error'
            # A nil error would otherwise surface as a value-less success;
            # substitute a sentinel so the failure propagates.
            err = state.error || SolanaError.new(SolanaError::SUBSCRIBABLE__STREAM_CLOSED_WITHOUT_ERROR)
            mutex.synchronize do
              failure = [err]
              cond.broadcast
            end
          end
        end

        aborted = Kernel.lambda do
          next false if signal.nil?

          begin
            signal.call
            false
          rescue StandardError
            true
          end
        end

        unsubscribe = store.subscribe(&on_change)
        # Seed from the store's current snapshot: the caller may already have
        # connected (and a value or error may already be present) before
        # iteration began. The bridge never connects the store itself.
        on_change.call

        begin
          Kernel.loop do
            # Abort wins over everything: end cleanly without raising.
            break if aborted.call

            action  = T.let(:park, Symbol)
            payload = T.let(nil, T.untyped)

            mutex.synchronize do
              if failure
                action  = :raise
                payload = failure[0]
              elsif latest
                action  = :yield
                payload = latest[0]
                latest  = nil
              else
                cond.wait(mutex, signal ? poll_interval : nil)
              end
            end

            case action
            when :yield then yielder.yield(payload)
            when :raise then Kernel.raise(coerce_error(payload))
            end
          end
        ensure
          unsubscribe.call
        end
      end
    end

    # The store's error channel carries whatever the publisher emitted, which
    # need not be an Exception. Ruby can only raise exceptions, so wrap anything
    # else rather than losing the failure.
    sig { params(error: T.untyped).returns(Exception) }
    def coerce_error(error)
      case error
      when Exception then error
      when String    then RuntimeError.new(error)
      else                RuntimeError.new(error.inspect)
      end
    end
    private_class_method :coerce_error
  end
end
