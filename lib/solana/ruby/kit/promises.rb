# typed: strict
# frozen_string_literal: true

require 'timeout'

# Mirrors @solana/promises.
# Provides thread-safe race and timeout helpers used by the RPC subscription
# transport layer.  Ruby threads replace JavaScript Promises throughout.
module Solana::Ruby::Kit
  module Promises
    extend T::Sig

    extend self

    # Run each callable in a dedicated thread and return the first result.
    # All losing threads are killed to avoid memory leaks — analogous to the
    # JS safeRace() that cancels losing promises via AbortSignal.
    #
    # @param callables [Array<#call>]  lambdas / procs to race
    # @param timeout_secs [Float, nil] optional wall-clock limit
    # @return the return value of whichever callable finishes first
    # @raise [Timeout::Error] if timeout_secs is reached before any finishes
    # @raise propagates any exception thrown by the winning callable
    sig do
      params(
        callables:    T::Array[T.proc.returns(T.untyped)],
        timeout_secs: T.nilable(Float)
      ).returns(T.untyped)
    end
    def safe_race(callables, timeout_secs: nil)
      result_q   = Queue.new
      threads    = callables.map do |callable|
        Thread.new do
          value = callable.call
          result_q.push([:ok, value])
        rescue StandardError => e
          result_q.push([:err, e])
        end
      end

      begin
        kind, payload = if timeout_secs
                         Timeout.timeout(timeout_secs) { result_q.pop }
                       else
                         result_q.pop
                       end
      ensure
        threads.each(&:kill)
      end

      Kernel.raise payload if kind == :err

      payload
    end

    # Execute +block+ with an optional wall-clock deadline.
    # When +secs+ is nil the block runs without any deadline.
    #
    # @param secs [Float, nil]
    # @raise [Timeout::Error] on deadline exceeded
    sig do
      type_parameters(:R)
        .params(secs: T.nilable(Float), block: T.proc.returns(T.type_parameter(:R)))
        .returns(T.type_parameter(:R))
    end
    def with_timeout(secs, &block)
      if secs
        Timeout.timeout(secs) { block.call }
      else
        yield
      end
    end

    # Returns a lambda that, when called, raises Timeout::Error.
    # Useful for constructing an "abort signal" from a deadline.
    sig { params(secs: Float).returns(T.proc.void) }
    def make_abort_signal(secs)
      start = T.let(Time.now, Time)
      Kernel.lambda do
        elapsed = Time.now - start
        Kernel.raise Timeout::Error, "Aborted after #{elapsed.round(2)}s" if elapsed >= secs
      end
    end
  end
end
