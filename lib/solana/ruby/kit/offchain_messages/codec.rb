# typed: strict
# frozen_string_literal: true

require 'base64'

module Solana::Ruby::Kit
  module OffchainMessages
    # Wire format for off-chain messages (Solana standard).
    #
    # v0: [0xFF, 0xFF] + domain_len(u8) + domain + version(u8) + message_len(u16LE) + message
    # v1: [0xFF, 0xFF] + domain_len(u8) + domain + version(u8) + app_domain_len(u16LE)
    #       + app_domain + message_len(u16LE) + message
    module Codec
      extend T::Sig

      MAGIC = T.let("\xFF\xFF".b.freeze, String)

      extend self

      # Serialize a Message to its canonical binary form.
      sig { params(msg: Message).returns(String) }
      def encode_offchain_message(msg)
        domain_b = msg.domain.encode('ASCII').b
        Kernel.raise ArgumentError, 'Domain exceeds 255 bytes' if domain_b.bytesize > 255

        message_b = msg.message.encode('UTF-8').b
        Kernel.raise ArgumentError, 'Message too large' if message_b.bytesize > 0xFFFF

        buf = MAGIC.dup
        buf << [domain_b.bytesize].pack('C')
        buf << domain_b
        buf << [msg.version].pack('C')

        # The v1 application-domain block is always emitted, using a zero length when
        # there is no application domain. The decoder reads this length unconditionally
        # for v1, so omitting the block would desynchronise it and make it read the
        # message length as an application-domain length.
        if msg.version >= 1
          app_b = msg.application_domain ? T.must(msg.application_domain).encode('ASCII').b : ''.b
          Kernel.raise ArgumentError, 'Application domain exceeds 65535 bytes' if app_b.bytesize > 0xFFFF

          buf << [app_b.bytesize].pack('v')
          buf << app_b
        end

        buf << [message_b.bytesize].pack('v')
        buf << message_b
        buf.b
      end

      # Deserialize a Message from its canonical binary form.
      sig { params(bytes: String).returns(Message) }
      def decode_offchain_message(bytes) # rubocop:disable Metrics/MethodLength
        b = bytes.b
        Kernel.raise SolanaError.new(SolanaError::OFFCHAIN_MESSAGES__INVALID_MESSAGE_FORMAT) unless b.byteslice(0, 2) == MAGIC

        offset     = 2
        domain_len = b.byteslice(offset, 1)&.unpack1('C') || 0
        offset    += 1
        domain     = b.byteslice(offset, domain_len)&.force_encoding('ASCII') || ''
        offset    += domain_len
        version    = b.byteslice(offset, 1)&.unpack1('C') || 0
        offset    += 1

        application_domain = nil
        if version >= 1
          app_len = b.byteslice(offset, 2)&.unpack1('v') || 0
          offset += 2
          # A zero length means there was no application domain, not an empty one, so
          # that encode/decode round-trips a message that never had one.
          application_domain = app_len.positive? ? b.byteslice(offset, app_len)&.force_encoding('ASCII') : nil
          offset += app_len
        end

        msg_len = b.byteslice(offset, 2)&.unpack1('v') || 0
        offset += 2
        message = b.byteslice(offset, msg_len)&.force_encoding('UTF-8') || ''

        Message.new(
          version:            version,
          domain:             domain,
          message:            message,
          application_domain: application_domain
        )
      end

      # Sign an off-chain message with a KeyPairSigner.
      sig { params(signer: Signers::KeyPairSigner, msg: Message).returns(Keys::Signature) }
      def sign_offchain_message(signer, msg)
        payload = encode_offchain_message(msg)
        Keys.encode_signature(signer.sign(payload))
      end

      # Verify an off-chain message signature.
      sig do
        params(
          verify_key: String,   # 32-byte Ed25519 public key
          signature:  Keys::Signature,
          msg:        Message
        ).returns(T::Boolean)
      end
      def verify_offchain_message_signature(verify_key, signature, msg)
        payload = encode_offchain_message(msg)
        vk      = RbNaCl::VerifyKey.new(verify_key)
        # `Signature` holds a base58 string (that is what `sign_offchain_message` returns),
        # so it has to be decoded back to the 64 raw bytes RbNaCl expects.
        sig_bytes = Solana::Ruby::Kit::Encoding::Base58.decode(signature.to_s)
        vk.verify(sig_bytes, payload)
        true
      rescue RbNaCl::BadSignatureError, RbNaCl::LengthError
        false
      end
    end
  end
end
