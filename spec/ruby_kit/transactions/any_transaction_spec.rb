# typed: ignore
# frozen_string_literal: true

require 'spec_helper'

# `FullySignedTransaction` must be accepted wherever a transaction is read.
#
# It is a parallel T::Struct rather than a subclass of `Transaction` — T::Struct
# is final — so it is not a subtype, and a `sig` naming only `Transaction`
# rejects it. That is backwards: `sign_transaction` *returns* one, and encoding,
# inspecting or sending the result is the ordinary next step, so the narrow
# signature rejected exactly the value the library hands you.
#
# It went unnoticed because `module_function` meant no signature was enforced at
# the module boundary. Turning enforcement on turned it into 22 spec failures at
# once; these examples pin the shape so it cannot come back.
RSpec.describe 'transactions accepting either struct' do
  let(:key_pair) { RubyKit::Keys.generate_key_pair }
  let(:address)  { RubyKit::Addresses.encode_address(key_pair.verify_key.to_bytes) }

  let(:unsigned) do
    RubyKit::Transactions::Transaction.new(
      message_bytes: RbNaCl::Random.random_bytes(64),
      signatures:    { address => nil }
    )
  end

  let(:signed) { RubyKit::Transactions.sign_transaction([key_pair.signing_key], unsigned) }

  it 'signing returns a FullySignedTransaction, not a Transaction' do
    expect(signed).to be_a(RubyKit::Transactions::FullySignedTransaction)
    expect(signed).not_to be_a(RubyKit::Transactions::Transaction)
  end

  # The two-call sequence every caller of this library makes.
  it 'wire-encodes the value signing just returned' do
    expect { RubyKit::Transactions.wire_encode_transaction(signed) }.not_to raise_error
    expect(RubyKit::Transactions.wire_encode_transaction(signed)).to be_a(String)
  end

  it 'reads the signature off a signed transaction' do
    expect(RubyKit::Transactions.get_signature_from_transaction(signed))
      .to be_a(RubyKit::Keys::Signature)
  end

  it 'answers its predicates for a signed transaction' do
    expect(RubyKit::Transactions.fully_signed_transaction?(signed)).to be(true)
    expect(RubyKit::Transactions.within_size_limit?(signed)).to be(true)
    expect(RubyKit::Transactions.sendable_transaction?(signed)).to be(true)
  end

  it 'runs its assertions against a signed transaction' do
    expect { RubyKit::Transactions.assert_fully_signed_transaction!(signed) }.not_to raise_error
    expect { RubyKit::Transactions.assert_within_size_limit!(signed) }.not_to raise_error
    expect { RubyKit::Transactions.assert_sendable_transaction!(signed) }.not_to raise_error
  end

  it 're-signs an already fully signed transaction' do
    expect { RubyKit::Transactions.partially_sign_transaction([key_pair.signing_key], signed) }
      .not_to raise_error
  end

  # Still works for the unsigned struct — widening must not have swapped one
  # accepted type for the other.
  it 'accepts a plain Transaction everywhere too' do
    expect(RubyKit::Transactions.fully_signed_transaction?(unsigned)).to be(false)
    expect { RubyKit::Transactions.wire_encode_transaction(unsigned) }.not_to raise_error
  end

  # And the widening is not a licence to pass anything.
  it 'still rejects something that is not a transaction at all' do
    expect { RubyKit::Transactions.wire_encode_transaction({ message_bytes: 'x' }) }
      .to raise_error(TypeError, /Parameter 'transaction'/)
  end
end
