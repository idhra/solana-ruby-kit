# typed: ignore
# frozen_string_literal: true

require 'spec_helper'

# Sorbet signatures have to be enforced on the calls people actually make.
#
# Every module here exposes its methods with `extend self`, and that is not a
# style choice. With `module_function`, Ruby copies each method onto the
# singleton class at `def` time — before sorbet installs its validating
# wrapper, which happens lazily on first call of the *instance* method. The
# copy therefore points at the unwrapped original, and `Mod.method(...)` gets
# no type checking at all, while `include Mod` then calling the same method
# does. Since every caller of this library uses the module form, that meant the
# `sig` on every public method in the kit was decorative.
#
# It failed in the way that is hardest to notice: a wrongly typed argument got
# no TypeError naming the parameter, but a NoMethodError several frames deep,
# where a caller's `rescue` could swallow it into a plausible-looking result.
#
# `extend self` routes the module call through the same instance method sorbet
# wrapped, so the check applies to both. These examples exist to fail if any
# module goes back to `module_function`.
RSpec.describe 'sorbet signature enforcement' do
  it 'validates arguments on module-level calls' do
    expect { RubyKit::Keys.signature_bytes(123) }
      .to raise_error(TypeError, /Parameter 'putative'.*Expected type String/)
  end

  it 'names the offending parameter rather than failing inside the method' do
    expect { RubyKit::Codecs::Numbers.u16_codec(endian: 'little') }
      .to raise_error(TypeError, /Parameter 'endian'.*Expected type Symbol/)
  end

  # The specific call that went unchecked in production: a raw 64-byte String
  # where a SignatureBytes was declared. It used to raise NoMethodError from
  # inside the method body — `undefined method 'value' for an instance of
  # String` — which a caller rescuing StandardError turned into "signature
  # invalid", rejecting every signature including correct ones.
  it 'rejects a raw String where a SignatureBytes is declared' do
    key_pair = RubyKit::Keys.generate_key_pair
    raw      = key_pair.signing_key.sign('hello')

    expect { RubyKit::Keys.verify_signature(key_pair.signing_key.verify_key, raw, 'hello') }
      .to raise_error(TypeError, /Parameter 'sig_bytes'/)
  end

  it 'still accepts a correctly wrapped signature' do
    key_pair = RubyKit::Keys.generate_key_pair
    wrapped  = RubyKit::Keys.sign_bytes(key_pair.signing_key, 'hello')

    expect(
      RubyKit::Keys.verify_signature(key_pair.signing_key.verify_key, wrapped, 'hello')
    ).to be(true)
  end

  # No module may expose its methods by copying them past the type checker.
  # Cheaper to assert here than to rediscover one module at a time.
  it 'uses no module_function anywhere in lib' do
    root    = File.expand_path('../../lib', __dir__)
    offends = Dir.glob("#{root}/**/*.rb").select do |file|
      File.readlines(file).any? { |line| line.match?(/^\s*module_function\s*$/) }
    end

    expect(offends).to be_empty,
                       "module_function disables sorbet runtime checks on module calls; " \
                       "use `extend self` instead. Found in: #{offends.join(', ')}"
  end
end
