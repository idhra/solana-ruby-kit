# typed: strict
# frozen_string_literal: true

require_relative '../errors'
require_relative '../addresses/address'

module Solana::Ruby::Kit
  module OffchainMessages
    extend T::Sig

    # An address that is required to sign an offchain message for it to be valid.
    # Mirrors TypeScript's `OffchainMessageSignatory`.
    class Signatory < T::Struct
      const :address, Addresses::Address
    end

    # A version 1 offchain message.
    #
    # Mirrors TypeScript's `OffchainMessageV1` — the shape from the newer
    # `@solana/offchain-messages` package, whose content is UTF-8 and whose preamble
    # lists the addresses required to sign it. This is a different type from the
    # legacy Message in message.rb, which models the older `@solana/signers`
    # domain/application-domain form; the two are not interchangeable.
    class MessageV1 < T::Struct
      # UTF-8 message content.
      const :content, String

      # Addresses required to sign this message. The offchain message specification
      # mandates that these be serialized in lexicographic order, so a decoded message
      # always lists them that way; one you build yourself may list them in any order.
      const :required_signatories, T::Array[Signatory], default: [].freeze

      extend T::Sig

      sig { returns(Integer) }
      def version = 1
    end

    extend self

    # Asserts that a version 1 offchain message received from an untrusted source is the
    # message it was expected to be.
    #
    # A signer (a wallet, say) returns the message bytes it signed alongside its signature.
    # Verifying that signature proves only that the signer produced it over *those* bytes;
    # it says nothing about whether those bytes represent the message that was asked for.
    # Use this to establish that they do, then verify the signature separately.
    #
    # Perform this assertion *before* verifying signatures. A signer that signed the wrong
    # message would otherwise surface as a signature verification failure, misattributing
    # the problem to the cryptography rather than to the content.
    #
    # Required signatories are compared without regard to order — both lists are sorted
    # first, and reported sorted so they can be compared by eye. Order is the only thing
    # ignored: the lists are otherwise compared element by element, so listing an address
    # twice on one side and once on the other is a mismatch rather than a no-op.
    #
    # Message content is never placed in the error context, since it can carry data better
    # kept out of logs and error reporting. Its length in UTF-8 bytes — the encoding in
    # which version 1 content is serialized — is reported instead.
    #
    # Raises SolanaError OFFCHAIN_MESSAGES__CONTENT_DOES_NOT_MATCH_EXPECTED if the two
    # messages' contents differ, or
    # OFFCHAIN_MESSAGES__REQUIRED_SIGNATORIES_DO_NOT_MATCH_EXPECTED if they require
    # signatures from different addresses. Content is checked first, so a message that
    # differs in both reports the content mismatch.
    #
    # Mirrors `assertOffchainMessageV1Equal(receivedMessage, expectedMessage)`.
    sig { params(received_message: MessageV1, expected_message: MessageV1).void }
    def assert_offchain_message_v1_equal(received_message, expected_message)
      if received_message.content != expected_message.content
        Kernel.raise SolanaError.new(
          SolanaError::OFFCHAIN_MESSAGES__CONTENT_DOES_NOT_MATCH_EXPECTED,
          {
            actual_bytes:   utf8_byte_length(received_message.content),
            expected_bytes: utf8_byte_length(expected_message.content)
          }
        )
      end

      actual_addresses   = sorted_signatory_addresses(received_message)
      expected_addresses = sorted_signatory_addresses(expected_message)
      return if actual_addresses == expected_addresses

      Kernel.raise SolanaError.new(
        SolanaError::OFFCHAIN_MESSAGES__REQUIRED_SIGNATORIES_DO_NOT_MATCH_EXPECTED,
        {
          actual_addresses:   actual_addresses.map(&:to_s),
          expected_addresses: expected_addresses.map(&:to_s)
        }
      )
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    sig { params(message: MessageV1).returns(T::Array[Addresses::Address]) }
    def sorted_signatory_addresses(message)
      message.required_signatories.map(&:address).sort
    end

    # Length of a string in UTF-8 bytes, which is how version 1 content is serialized.
    # Ruby strings carry their own encoding, so one that arrived as anything else is
    # converted first rather than having its raw bytes counted.
    #
    # NOTE: `::Encoding` must be spelled with the leading `::`. Bare `Encoding` resolves
    # to Solana::Ruby::Kit::Encoding — this gem's own base58 namespace — not Ruby's.
    sig { params(content: String).returns(Integer) }
    def utf8_byte_length(content)
      content.encoding == ::Encoding::UTF_8 ? content.bytesize : content.encode(::Encoding::UTF_8).bytesize
    end

    private_class_method :sorted_signatory_addresses
    private_class_method :utf8_byte_length
  end
end
