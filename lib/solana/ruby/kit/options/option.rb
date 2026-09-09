# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Options
    extend T::Sig
    # Mirrors Rust's `Option<T>` pattern from @solana/options.
    #
    # TypeScript represents absence as `T | null`, but that collapses nested
    # options: `Option<Option<T>>` becomes indistinguishable from `Option<T>`.
    # This explicit discriminated union preserves that distinction.

    # Represents the presence of a value — mirrors TypeScript's `Some<T>`.
    class Some
      extend T::Sig
      extend T::Generic

      Elem = type_member

      sig { returns(Elem) }
      attr_reader :value

      sig { params(value: Elem).void }
      def initialize(value)
        @value = T.let(value, Elem)
      end

      sig { returns(String) }
      def inspect = "Some(#{T.unsafe(@value).inspect})"

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other)
        !!(other.is_a?(Some) && T.unsafe(value) == T.unsafe(other.value))
      end
    end

    # Represents the absence of a value — mirrors TypeScript's `None`.
    class None
      extend T::Sig

      INSTANCE = T.let(new, None)

      sig { returns(String) }
      def inspect = 'None'

      sig { params(other: T.untyped).returns(T::Boolean) }
      def ==(other) = other.is_a?(None)
    end

    # Sorbet type alias: Option<T> is either Some or None.
    # Because Sorbet generics on non-class types are limited, we use T.untyped
    # for the contained value at the type-alias level; callers rely on Some's
    # generic parameter for per-use type safety.
    Option = T.type_alias { T.any(Solana::Ruby::Kit::Options::Some[T.untyped], None) }

    # OptionOrNullable mirrors TypeScript's `OptionOrNullable<T>`:
    #   accepts Option<T>, T, or nil — useful for codec input.
    OptionOrNullable = T.type_alias { T.untyped }

    extend self

    # Wraps a value in Some.  Mirrors `some<T>(value)`.
    sig { params(value: T.untyped).returns(Solana::Ruby::Kit::Options::Some[T.untyped]) }
    def some(value)
      Some.new(value)
    end

    # Returns the singleton None instance.  Mirrors `none<T>()`.
    sig { returns(None) }
    def none
      None::INSTANCE
    end

    # Returns true if the value is an Option (Some or None).
    # Mirrors `isOption()`.
    sig { params(input: T.untyped).returns(T::Boolean) }
    def option?(input)
      input.is_a?(Some) || input.is_a?(None)
    end

    # Returns true if the option contains a value.
    # Mirrors `isSome()`.
    sig { params(opt: T.untyped).returns(T::Boolean) }
    def some?(opt)
      opt.is_a?(Some)
    end

    # Returns true if the option is empty.
    # Mirrors `isNone()`.
    sig { params(opt: T.untyped).returns(T::Boolean) }
    def none?(opt)
      opt.is_a?(None)
    end

    # Extracts the contained value, or returns a fallback.
    # Mirrors `unwrapOption(option, fallback?)`.
    #
    # @param opt      [Some, None]
    # @param fallback [Proc, nil] called when opt is None; returns nil if omitted
    sig { params(opt: T.untyped, fallback: T.nilable(T.proc.returns(T.untyped))).returns(T.untyped) }
    def unwrap_option(opt, fallback = nil)
      return opt.value if opt.is_a?(Some)

      fallback ? fallback.call : nil
    end

    # Wraps a nullable (nil-able) value into an Option.
    # Mirrors `wrapNullable()`.
    sig { params(nullable: T.untyped).returns(T.any(Solana::Ruby::Kit::Options::Some[T.untyped], None)) }
    def wrap_nullable(nullable)
      nullable.nil? ? none : some(nullable)
    end

    # Recursively unwraps nested Options within objects, arrays, and hashes.
    # Mirrors `unwrapOptionRecursively()`.
    #
    # Primitives (Integer, Float, String, Symbol, true, false) and
    # binary/typed-array equivalents are returned as-is.
    sig { params(input: T.untyped, fallback: T.nilable(T.proc.returns(T.untyped))).returns(T.untyped) }
    def unwrap_option_recursively(input, fallback = nil)
      nxt = ->(x) { unwrap_option_recursively(x, fallback) }

      case input
      when Some then nxt.call(input.value)
      when None then fallback ? fallback.call : nil
      when Array then input.map { |el| nxt.call(el) }
      when Hash  then input.transform_values { |v| nxt.call(v) }
      else input   # primitives and opaque objects pass through
      end
    end
  end
end
