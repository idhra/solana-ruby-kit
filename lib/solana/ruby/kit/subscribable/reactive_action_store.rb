# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Subscribable
    extend T::Sig

    # Lifecycle status of a ReactiveActionStore.
    # Mirrors TypeScript's ReactiveActionStatus.
    ReactiveActionStatus = T.type_alias { String } # 'idle' | 'running' | 'success' | 'error'

    # Lifecycle snapshot of a ReactiveActionStore.
    # `data` persists across running/error states so callers can render stale
    # content while a retry is in flight; only reset() clears it.
    #
    # Mirrors TypeScript's ReactiveActionState<TResult>.
    class ReactiveActionState
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
        other.is_a?(ReactiveActionState) &&
          @status == other.status &&
          @data.equal?(other.data) &&
          @error.equal?(other.error)
      end
    end

    REACTIVE_ACTION_IDLE_STATE = T.let(
      ReactiveActionState.new(status: 'idle').freeze,
      ReactiveActionState
    )

    # A thread-safe state machine wrapping a callable. Exposes
    #   dispatch / dispatch_async / get_state / subscribe / reset
    # so that observers can react to in-flight, succeeded, or failed calls.
    #
    # dispatch     — fire-and-forget; runs the callable in a background thread.
    # dispatch_async — blocking; runs the callable in the current thread and
    #                 returns the result (or raises on failure / supersession).
    #
    # Only the most recent dispatch can mutate state — superseded calls silently
    # drop their result via a generation counter.
    #
    # Mirrors TypeScript's ReactiveActionStore<TArgs, TResult>.
    class ReactiveActionStore
      extend T::Sig

      sig { params(fn: T.proc.params(args: T.untyped).returns(T.untyped)).void }
      def initialize(fn)
        @fn          = T.let(fn,   T.proc.params(args: T.untyped).returns(T.untyped))
        @state       = T.let(REACTIVE_ACTION_IDLE_STATE, ReactiveActionState)
        @listeners   = T.let([], T::Array[T.proc.void])
        @mutex       = T.let(Mutex.new, Mutex)
        @current_gen = T.let(0, Integer)
      end

      # Returns the current lifecycle snapshot.
      sig { returns(ReactiveActionState) }
      def get_state
        @mutex.synchronize { @state }
      end

      # Fire-and-forget dispatch. Runs fn in a background thread. Only the
      # most recent call's result updates state; superseded threads are ignored.
      sig { params(args: T.untyped).void }
      def dispatch(*args)
        gen        = T.let(nil, T.nilable(Integer))
        prev_data  = T.let(nil, T.untyped)
        @mutex.synchronize do
          @current_gen += 1
          gen       = @current_gen
          prev_data = @state.data
          @state    = ReactiveActionState.new(status: 'running', data: prev_data)
        end
        _notify

        Thread.new do
          begin
            result  = @fn.call(*T.unsafe(args))
            active  = @mutex.synchronize do
              if @current_gen == gen
                @state = ReactiveActionState.new(status: 'success', data: result)
                true
              else
                false
              end
            end
            _notify if active
          rescue => e
            active = @mutex.synchronize do
              if @current_gen == gen
                @state = ReactiveActionState.new(status: 'error', data: prev_data, error: e)
                true
              else
                false
              end
            end
            _notify if active
          end
        end

        nil
      end

      # Blocking dispatch. Runs fn in the current thread. Returns the result on
      # success. Raises the error on failure. Raises RuntimeError if superseded
      # by a concurrent dispatch or reset().
      sig { params(args: T.untyped).returns(T.untyped) }
      def dispatch_async(*args)
        gen        = T.let(nil, T.nilable(Integer))
        prev_data  = T.let(nil, T.untyped)
        @mutex.synchronize do
          @current_gen += 1
          gen       = @current_gen
          prev_data = @state.data
          @state    = ReactiveActionState.new(status: 'running', data: prev_data)
        end
        _notify

        result = @fn.call(*T.unsafe(args))

        active = @mutex.synchronize do
          if @current_gen == gen
            @state = ReactiveActionState.new(status: 'success', data: result)
            true
          else
            false
          end
        end
        _notify if active
        Kernel.raise 'ReactiveActionStore: call was superseded' unless active
        result
      rescue RuntimeError
        Kernel.raise
      rescue => e
        active = @mutex.synchronize do
          if @current_gen == gen
            @state = ReactiveActionState.new(status: 'error', data: prev_data, error: e)
            true
          else
            false
          end
        end
        _notify if active
        Kernel.raise e
      end

      # Aborts any in-flight background dispatch (by incrementing generation)
      # and resets state to idle.
      sig { void }
      def reset
        @mutex.synchronize do
          @current_gen += 1
          @state = REACTIVE_ACTION_IDLE_STATE
        end
        _notify
      end

      # Registers a listener called on every state change.
      # Returns an unsubscribe lambda.
      sig { params(listener: T.proc.void).returns(T.proc.void) }
      def subscribe(&listener)
        @mutex.synchronize { @listeners << listener }
        lambda { @mutex.synchronize { @listeners.delete(listener) } }
      end

      private

      sig { void }
      def _notify
        subs = @mutex.synchronize { @listeners.dup }
        subs.each(&:call)
      end
    end

    extend self

    # Wraps a callable in a ReactiveActionStore.
    # fn receives the arguments passed to dispatch/dispatch_async.
    #
    # Mirrors TypeScript's createReactiveActionStore.
    sig do
      params(fn: T.proc.params(args: T.untyped).returns(T.untyped)).returns(ReactiveActionStore)
    end
    def create_reactive_action_store(&fn)
      ReactiveActionStore.new(T.let(fn, T.proc.params(args: T.untyped).returns(T.untyped)))
    end
  end
end
