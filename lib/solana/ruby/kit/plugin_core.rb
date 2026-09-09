# typed: strict
# frozen_string_literal: true

# Mirrors @solana/rpc-types plugin-core pattern (createEmptyClient / use).
#
# A PluginClient starts empty and is extended incrementally via #use.
# Each plugin is a callable that receives the current client and returns a
# Hash of { method_name => callable } which is merged into the client.
#
#   client = Solana::Ruby::Kit::PluginCore.create_client
#             .use(Solana::Ruby::Kit::Rpc::Api::ALL_METHODS)
#
module Solana::Ruby::Kit
  class PluginClient
    extend T::Sig

    sig { void }
    def initialize
      @methods = T.let({}, T::Hash[Symbol, T.proc.params(args: T.untyped).returns(T.untyped)])
    end

    # Apply +plugin+ and return a new PluginClient with the additional methods.
    # +plugin+ may be:
    #   - a Hash of { symbol => callable }
    #   - a callable that receives self and returns such a Hash
    sig { params(plugin: T.untyped).returns(PluginClient) }
    def use(plugin)
      new_methods = plugin.respond_to?(:call) ? plugin.call(self) : plugin
      extended    = PluginClient.new
      extended.instance_variable_set(:@methods, @methods.merge(new_methods.transform_keys(&:to_sym)))
      extended
    end

    sig { params(name: Symbol, args: T.untyped, block: T.untyped).returns(T.untyped) }
    def method_missing(name, *args, &block)
      m = @methods[name]
      return super unless m

      T.unsafe(m).call(*args, &block)
    end

    sig { params(name: Symbol, include_private: T::Boolean).returns(T::Boolean) }
    def respond_to_missing?(name, include_private = false)
      @methods.key?(name) || super
    end
  end

  module PluginCore
    extend T::Sig

    extend self

    sig { returns(PluginClient) }
    def create_client
      PluginClient.new
    end
  end
end
