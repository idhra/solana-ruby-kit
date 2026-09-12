# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  # Maps TypeScript's SolanaError pattern to Ruby exceptions.
  # Each error code corresponds to a constant and carries structured context.
  # Mirrors @solana/errors codes.ts + messages.ts.
  class SolanaError < StandardError
    extend T::Sig

    # ── General ──────────────────────────────────────────────────────────────
    INVALID_KEYPAIR_SEED_LENGTH                          = :SOLANA_ERROR__INVALID_KEYPAIR_SEED_LENGTH
    INVALID_NONCE                                        = :SOLANA_ERROR__INVALID_NONCE

    # ── Addresses ─────────────────────────────────────────────────────────────
    ADDRESSES__INVALID_BASE58_ENCODED_ADDRESS            = :SOLANA_ERROR__ADDRESSES__INVALID_BASE58_ENCODED_ADDRESS
    ADDRESSES__INVALID_BYTE_LENGTH_FOR_ADDRESS           = :SOLANA_ERROR__ADDRESSES__INVALID_BYTE_LENGTH_FOR_ADDRESS
    ADDRESSES__STRING_LENGTH_OUT_OF_RANGE                = :SOLANA_ERROR__ADDRESSES__STRING_LENGTH_OUT_OF_RANGE_FOR_ADDRESS
    ADDRESSES__INVALID_ED25519_PUBLIC_KEY                = :SOLANA_ERROR__ADDRESSES__INVALID_ED25519_PUBLIC_KEY
    ADDRESSES__SEEDS_POINT_ON_CURVE                      = :SOLANA_ERROR__ADDRESSES__SEEDS_POINT_ON_CURVE
    ADDRESSES__MAX_SEED_LENGTH_EXCEEDED                  = :SOLANA_ERROR__ADDRESSES__MAX_SEED_LENGTH_EXCEEDED
    ADDRESSES__TOO_MANY_SEEDS                            = :SOLANA_ERROR__ADDRESSES__TOO_MANY_SEEDS
    ADDRESSES__FAILED_TO_FIND_VIABLE_PDA_BUMP_SEED       = :SOLANA_ERROR__ADDRESSES__FAILED_TO_FIND_VIABLE_PDA_BUMP_SEED
    ADDRESSES__INVALID_SEEDS_POINT_ON_CURVE              = :SOLANA_ERROR__ADDRESSES__INVALID_SEEDS_POINT_ON_CURVE
    ADDRESSES__PDA_BUMP_SEED_OUT_OF_RANGE                = :SOLANA_ERROR__ADDRESSES__PDA_BUMP_SEED_OUT_OF_RANGE

    # ── Accounts ──────────────────────────────────────────────────────────────
    ACCOUNTS__ACCOUNT_NOT_FOUND                          = :SOLANA_ERROR__ACCOUNTS__ACCOUNT_NOT_FOUND
    ACCOUNTS__ONE_OR_MORE_ACCOUNTS_NOT_FOUND             = :SOLANA_ERROR__ACCOUNTS__ONE_OR_MORE_ACCOUNTS_NOT_FOUND
    ACCOUNTS__EXPECTED_DECODED_ACCOUNT                   = :SOLANA_ERROR__ACCOUNTS__EXPECTED_DECODED_ACCOUNT
    ACCOUNTS__EXPECTED_ALL_ACCOUNTS_TO_BE_DECODED        = :SOLANA_ERROR__ACCOUNTS__EXPECTED_ALL_ACCOUNTS_TO_BE_DECODED
    ACCOUNTS__FAILED_TO_DECODE_ACCOUNT                   = :SOLANA_ERROR__ACCOUNTS__FAILED_TO_DECODE_ACCOUNT

    # ── Keys ──────────────────────────────────────────────────────────────────
    KEYS__INVALID_KEY_PAIR_BYTE_LENGTH                   = :SOLANA_ERROR__KEYS__INVALID_KEY_PAIR_BYTE_LENGTH
    KEYS__PUBLIC_KEY_MUST_MATCH_PRIVATE_KEY              = :SOLANA_ERROR__KEYS__PUBLIC_KEY_MUST_MATCH_PRIVATE_KEY
    KEYS__INVALID_SIGNATURE_BYTE_LENGTH                  = :SOLANA_ERROR__KEYS__INVALID_SIGNATURE_BYTE_LENGTH
    KEYS__SIGNATURE_STRING_LENGTH_OUT_OF_RANGE           = :SOLANA_ERROR__KEYS__SIGNATURE_STRING_LENGTH_OUT_OF_RANGE

    # ── Instructions ──────────────────────────────────────────────────────────
    INSTRUCTIONS__EXPECTED_TO_HAVE_ACCOUNTS              = :SOLANA_ERROR__INSTRUCTIONS__EXPECTED_TO_HAVE_ACCOUNTS
    INSTRUCTIONS__EXPECTED_TO_HAVE_DATA                  = :SOLANA_ERROR__INSTRUCTIONS__EXPECTED_TO_HAVE_DATA
    INSTRUCTIONS__PROGRAM_ADDRESS_MISMATCH               = :SOLANA_ERROR__INSTRUCTIONS__PROGRAM_ADDRESS_MISMATCH
    INSTRUCTIONS__ACCOUNT_NOT_FOUND                      = :SOLANA_ERROR__INSTRUCTIONS__ACCOUNT_NOT_FOUND
    INSTRUCTIONS__EXPECTED_ALL_ACCOUNTS_TO_BE_DECODED    = :SOLANA_ERROR__INSTRUCTIONS__EXPECTED_ALL_ACCOUNTS_TO_BE_DECODED

    # ── Transactions ──────────────────────────────────────────────────────────
    TRANSACTIONS__TRANSACTION_NOT_SIGNABLE               = :SOLANA_ERROR__TRANSACTIONS__TRANSACTION_NOT_SIGNABLE
    TRANSACTION__FAILED_TO_ESTIMATE_COMPUTE_LIMIT        = :SOLANA_ERROR__TRANSACTION__FAILED_TO_ESTIMATE_COMPUTE_LIMIT
    TRANSACTION__FAILED_WHEN_SIMULATING_TO_ESTIMATE_COMPUTE_LIMIT = :SOLANA_ERROR__TRANSACTION__FAILED_WHEN_SIMULATING_TO_ESTIMATE_COMPUTE_LIMIT
    TRANSACTION__FAILED_TO_ESTIMATE_LOADED_ACCOUNTS_DATA_SIZE_LIMIT = :SOLANA_ERROR__TRANSACTION__FAILED_TO_ESTIMATE_LOADED_ACCOUNTS_DATA_SIZE_LIMIT
    TRANSACTION__FAILED_WHEN_SIMULATING_TO_ESTIMATE_RESOURCE_LIMITS = :SOLANA_ERROR__TRANSACTION__FAILED_WHEN_SIMULATING_TO_ESTIMATE_RESOURCE_LIMITS
    TRANSACTIONS__EXCEEDS_SIZE_LIMIT                     = :SOLANA_ERROR__TRANSACTION__EXCEEDS_SIZE_LIMIT
    TRANSACTIONS__MISSING_SIGNER                         = :SOLANA_ERROR__TRANSACTIONS__MISSING_SIGNER
    TRANSACTIONS__VERSION_NUMBER_OUT_OF_RANGE            = :SOLANA_ERROR__TRANSACTIONS__VERSION_NUMBER_OUT_OF_RANGE
    TRANSACTIONS__FAILED_TO_DECOMPILE_ADDRESS_LOOKUP_TABLE_CONTENTS = :SOLANA_ERROR__TRANSACTIONS__FAILED_TO_DECOMPILE_ADDRESS_LOOKUP_TABLE_CONTENTS
    TRANSACTIONS__FAILED_TO_DECOMPILE_FEE_PAYER_MISSING = :SOLANA_ERROR__TRANSACTIONS__FAILED_TO_DECOMPILE_FEE_PAYER_MISSING
    TRANSACTIONS__FAILED_TO_DECOMPILE_INSTRUCTION_PROGRAM_ADDRESS_NOT_FOUND = :SOLANA_ERROR__TRANSACTIONS__FAILED_TO_DECOMPILE_INSTRUCTION_PROGRAM_ADDRESS_NOT_FOUND
    # context: { index: }
    TRANSACTION__FAILED_TO_DECOMPILE_INSTRUCTION_ACCOUNT_INDEX_OUT_OF_RANGE = :SOLANA_ERROR__TRANSACTION__FAILED_TO_DECOMPILE_INSTRUCTION_ACCOUNT_INDEX_OUT_OF_RANGE
    # context: { unsupported_version: }
    TRANSACTION__VERSION_NUMBER_NOT_SUPPORTED            = :SOLANA_ERROR__TRANSACTION__VERSION_NUMBER_NOT_SUPPORTED
    # context: { compute_unit_limit:, max_compute_unit_limit: }
    TRANSACTION__COMPUTE_UNIT_LIMIT_OUT_OF_RANGE         = :SOLANA_ERROR__TRANSACTION__COMPUTE_UNIT_LIMIT_OUT_OF_RANGE
    # context: { heap_size:, max_heap_size:, min_heap_size:, multiple_of: }
    TRANSACTION__INVALID_HEAP_SIZE                       = :SOLANA_ERROR__TRANSACTION__INVALID_HEAP_SIZE
    TRANSACTIONS__SEND_TRANSACTION_PREFLIGHT_FAILURE     = :SOLANA_ERROR__TRANSACTIONS__SEND_TRANSACTION_PREFLIGHT_FAILURE
    TRANSACTIONS__BLOCKHASH_NOT_FOUND                    = :SOLANA_ERROR__TRANSACTIONS__BLOCKHASH_NOT_FOUND
    TRANSACTIONS__FAILED_TRANSACTION_PLAN                = :SOLANA_ERROR__TRANSACTIONS__FAILED_TRANSACTION_PLAN
    TRANSACTIONS__TRANSACTION_EXPIRED_BLOCKHEIGHT_EXCEEDED = :SOLANA_ERROR__TRANSACTIONS__TRANSACTION_EXPIRED_BLOCKHEIGHT_EXCEEDED
    TRANSACTIONS__TRANSACTION_EXPIRED_NONCE_INVALID      = :SOLANA_ERROR__TRANSACTIONS__TRANSACTION_EXPIRED_NONCE_INVALID
    TRANSACTIONS__TRANSACTION_CONFIRMATION_TIMEOUT       = :SOLANA_ERROR__TRANSACTIONS__TRANSACTION_CONFIRMATION_TIMEOUT

    # ── Signers ───────────────────────────────────────────────────────────────
    SIGNERS__ADDRESS_CANNOT_HAVE_MULTIPLE_SIGNERS        = :SOLANA_ERROR__SIGNERS__ADDRESS_CANNOT_HAVE_MULTIPLE_SIGNERS
    SIGNERS__EXPECTED_MESSAGE_MODIFYING_SIGNER           = :SOLANA_ERROR__SIGNERS__EXPECTED_MESSAGE_MODIFYING_SIGNER
    SIGNERS__EXPECTED_TRANSACTION_MODIFYING_SIGNER       = :SOLANA_ERROR__SIGNERS__EXPECTED_TRANSACTION_MODIFYING_SIGNER
    SIGNERS__EXPECTED_TRANSACTION_SENDING_SIGNER         = :SOLANA_ERROR__SIGNERS__EXPECTED_TRANSACTION_SENDING_SIGNER
    SIGNERS__TRANSACTION_CANNOT_HAVE_MULTIPLE_SENDING_SIGNERS = :SOLANA_ERROR__SIGNERS__TRANSACTION_CANNOT_HAVE_MULTIPLE_SENDING_SIGNERS
    SIGNERS__WALLET_MULTISIGN_UNIMPLEMENTED              = :SOLANA_ERROR__SIGNERS__WALLET_MULTISIGN_UNIMPLEMENTED

    # ── Codecs ────────────────────────────────────────────────────────────────
    CODECS__CANNOT_DECODE_EMPTY_BYTE_ARRAY               = :SOLANA_ERROR__CODECS__CANNOT_DECODE_EMPTY_BYTE_ARRAY
    CODECS__EXPECTED_POSITIVE_BYTE_LENGTH                = :SOLANA_ERROR__CODECS__EXPECTED_POSITIVE_BYTE_LENGTH
    CODECS__ENCODER_DECODER_FIXED_SIZE_MISMATCH          = :SOLANA_ERROR__CODECS__ENCODER_DECODER_FIXED_SIZE_MISMATCH
    CODECS__ENCODER_DECODER_MAX_SIZE_MISMATCH            = :SOLANA_ERROR__CODECS__ENCODER_DECODER_MAX_SIZE_MISMATCH
    CODECS__INVALID_NUMBER_OF_ITEMS                      = :SOLANA_ERROR__CODECS__INVALID_NUMBER_OF_ITEMS
    CODECS__ENUM_DISCRIMINATOR_OUT_OF_RANGE              = :SOLANA_ERROR__CODECS__ENUM_DISCRIMINATOR_OUT_OF_RANGE
    CODECS__UNION_VARIANT_OUT_OF_RANGE                   = :SOLANA_ERROR__CODECS__UNION_VARIANT_OUT_OF_RANGE
    CODECS__OFFSET_OUT_OF_RANGE                          = :SOLANA_ERROR__CODECS__OFFSET_OUT_OF_RANGE
    CODECS__SENTINEL_MISSING_IN_DECODED_BYTES            = :SOLANA_ERROR__CODECS__SENTINEL_MISSING_IN_DECODED_BYTES
    CODECS__INVALID_STRING_FOR_BASE58_CODEC              = :SOLANA_ERROR__CODECS__INVALID_STRING_FOR_BASE58_CODEC
    CODECS__INVALID_STRING_FOR_BASE64_CODEC              = :SOLANA_ERROR__CODECS__INVALID_STRING_FOR_BASE64_CODEC
    CODECS__INVALID_STRING_FOR_HEX_CODEC                 = :SOLANA_ERROR__CODECS__INVALID_STRING_FOR_HEX_CODEC
    CODECS__INVALID_BYTE_LENGTH                          = :SOLANA_ERROR__CODECS__INVALID_BYTE_LENGTH
    CODECS__EXPECTED_ZERO_VALUE_TO_MATCH_ITEM_FIXED_DISCRIMINATOR = :SOLANA_ERROR__CODECS__EXPECTED_ZERO_VALUE_TO_MATCH_ITEM_FIXED_DISCRIMINATOR
    CODECS__FIXED_NULLABLE_CANNOT_WRAP_VARIABLE_SIZE_CODEC = :SOLANA_ERROR__CODECS__FIXED_NULLABLE_CANNOT_WRAP_VARIABLE_SIZE_CODEC
    # context: { bytes:, offset: }
    CODECS__INVALID_UTF8_BYTES                           = :SOLANA_ERROR__CODECS__INVALID_UTF8_BYTES
    # context: { index:, value: }
    CODECS__INVALID_UTF8_STRING                          = :SOLANA_ERROR__CODECS__INVALID_UTF8_STRING

    # ── RPC / JSON-RPC ────────────────────────────────────────────────────────
    RPC__INTEGER_OVERFLOW_WHILE_SERIALIZING_LARGE_INTEGER = :SOLANA_ERROR__RPC__INTEGER_OVERFLOW_WHILE_SERIALIZING_LARGE_INTEGER
    RPC__INTEGER_OVERFLOW_WHILE_DESERIALIZING_LARGE_INTEGER = :SOLANA_ERROR__RPC__INTEGER_OVERFLOW_WHILE_DESERIALIZING_LARGE_INTEGER
    RPC__TRANSPORT_HTTP_ERROR                             = :SOLANA_ERROR__RPC__TRANSPORT_HTTP_ERROR
    # JSON-RPC server errors (see https://github.com/anza-xyz/kit/blob/main/packages/errors/src/codes.ts)
    JSON_RPC__SERVER_ERROR_EPOCH_REWARDS_PERIOD_ACTIVE    = :SOLANA_ERROR__JSON_RPC__SERVER_ERROR_EPOCH_REWARDS_PERIOD_ACTIVE
    JSON_RPC__SERVER_ERROR_SLOT_NOT_EPOCH_BOUNDARY        = :SOLANA_ERROR__JSON_RPC__SERVER_ERROR_SLOT_NOT_EPOCH_BOUNDARY
    JSON_RPC__SERVER_ERROR_LONG_TERM_STORAGE_UNREACHABLE  = :SOLANA_ERROR__JSON_RPC__SERVER_ERROR_LONG_TERM_STORAGE_UNREACHABLE
    JSON_RPC__SERVER_ERROR_NO_SLOT_HISTORY                = :SOLANA_ERROR__JSON_RPC__SERVER_ERROR_NO_SLOT_HISTORY
    JSON_RPC__SERVER_ERROR_FILTER_TRANSACTION_NOT_FOUND   = :SOLANA_ERROR__JSON_RPC__SERVER_ERROR_FILTER_TRANSACTION_NOT_FOUND
    RPC_SUBSCRIPTIONS__CANNOT_CREATE_SUBSCRIPTION_REQUEST = :SOLANA_ERROR__RPC_SUBSCRIPTIONS__CANNOT_CREATE_SUBSCRIPTION_REQUEST
    RPC_SUBSCRIPTIONS__EXPECTED_SERVER_SUBSCRIPTION_ID   = :SOLANA_ERROR__RPC_SUBSCRIPTIONS__EXPECTED_SERVER_SUBSCRIPTION_ID
    RPC_SUBSCRIPTIONS__CHANNEL_CLOSED_BEFORE_MESSAGE_BUFFERED = :SOLANA_ERROR__RPC_SUBSCRIPTIONS__CHANNEL_CLOSED_BEFORE_MESSAGE_BUFFERED
    RPC_SUBSCRIPTIONS__CHANNEL_CONNECTION_CLOSED         = :SOLANA_ERROR__RPC_SUBSCRIPTIONS__CHANNEL_CONNECTION_CLOSED
    RPC_SUBSCRIPTIONS__WEBSOCKET_CONNECTION_FAILED        = :SOLANA_ERROR__RPC_SUBSCRIPTIONS__WEBSOCKET_CONNECTION_FAILED

    # ── Offchain messages ─────────────────────────────────────────────────────
    OFFCHAIN_MESSAGES__FAILED_TO_DECODE_MESSAGE          = :SOLANA_ERROR__OFFCHAIN_MESSAGES__FAILED_TO_DECODE_MESSAGE
    OFFCHAIN_MESSAGES__INVALID_MESSAGE_FORMAT            = :SOLANA_ERROR__OFFCHAIN_MESSAGES__INVALID_MESSAGE_FORMAT
    OFFCHAIN_MESSAGES__INVALID_MESSAGE_VERSION           = :SOLANA_ERROR__OFFCHAIN_MESSAGES__INVALID_MESSAGE_VERSION
    OFFCHAIN_MESSAGES__NON_PRINTABLE_ASCII_CHARACTER     = :SOLANA_ERROR__OFFCHAIN_MESSAGES__NON_PRINTABLE_ASCII_CHARACTER
    OFFCHAIN_MESSAGES__MESSAGE_TOO_LONG                  = :SOLANA_ERROR__OFFCHAIN_MESSAGES__MESSAGE_TOO_LONG
    OFFCHAIN_MESSAGES__LEADING_ZERO_IN_SIGNING_DOMAIN    = :SOLANA_ERROR__OFFCHAIN_MESSAGES__LEADING_ZERO_IN_SIGNING_DOMAIN
    # context: { actual_bytes:, expected_bytes: }
    OFFCHAIN_MESSAGES__CONTENT_DOES_NOT_MATCH_EXPECTED   = :SOLANA_ERROR__OFFCHAIN_MESSAGE__CONTENT_DOES_NOT_MATCH_EXPECTED
    # context: { actual_addresses:, expected_addresses: }
    OFFCHAIN_MESSAGES__REQUIRED_SIGNATORIES_DO_NOT_MATCH_EXPECTED = :SOLANA_ERROR__OFFCHAIN_MESSAGE__REQUIRED_SIGNATORIES_DO_NOT_MATCH_EXPECTED

    # ── Instruction plans ─────────────────────────────────────────────────────
    # context: { num_bytes_required:, num_free_bytes: }
    INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN      = :SOLANA_ERROR__INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN
    INSTRUCTION_PLANS__MESSAGE_PACKER_ALREADY_COMPLETE      = :SOLANA_ERROR__INSTRUCTION_PLANS__MESSAGE_PACKER_ALREADY_COMPLETE
    INSTRUCTION_PLANS__EMPTY_INSTRUCTION_PLAN               = :SOLANA_ERROR__INSTRUCTION_PLANS__EMPTY_INSTRUCTION_PLAN
    INSTRUCTION_PLANS__FAILED_TO_EXECUTE_TRANSACTION_PLAN   = :SOLANA_ERROR__INSTRUCTION_PLANS__FAILED_TO_EXECUTE_TRANSACTION_PLAN
    # context: { max_instructions:, transaction_instruction_limit: }
    INSTRUCTION_PLANS__INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION = :SOLANA_ERROR__INSTRUCTION_PLANS__INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION
    # context: { max_instructions:, num_instructions: }
    INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED = :SOLANA_ERROR__INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED

    # ── Transaction introspection ────────────────────────────────────────────
    TRANSACTION_INTROSPECTION__CANNOT_DECODE_JSON_PARSED_TRANSACTION = :SOLANA_ERROR__TRANSACTION_INTROSPECTION__CANNOT_DECODE_JSON_PARSED_TRANSACTION
    TRANSACTION_INTROSPECTION__UNRECOGNIZED_GET_TRANSACTION_RESPONSE = :SOLANA_ERROR__TRANSACTION_INTROSPECTION__UNRECOGNIZED_GET_TRANSACTION_RESPONSE
    # context: { needed_bytes: }
    TRANSACTION_INTROSPECTION__MALFORMED_COMPILED_MESSAGE = :SOLANA_ERROR__TRANSACTION_INTROSPECTION__MALFORMED_COMPILED_MESSAGE

    # ── Wallet Standard ───────────────────────────────────────────────────────
    WALLET_STANDARD__INVALID_WIRE_FORMAT             = :SOLANA_ERROR__WALLET_STANDARD__INVALID_WIRE_FORMAT
    WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED   = :SOLANA_ERROR__WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED

    # ── Subscribable ──────────────────────────────────────────────────────────
    SUBSCRIBABLE__RETRY_NOT_SUPPORTED                     = :SOLANA_ERROR__SUBSCRIBABLE__RETRY_NOT_SUPPORTED
    SUBSCRIBABLE__STREAM_CLOSED_WITHOUT_ERROR             = :SOLANA_ERROR__SUBSCRIBABLE__STREAM_CLOSED_WITHOUT_ERROR

    # ── Fixed-points ──────────────────────────────────────────────────────────
    FIXED_POINTS__STRICT_MODE_PRECISION_LOSS              = :SOLANA_ERROR__FIXED_POINTS__STRICT_MODE_PRECISION_LOSS
    LAMPORTS_OUT_OF_RANGE                                 = :SOLANA_ERROR__LAMPORTS_OUT_OF_RANGE

    # ── Invariant violations (internal) ──────────────────────────────────────
    INVARIANT_VIOLATION__SUBSCRIPTION_ITERATOR_STATE_MISSING = :SOLANA_ERROR__INVARIANT_VIOLATION__SUBSCRIPTION_ITERATOR_STATE_MISSING
    INVARIANT_VIOLATION__SUBSCRIPTION_ITERATOR_MUST_NOT_POLL_BEFORE_RESOLVING_EXISTING_MESSAGE_PROMISE = :SOLANA_ERROR__INVARIANT_VIOLATION__SUBSCRIPTION_ITERATOR_MUST_NOT_POLL_BEFORE_RESOLVING_EXISTING_MESSAGE_PROMISE
    INVARIANT_VIOLATION__INVALID_INSTRUCTION_PLAN_KIND      = :SOLANA_ERROR__INVARIANT_VIOLATION__INVALID_INSTRUCTION_PLAN_KIND
    INVARIANT_VIOLATION__INVALID_TRANSACTION_PLAN_KIND      = :SOLANA_ERROR__INVARIANT_VIOLATION__INVALID_TRANSACTION_PLAN_KIND

    ERROR_MESSAGES = T.let(
      {
        # General
        INVALID_KEYPAIR_SEED_LENGTH                      => 'Keypair seed must be 32 bytes, got %{actual_length}',
        INVALID_NONCE                                    => 'The supplied nonce is not a valid nonce',

        # Addresses
        ADDRESSES__INVALID_BASE58_ENCODED_ADDRESS        => 'Not a valid base58-encoded address',
        ADDRESSES__INVALID_BYTE_LENGTH_FOR_ADDRESS       => 'Expected 32 bytes for an address, got %{byte_length}',
        ADDRESSES__STRING_LENGTH_OUT_OF_RANGE            => 'Address string length out of range (32–44 chars), got %{actual_length}',
        ADDRESSES__INVALID_ED25519_PUBLIC_KEY            => 'The public key is not a valid Ed25519 public key',
        ADDRESSES__SEEDS_POINT_ON_CURVE                  => 'The seeds resolve to a point on the Ed25519 curve; it cannot be used as a PDA',
        ADDRESSES__MAX_SEED_LENGTH_EXCEEDED              => 'A seed exceeds the maximum allowed length of 32 bytes, got %{actual_length}',
        ADDRESSES__TOO_MANY_SEEDS                        => 'Too many seeds provided (max 16)',
        ADDRESSES__FAILED_TO_FIND_VIABLE_PDA_BUMP_SEED   => 'Could not find a viable bump seed for the given program and seeds',
        ADDRESSES__INVALID_SEEDS_POINT_ON_CURVE          => 'The seeds result in a public key that lies on the Ed25519 curve',
        ADDRESSES__PDA_BUMP_SEED_OUT_OF_RANGE            => 'Bump seed must be in range [0, 255]',

        # Accounts
        ACCOUNTS__ACCOUNT_NOT_FOUND                      => 'Account not found at address %{address}',
        ACCOUNTS__ONE_OR_MORE_ACCOUNTS_NOT_FOUND         => 'One or more accounts were not found',
        ACCOUNTS__EXPECTED_DECODED_ACCOUNT               => 'Expected account at address %{address} to be decoded',
        ACCOUNTS__EXPECTED_ALL_ACCOUNTS_TO_BE_DECODED    => 'Expected all %{count} account(s) to be decoded',
        ACCOUNTS__FAILED_TO_DECODE_ACCOUNT               => 'Failed to decode account data at address %{address}',

        # Keys
        KEYS__INVALID_KEY_PAIR_BYTE_LENGTH               => 'Key pair byte array must be 64 bytes, got %{byte_length}',
        KEYS__PUBLIC_KEY_MUST_MATCH_PRIVATE_KEY          => 'The public key does not match the private key',
        KEYS__INVALID_SIGNATURE_BYTE_LENGTH              => 'Signature must be 64 bytes, got %{actual_length}',
        KEYS__SIGNATURE_STRING_LENGTH_OUT_OF_RANGE       => 'Signature string length out of range (64–88 chars), got %{actual_length}',

        # Instructions
        INSTRUCTIONS__EXPECTED_TO_HAVE_ACCOUNTS          => 'Expected instruction to have accounts',
        INSTRUCTIONS__EXPECTED_TO_HAVE_DATA              => 'Expected instruction to have data',
        INSTRUCTIONS__PROGRAM_ADDRESS_MISMATCH           => 'Instruction program address mismatch: expected %{expected}, got %{actual}',
        INSTRUCTIONS__ACCOUNT_NOT_FOUND                  => 'Account at index %{index} not found in instruction',
        INSTRUCTIONS__EXPECTED_ALL_ACCOUNTS_TO_BE_DECODED => 'Expected all instruction accounts to be decoded',

        # Transactions
        TRANSACTIONS__TRANSACTION_NOT_SIGNABLE           => 'Transaction is not signable (missing fee payer or lifetime constraint)',
        TRANSACTION__FAILED_TO_ESTIMATE_COMPUTE_LIMIT    => 'Failed to estimate the compute unit consumption for this transaction message. This is likely because simulating the transaction failed.',
        TRANSACTION__FAILED_WHEN_SIMULATING_TO_ESTIMATE_COMPUTE_LIMIT => 'Transaction failed when it was simulated in order to estimate the compute unit consumption.',
        TRANSACTION__FAILED_TO_ESTIMATE_LOADED_ACCOUNTS_DATA_SIZE_LIMIT => 'Failed to estimate the loaded accounts data size for this transaction message. The RPC did not return a loadedAccountsDataSize value from simulation. This value is required for version 1 transactions.',
        TRANSACTION__FAILED_WHEN_SIMULATING_TO_ESTIMATE_RESOURCE_LIMITS => 'Transaction failed when it was simulated in order to estimate its resource limits.',
        TRANSACTIONS__EXCEEDS_SIZE_LIMIT                 => 'Transaction wire size (%{actual_size} bytes) exceeds the limit of %{limit} bytes',
        TRANSACTIONS__MISSING_SIGNER                     => 'Transaction is missing a required signer: %{address}',
        TRANSACTIONS__VERSION_NUMBER_OUT_OF_RANGE        => 'Transaction version %{version} is out of range',
        TRANSACTIONS__FAILED_TO_DECOMPILE_ADDRESS_LOOKUP_TABLE_CONTENTS => 'Failed to decompile address lookup table contents',
        TRANSACTIONS__FAILED_TO_DECOMPILE_FEE_PAYER_MISSING => 'Failed to decompile transaction: fee payer is missing',
        TRANSACTIONS__FAILED_TO_DECOMPILE_INSTRUCTION_PROGRAM_ADDRESS_NOT_FOUND => 'Failed to decompile instruction: program address not found at index %{index}',
        TRANSACTION__FAILED_TO_DECOMPILE_INSTRUCTION_ACCOUNT_INDEX_OUT_OF_RANGE => 'Failed to decompile instruction: account index %{index} is out of range',
        TRANSACTION__VERSION_NUMBER_NOT_SUPPORTED        => 'Transaction version %{unsupported_version} is not supported',
        TRANSACTION__COMPUTE_UNIT_LIMIT_OUT_OF_RANGE     => 'Transaction compute unit limit must be an integer in the range [0, %{max_compute_unit_limit}]. `%{compute_unit_limit}` given',
        TRANSACTION__INVALID_HEAP_SIZE                   => 'Transaction heap size must be an integer multiple of %{multiple_of} bytes in the range [%{min_heap_size}, %{max_heap_size}]. `%{heap_size}` given',
        TRANSACTIONS__SEND_TRANSACTION_PREFLIGHT_FAILURE => 'Transaction simulation failed: %{message}',
        TRANSACTIONS__BLOCKHASH_NOT_FOUND                => 'Blockhash not found',
        TRANSACTIONS__FAILED_TRANSACTION_PLAN            => 'Failed to execute transaction plan',
        TRANSACTIONS__TRANSACTION_EXPIRED_BLOCKHEIGHT_EXCEEDED => 'Transaction expired: block height exceeded',
        TRANSACTIONS__TRANSACTION_EXPIRED_NONCE_INVALID  => 'Transaction expired: nonce is no longer valid',
        TRANSACTIONS__TRANSACTION_CONFIRMATION_TIMEOUT   => 'Timed out waiting for transaction %{signature} to confirm',

        # Signers
        SIGNERS__ADDRESS_CANNOT_HAVE_MULTIPLE_SIGNERS    => 'Address %{address} cannot be assigned multiple signers',
        SIGNERS__EXPECTED_MESSAGE_MODIFYING_SIGNER       => 'Expected signer to be a message modifying signer',
        SIGNERS__EXPECTED_TRANSACTION_MODIFYING_SIGNER   => 'Expected signer to be a transaction modifying signer',
        SIGNERS__EXPECTED_TRANSACTION_SENDING_SIGNER     => 'Expected signer to be a transaction sending signer',
        SIGNERS__TRANSACTION_CANNOT_HAVE_MULTIPLE_SENDING_SIGNERS => 'Transaction cannot have multiple sending signers',
        SIGNERS__WALLET_MULTISIGN_UNIMPLEMENTED          => 'Wallet multisign is not yet implemented',

        # Codecs
        CODECS__CANNOT_DECODE_EMPTY_BYTE_ARRAY           => 'Cannot decode an empty byte array',
        CODECS__EXPECTED_POSITIVE_BYTE_LENGTH            => 'Expected a positive byte length, got %{byte_length}',
        CODECS__ENCODER_DECODER_FIXED_SIZE_MISMATCH      => 'Encoder fixed size (%{encoder_size}) does not match decoder fixed size (%{decoder_size})',
        CODECS__ENCODER_DECODER_MAX_SIZE_MISMATCH        => 'Encoder max size (%{encoder_max}) does not match decoder max size (%{decoder_max})',
        CODECS__INVALID_NUMBER_OF_ITEMS                  => 'Expected %{expected} items but got %{actual}',
        CODECS__ENUM_DISCRIMINATOR_OUT_OF_RANGE          => 'Enum discriminator %{discriminator} is out of range [0, %{max}]',
        CODECS__UNION_VARIANT_OUT_OF_RANGE               => 'Union variant index %{index} is out of range',
        CODECS__OFFSET_OUT_OF_RANGE                      => 'Codec offset %{offset} is out of range for byte array of length %{byte_length}',
        CODECS__SENTINEL_MISSING_IN_DECODED_BYTES        => 'Sentinel bytes not found in decoded data',
        CODECS__INVALID_STRING_FOR_BASE58_CODEC          => 'Invalid base58 string: %{value}',
        CODECS__INVALID_STRING_FOR_BASE64_CODEC          => 'Invalid base64 string: %{value}',
        CODECS__INVALID_STRING_FOR_HEX_CODEC             => 'Invalid hex string: %{value}',
        CODECS__INVALID_BYTE_LENGTH                      => 'Expected %{expected} bytes but got %{actual}',
        CODECS__EXPECTED_ZERO_VALUE_TO_MATCH_ITEM_FIXED_DISCRIMINATOR => 'Expected zero value to match fixed discriminator',
        CODECS__FIXED_NULLABLE_CANNOT_WRAP_VARIABLE_SIZE_CODEC => 'A fixed-size nullable codec cannot wrap a variable-size codec',
        CODECS__INVALID_UTF8_BYTES                       => 'Invalid UTF-8 byte sequence at offset %{offset}',
        CODECS__INVALID_UTF8_STRING                      => 'Invalid UTF-8 string at index %{index}',

        # RPC
        RPC__INTEGER_OVERFLOW_WHILE_SERIALIZING_LARGE_INTEGER   => 'Integer overflow while serializing large integer %{value}',
        RPC__INTEGER_OVERFLOW_WHILE_DESERIALIZING_LARGE_INTEGER => 'Integer overflow while deserializing large integer %{value}',
        RPC__TRANSPORT_HTTP_ERROR                               => 'HTTP transport error: %{status} %{message}',
        JSON_RPC__SERVER_ERROR_EPOCH_REWARDS_PERIOD_ACTIVE      => 'Epoch rewards period still active at slot %{slot}',
        JSON_RPC__SERVER_ERROR_SLOT_NOT_EPOCH_BOUNDARY          => "Rewards cannot be found because slot %{slot} is not the epoch boundary. This may be due to gap in the queried node's local ledger or long-term storage",
        JSON_RPC__SERVER_ERROR_LONG_TERM_STORAGE_UNREACHABLE    => 'Failed to query long-term storage; please try again',
        JSON_RPC__SERVER_ERROR_NO_SLOT_HISTORY                  => 'No slot history',
        JSON_RPC__SERVER_ERROR_FILTER_TRANSACTION_NOT_FOUND     => 'Filter transaction not found',
        RPC_SUBSCRIPTIONS__CANNOT_CREATE_SUBSCRIPTION_REQUEST  => 'Cannot create subscription request',
        RPC_SUBSCRIPTIONS__EXPECTED_SERVER_SUBSCRIPTION_ID     => 'Expected server to return a subscription ID',
        RPC_SUBSCRIPTIONS__CHANNEL_CLOSED_BEFORE_MESSAGE_BUFFERED => 'WebSocket channel closed before message could be buffered',
        RPC_SUBSCRIPTIONS__CHANNEL_CONNECTION_CLOSED           => 'WebSocket connection closed: %{reason}',
        RPC_SUBSCRIPTIONS__WEBSOCKET_CONNECTION_FAILED         => 'Failed to establish WebSocket connection to %{url}',

        # Offchain messages
        OFFCHAIN_MESSAGES__FAILED_TO_DECODE_MESSAGE      => 'Failed to decode offchain message',
        OFFCHAIN_MESSAGES__INVALID_MESSAGE_FORMAT        => 'Invalid offchain message format',
        OFFCHAIN_MESSAGES__INVALID_MESSAGE_VERSION       => 'Invalid offchain message version %{version}',
        OFFCHAIN_MESSAGES__NON_PRINTABLE_ASCII_CHARACTER => 'Offchain message v0 contains non-printable ASCII character at index %{index}',
        OFFCHAIN_MESSAGES__MESSAGE_TOO_LONG              => 'Offchain message is too long (%{length} bytes, max %{max})',
        OFFCHAIN_MESSAGES__LEADING_ZERO_IN_SIGNING_DOMAIN => 'Offchain message signing domain must not start with a null byte',
        OFFCHAIN_MESSAGES__CONTENT_DOES_NOT_MATCH_EXPECTED => 'The content of the offchain message does not match the content that was expected. ' \
          'Expected content with a byte-length of %{expected_bytes}; got content with a byte-length of %{actual_bytes}. ' \
          'The signer may have signed different data than was requested; do not trust its signature.',
        OFFCHAIN_MESSAGES__REQUIRED_SIGNATORIES_DO_NOT_MATCH_EXPECTED => 'The offchain message lists different required signatories than was expected. ' \
          'Expected [%{expected_addresses}]. Got [%{actual_addresses}]. ' \
          'The signer may have signed different data than was requested; do not trust its signature.',

        # Instruction plans
        INSTRUCTION_PLANS__MESSAGE_CANNOT_ACCOMMODATE_PLAN    => 'Transaction message cannot accommodate the plan: requires %{num_bytes_required} bytes but only %{num_free_bytes} are available',
        INSTRUCTION_PLANS__MESSAGE_PACKER_ALREADY_COMPLETE    => 'Message packer is already complete; no more instructions to pack',
        INSTRUCTION_PLANS__EMPTY_INSTRUCTION_PLAN             => 'Instruction plan is empty and produced no transaction messages',
        INSTRUCTION_PLANS__FAILED_TO_EXECUTE_TRANSACTION_PLAN => 'Failed to execute transaction plan',
        INSTRUCTION_PLANS__INVALID_MAX_INSTRUCTIONS_PER_TRANSACTION => 'The configured maximum of %{max_instructions} instructions per transaction is invalid. It must be a positive integer no greater than the transaction format limit of %{transaction_instruction_limit} instructions per transaction.',
        INSTRUCTION_PLANS__MAX_INSTRUCTIONS_PER_TRANSACTION_EXCEEDED => 'Planning this transaction message would require %{num_instructions} instructions, which exceeds the configured maximum of %{max_instructions} instructions per transaction.',

        # Transaction introspection
        TRANSACTION_INTROSPECTION__CANNOT_DECODE_JSON_PARSED_TRANSACTION => "Cannot decode a 'jsonParsed'-encoded getTransaction response; its instructions are pre-parsed and lack raw bytes. Fetch with encoding: 'json' or 'base64' instead.",
        TRANSACTION_INTROSPECTION__UNRECOGNIZED_GET_TRANSACTION_RESPONSE => 'Unrecognized getTransaction response shape; expected a base64, base58, or json-encoded transaction.',
        TRANSACTION_INTROSPECTION__MALFORMED_COMPILED_MESSAGE => 'Malformed compiled transaction message: expected at least %{needed_bytes} byte(s)',

        # Subscribable
        SUBSCRIBABLE__RETRY_NOT_SUPPORTED              => 'This reactive store does not support retry(); use create_reactive_store_from_data_publisher_factory for a retryable store',
        SUBSCRIBABLE__STREAM_CLOSED_WITHOUT_ERROR      => 'The stream store closed in an error state but did not report an error.',

        # Fixed-points
        FIXED_POINTS__STRICT_MODE_PRECISION_LOSS       => 'Value has more than 9 fractional digits and cannot be represented exactly as a Sol amount',
        LAMPORTS_OUT_OF_RANGE                          => 'Lamports value out of range; must fit in an unsigned 64-bit integer',

        # Wallet Standard
        WALLET_STANDARD__INVALID_WIRE_FORMAT           => 'Invalid transaction wire format: %{reason}',
        WALLET_STANDARD__SIGNATURE_VERIFICATION_FAILED => 'Signature verification failed for signer %{address}',

        # Invariant violations
        INVARIANT_VIOLATION__SUBSCRIPTION_ITERATOR_STATE_MISSING => 'Subscription iterator state is missing (internal error)',
        INVARIANT_VIOLATION__SUBSCRIPTION_ITERATOR_MUST_NOT_POLL_BEFORE_RESOLVING_EXISTING_MESSAGE_PROMISE => 'Subscription iterator must not poll before resolving existing message (internal error)',
        INVARIANT_VIOLATION__INVALID_INSTRUCTION_PLAN_KIND    => 'Invalid instruction plan kind: %{kind} (internal error)',
        INVARIANT_VIOLATION__INVALID_TRANSACTION_PLAN_KIND    => 'Invalid transaction plan kind: %{kind} (internal error)',
      }.freeze,
      T::Hash[Symbol, String]
    )

    sig { returns(Symbol) }
    attr_reader :code

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :context

    sig { params(code: Symbol, context: T::Hash[Symbol, T.untyped]).void }
    def initialize(code, context = {})
      @code    = T.let(code, Symbol)
      @context = T.let(context, T::Hash[Symbol, T.untyped])

      template = ERROR_MESSAGES[code] || code.to_s
      message  = context.empty? ? template : (template % display_context(context) rescue "#{template} #{context}")
      super(message)
    end

    private

    # Values used to fill a message template. Array values — lists of addresses, say —
    # interpolate as a comma-separated list rather than as Ruby's `inspect` output, so
    # that `[%{expected_addresses}]` reads like the TypeScript original. `#context` is
    # untouched and still hands back the array itself.
    sig { params(context: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def display_context(context)
      context.transform_values { |value| value.is_a?(Array) ? value.join(', ') : value }
    end
  end
end
