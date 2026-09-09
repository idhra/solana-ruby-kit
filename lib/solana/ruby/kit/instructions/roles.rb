# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module Instructions
    # Bitflag-based account roles for Solana instructions.
    # Mirrors TypeScript's `AccountRole` enum from @solana/instructions.
    #
    # Bit layout:
    #   bit 1 (0b10) → signer privilege
    #   bit 0 (0b01) → writable privilege
    module AccountRole
      extend T::Sig

      READONLY        = T.let(0b00, Integer)  # read-only, no signing required
      WRITABLE        = T.let(0b01, Integer)  # writable, no signing required
      READONLY_SIGNER = T.let(0b10, Integer)  # must sign, read-only
      WRITABLE_SIGNER = T.let(0b11, Integer)  # must sign AND writable

      ALL = T.let([READONLY, WRITABLE, READONLY_SIGNER, WRITABLE_SIGNER].freeze, T::Array[Integer])

      extend self

      # Returns true if the role requires the account to sign the transaction.
      sig { params(role: Integer).returns(T::Boolean) }
      def signer_role?(role)
        (role & 0b10) != 0
      end

      # Returns true if the role permits writing to the account.
      sig { params(role: Integer).returns(T::Boolean) }
      def writable_role?(role)
        (role & 0b01) != 0
      end

      # Returns the role that grants the highest privileges of both inputs.
      # Mirrors `mergeRoles()`.
      sig { params(a: Integer, b: Integer).returns(Integer) }
      def merge(a, b)
        a | b
      end

      # Removes the signer bit from a role.
      # Mirrors `downgradeRoleToNonSigner()`.
      sig { params(role: Integer).returns(Integer) }
      def downgrade_to_non_signer(role)
        role & 0b01
      end

      # Removes the writable bit from a role.
      # Mirrors `downgradeRoleToReadonly()`.
      sig { params(role: Integer).returns(Integer) }
      def downgrade_to_readonly(role)
        role & 0b10
      end

      # Adds the signer bit to a role.
      # Mirrors `upgradeRoleToSigner()`.
      sig { params(role: Integer).returns(Integer) }
      def upgrade_to_signer(role)
        role | 0b10
      end

      # Adds the writable bit to a role.
      # Mirrors `upgradeRoleToWritable()`.
      sig { params(role: Integer).returns(Integer) }
      def upgrade_to_writable(role)
        role | 0b01
      end

      # Human-readable name for a role (useful for debugging).
      sig { params(role: Integer).returns(String) }
      def name(role)
        case role
        when READONLY        then 'READONLY'
        when WRITABLE        then 'WRITABLE'
        when READONLY_SIGNER then 'READONLY_SIGNER'
        when WRITABLE_SIGNER then 'WRITABLE_SIGNER'
        else "UNKNOWN(#{role})"
        end
      end
    end
  end
end
