# typed: strict
# frozen_string_literal: true

# Mirrors @solana/fast-stable-stringify.
# Produces deterministic JSON by sorting Hash keys recursively.
# Used internally by RPC transport so request bodies are stable.
module Solana::Ruby::Kit
  module FastStableStringify
    extend T::Sig

    extend self

    # Serialize +value+ to a deterministic JSON string.
    # Hash keys are sorted lexicographically at every level.
    # Unsupported types (custom objects, Symbols as values, etc.) are treated
    # as +nil+ (same behaviour as JSON.generate's default replacer).
    sig { params(value: T.untyped).returns(String) }
    def stringify(value)
      serialize(value)
    end

    # Internal recursive serializer (exposed as module_function for testability).
    sig { params(value: T.untyped).returns(String) }
    def serialize(value) # rubocop:disable Metrics/MethodLength
      case value
      when NilClass  then 'null'
      when TrueClass then 'true'
      when FalseClass then 'false'
      when Integer
        # Sorbet: plain integer — output as-is
        value.to_s
      when Float
        # Match JSON behaviour: NaN / Infinity → null
        if value.nan? || value.infinite?
          'null'
        else
          # Avoid trailing zeros while staying valid JSON
          int = value.to_i
          int.to_f == value ? int.to_s : value.to_s
        end
      when String
        value.to_json
      when Array
        inner = value.map { |el| serialize(el) }.join(',')
        "[#{inner}]"
      when Hash
        pairs = value.keys.map(&:to_s).sort.filter_map do |k|
          raw_val = value[k] || value[k.to_sym]
          serialized = serialize(raw_val)
          next if serialized == 'undefined' # skip undefined-equivalent keys

          "#{k.to_s.to_json}:#{serialized}"
        end
        "{#{pairs.join(',')}}"
      else
        # Symbol, custom class, etc. → null
        'null'
      end
    end
    private_class_method :serialize
  end
end
