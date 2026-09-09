# typed: strict
# frozen_string_literal: true

require_relative '../errors'

module Solana::Ruby::Kit
  # NOTE: `MAX_COMPUTE_UNIT_LIMIT` lives in `compute_budget.rb`, which requires this file, so it
  # is referenced from a method body rather than at load time to keep the two files acyclic.
  module TransactionMessages
    # The smallest heap frame size that a transaction may request (32 KiB).
    MIN_HEAP_SIZE = T.let(32 * 1024, Integer)

    # The largest heap frame size that a transaction may request (256 KiB).
    MAX_HEAP_SIZE = T.let(256 * 1024, Integer)

    # A requested heap frame size must be a whole number of KiB.
    HEAP_SIZE_MULTIPLE_OF = T.let(1024, Integer)

    extend self

    # Raises if the given compute unit limit is one the runtime will not honor as written.
    #
    # A transaction may request at most MAX_COMPUTE_UNIT_LIMIT compute units. Requesting more
    # does not fail the transaction; the runtime clamps the request down to that maximum, so
    # the budget the transaction runs with is silently not the one that was asked for. Values
    # that are not integers are a separate hazard, since they cannot be encoded as a `u32` and
    # are not clamped. Failing here surfaces both at the point the value is set.
    #
    # Mirrors `assertIsValidComputeUnitLimit` from @solana/transaction-messages.
    sig { params(compute_unit_limit: T.untyped).void }
    def assert_is_valid_compute_unit_limit(compute_unit_limit)
      return if compute_unit_limit.is_a?(Integer) &&
                compute_unit_limit >= 0 &&
                compute_unit_limit <= MAX_COMPUTE_UNIT_LIMIT

      Kernel.raise SolanaError.new(
        SolanaError::TRANSACTION__COMPUTE_UNIT_LIMIT_OUT_OF_RANGE,
        { compute_unit_limit: compute_unit_limit, max_compute_unit_limit: MAX_COMPUTE_UNIT_LIMIT }
      )
    end

    # Raises if the given heap frame size is one the runtime will not accept.
    #
    # The requested heap size must be a multiple of HEAP_SIZE_MULTIPLE_OF bytes and lie between
    # MIN_HEAP_SIZE and MAX_HEAP_SIZE inclusive. This mirrors the transaction sanitization check
    # performed by the runtime.
    #
    # Mirrors `assertIsValidHeapSize` from @solana/transaction-messages. Ruby has no heap-size
    # setter of its own — the `RequestHeapFrame` instruction and the version 1 transaction config
    # are both untranslated — so this is offered as a standalone check for callers building that
    # instruction themselves.
    sig { params(heap_size: T.untyped).void }
    def assert_is_valid_heap_size(heap_size)
      return if heap_size.is_a?(Integer) &&
                heap_size >= MIN_HEAP_SIZE &&
                heap_size <= MAX_HEAP_SIZE &&
                (heap_size % HEAP_SIZE_MULTIPLE_OF).zero?

      Kernel.raise SolanaError.new(
        SolanaError::TRANSACTION__INVALID_HEAP_SIZE,
        {
          heap_size:     heap_size,
          max_heap_size: MAX_HEAP_SIZE,
          min_heap_size: MIN_HEAP_SIZE,
          multiple_of:   HEAP_SIZE_MULTIPLE_OF
        }
      )
    end
  end
end
