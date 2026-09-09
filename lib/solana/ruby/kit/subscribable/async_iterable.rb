# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Subscribable
    # Creates an Enumerator backed by a thread-safe Queue.
    #
    # Mirrors createAsyncIterableFromDataPublisher from @solana/subscribable.
    #
    # Usage:
    #   enum = AsyncIterable.from_publisher(publisher, data_channel: :accountNotification)
    #   enum.each { |notification| process(notification) }
    #
    # The enumerator blocks on Queue#pop until the publisher closes or the
    # optional +timeout+ expires.  When the publisher emits on the error
    # channel the exception is re-raised inside the enumerator.
    module AsyncIterable
      extend T::Sig

      # Sentinel value pushed into the queue when the stream is done.
      DONE = T.let(Object.new.freeze, Object)

      extend self

      # @param publisher [DataPublisher]
      # @param data_channel channel name for data messages
      # @param error_channel channel name for errors (default: :error)
      # @param timeout [Float, nil] per-item pop timeout in seconds
      # @return [Enumerator]
      sig do
        params(
          publisher:     DataPublisher,
          data_channel:  T.untyped,
          error_channel: T.untyped,
          timeout:       T.nilable(Float)
        ).returns(T::Enumerator[T.untyped])
      end
      def from_publisher(publisher, data_channel:, error_channel: :error, timeout: nil)
        queue = T.let(Queue.new, Queue)

        # Subscribe to data
        unsub_data = publisher.on(data_channel) { |data| queue.push([:data, data]) }

        # Subscribe to errors — re-raise inside the enumerator
        unsub_error = publisher.on(error_channel) { |err| queue.push([:error, err]) }

        # Subscribe to close
        unsub_close = publisher.on(DataPublisher::CLOSE_CHANNEL) { queue.push([:done, nil]) }

        cleanup = Kernel.lambda do
          unsub_data.call
          unsub_error.call
          unsub_close.call
        end

        Enumerator.new do |yielder|
          Kernel.loop do
            kind, payload = if timeout
                              begin
                                Timeout.timeout(timeout) { queue.pop }
                              rescue Timeout::Error
                                [:done, nil]
                              end
                            else
                              queue.pop
                            end

            case kind
            when :data  then yielder.yield(payload)
            when :error then Kernel.raise T.cast(payload, StandardError)
            else             break
            end
          end
        ensure
          cleanup.call
        end
      end
    end
  end
end
