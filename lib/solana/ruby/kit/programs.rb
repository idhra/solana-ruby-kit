# typed: strict
# frozen_string_literal: true

# Mirrors @solana/programs — helpers for inspecting custom program errors
# returned in Solana transaction failures.
require_relative 'programs/associated_token_account'
require_relative 'programs/system_program'
require_relative 'programs/stake_program'
#
# A program error in a transaction result looks like:
#   { "InstructionError" => [0, { "Custom" => 1234 }] }
module Solana::Ruby::Kit
  module Programs
    extend T::Sig

    extend self

    # Returns true when +err+ is a custom program error, optionally matching
    # a specific error code.
    sig { params(err: T.untyped, expected_code: T.nilable(Integer)).returns(T::Boolean) }
    def program_error?(err, expected_code: nil)
      code = get_program_error_code(err)
      return false if code.nil?

      expected_code ? code == expected_code : true
    end

    # Extract the custom program error code from a transaction error hash.
    # Returns nil when the error is not a custom program error.
    sig { params(err: T.untyped).returns(T.nilable(Integer)) }
    def get_program_error_code(err)
      return nil unless err.is_a?(Hash)

      instruction_error = err['InstructionError']
      return nil unless instruction_error.is_a?(Array) && instruction_error.length == 2

      inner = instruction_error[1]
      return nil unless inner.is_a?(Hash) && inner.key?('Custom')

      Kernel.Integer(inner['Custom'])
    rescue TypeError, ArgumentError
      nil
    end
  end
end
