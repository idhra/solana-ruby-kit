# solana-ruby-kit

A Ruby port of [@anza-xyz/kit](https://github.com/anza-xyz/kit) — the official Solana TypeScript SDK — translated into idiomatic Ruby with [Sorbet](https://sorbet.org) static types.

Every module maps 1-to-1 to a TypeScript package. All methods are synchronous (Ruby's RbNaCl is synchronous; TypeScript's Web Crypto API is not).  This port now tracks the anza-xyz/kit version.

## Requirements

- Ruby >= 3.2
- libsodium (required by `rbnacl`)

```bash
# macOS
brew install libsodium

# Debian / Ubuntu
apt-get install libsodium-dev
```

## Installation

```ruby
# Gemfile
gem 'solana-ruby-kit'
```

```bash
bundle install
```

## Examples

Full worked examples live on the [wiki](https://github.com/pzupan/solana-ruby-kit/wiki):

- [Quick Start](https://github.com/pzupan/solana-ruby-kit/wiki/Quick-Start)
- [Create a Wallet](https://github.com/pzupan/solana-ruby-kit/wiki/Create-a-Wallet)
- [Transfer SOL](https://github.com/pzupan/solana-ruby-kit/wiki/Transfer-SOL)
- [Create an Associated Token Account](https://github.com/pzupan/solana-ruby-kit/wiki/Create-an-Associated-Token-Account)
- [Stake SOL with a Validator](https://github.com/pzupan/solana-ruby-kit/wiki/Stake-SOL-with-a-Validator)
- [Verify a Wallet-Signed Transaction in Rails](https://github.com/pzupan/solana-ruby-kit/wiki/Verify-a-Wallet-Signed-Transaction-in-Rails)
- [Build a Transaction for Browser Signing](https://github.com/pzupan/solana-ruby-kit/wiki/Build-a-Transaction-for-Browser-Signing)

The sections below cover configuration and the per-module API reference.

## Rails

The gem includes a Railtie that auto-configures when Rails is present. Add it to your `Gemfile` as usual, then run the install generator:

```bash
rails generate solana:ruby:kit:install
```

This creates `config/initializers/ruby_kit.rb`:

```ruby
Solana::Ruby::Kit.configure do |config|
  config.rpc_url    = 'https://api.mainnet-beta.solana.com'
  config.ws_url     = 'wss://api.mainnet-beta.solana.com'
  config.commitment = :confirmed
  config.timeout    = 30
end
```

Or configure via `config/application.rb`:

```ruby
config.ruby_kit.rpc_url    = ENV['SOLANA_RPC_URL']
config.ruby_kit.commitment = :finalized
```

Get a pre-configured client anywhere in your app:

```ruby
rpc = Solana::Ruby::Kit.rpc_client
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `rpc_url` | `https://api.mainnet-beta.solana.com` | JSON-RPC endpoint |
| `ws_url` | `nil` | WebSocket endpoint for subscriptions |
| `commitment` | `:confirmed` | Default commitment level |
| `timeout` | `30` | HTTP read timeout in seconds |

## Modules

### `Solana::Ruby::Kit::Addresses` — `@solana/addresses`

Validate and work with base58-encoded Solana addresses.

```ruby
Addr = Solana::Ruby::Kit::Addresses

# Validate
Addr.address?('11111111111111111111111111111111')  # => true

# Wrap into a typed Address value object (raises on invalid input)
addr = Addr.address('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA')

# Encode / decode raw bytes
bytes = Addr.decode_address(addr)   # => 32-byte binary String
str   = Addr.encode_address(bytes)  # => base58 String

# Program Derived Addresses (PDAs)
program = Addr.address('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA')
pda = Addr.get_program_derived_address(
  program_address: program,
  seeds:           ['my-seed', [1, 2, 3]]
)
puts pda.address  # => Address
puts pda.bump     # => Integer (0-255)
```

### `Solana::Ruby::Kit::Keys` — `@solana/keys`

Ed25519 key generation, signing, and verification via libsodium.

```ruby
Keys = Solana::Ruby::Kit::Keys

# Generate
kp = Keys.generate_key_pair
kp.signing_key  # => RbNaCl::SigningKey
kp.verify_key   # => RbNaCl::VerifyKey

# From 64 raw bytes (seed || public key)
kp = Keys.create_key_pair_from_bytes(File.binread('wallet.bin'))

# From 32-byte private seed only
kp = Keys.create_key_pair_from_private_key_bytes(seed_bytes)

# Sign / verify
sig = Keys.sign_bytes(kp.signing_key, data)
ok  = Keys.verify_signature(kp.verify_key, sig, data)

# Base58-encode a signature
Keys.encode_signature(sig)   # => Signature string
Keys.decode_signature(str)   # => SignatureBytes
```

### `Solana::Ruby::Kit::Signers` — `@solana/signers`

High-level signer abstraction that wraps a key pair and exposes an `address`.

```ruby
Signers = Solana::Ruby::Kit::Signers

# Random new signer
signer = Signers.generate_key_pair_signer
signer.address    # => Addresses::Address
signer.to_s       # => base58 string

# From existing key pair
signer = Signers.create_signer_from_key_pair(kp)

# From raw bytes
signer = Signers.create_key_pair_signer_from_bytes(bytes_64)
signer = Signers.create_key_pair_signer_from_private_key_bytes(seed_32)

# Sign arbitrary data
sig = signer.sign(message_bytes)

# Sign a batch of messages for multiple signers
map = Signers.sign_message_bytes_with_signers([signer1, signer2], bytes)
# => { "addr1" => SignatureBytes, "addr2" => SignatureBytes }
```

### `Solana::Ruby::Kit::TransactionMessages` — `@solana/transaction-messages`

Immutable transaction message builder. Every method returns a new struct; originals are unmodified.

```ruby
TxMsg = Solana::Ruby::Kit::TransactionMessages

msg = TxMsg.create_transaction_message(version: 0)

# Set fee payer
msg = TxMsg.set_fee_payer(signer.address, msg)

# Set blockhash lifetime
constraint = TxMsg::BlockhashLifetimeConstraint.new(
  blockhash: '4vJ9...', last_valid_block_height: 123_456
)
msg = TxMsg.set_blockhash_lifetime(constraint, msg)

# Append / prepend instructions
msg = TxMsg.append_instructions(msg, [instruction])
msg = TxMsg.prepend_instructions(msg, [priority_fee_ix])

# Compute unit limit (SetComputeUnitLimit instruction from the Compute Budget program)
# The limit is validated: it must be an integer in [0, MAX_COMPUTE_UNIT_LIMIT] (1,400,000).
# The runtime silently clamps a larger request rather than failing, so asking for more than
# the maximum would run on a budget you did not ask for — this raises instead.
msg = TxMsg.set_transaction_message_compute_unit_limit(200_000, msg)
TxMsg.get_transaction_message_compute_unit_limit(msg)  # => 200_000

# The check is also available on its own, alongside one for heap frame sizes — a whole
# number of KiB in [MIN_HEAP_SIZE, MAX_HEAP_SIZE] (32 KiB to 256 KiB).
TxMsg.assert_is_valid_compute_unit_limit(200_000)
TxMsg.assert_is_valid_heap_size(64 * 1024)

# Loaded accounts data size limit
msg = TxMsg.set_transaction_message_loaded_accounts_data_size_limit(64_000, msg)
TxMsg.get_transaction_message_loaded_accounts_data_size_limit(msg)  # => 64_000

# Durable nonce lifetime
nonce_constraint = TxMsg::DurableNonceLifetimeConstraint.new(
  nonce:                 'abc...',
  nonce_account_address: nonce_addr
)
msg = TxMsg.set_durable_nonce_lifetime(nonce_constraint, msg)
```

### `Solana::Ruby::Kit::Transactions` — `@solana/transactions`

Compile, sign, and inspect transactions.

```ruby
Txns = Solana::Ruby::Kit::Transactions

# Compile a TransactionMessage into wire bytes + an empty signatures map.
# message_bytes are the bytes that each required signer must sign.
# A lifetime constraint (blockhash or durable nonce) is optional at compile
# time — omitting it writes 32 zero bytes into the blockhash field, which
# must be replaced before the transaction is valid for submission.
transaction = Txns.compile_transaction_message(message)

# Partially sign (one or more keys, not necessarily all signers)
tx = Txns.partially_sign_transaction([kp.signing_key], transaction)

# Fully sign (raises unless all signers have signed)
signed_tx = Txns.sign_transaction([kp.signing_key], transaction)

# Encode the fully signed transaction for submission via sendTransaction.
# Prepends compact-u16 signature count + 64-byte signatures to message bytes.
wire_bytes  = Txns.wire_encode_transaction(signed_tx)
wire_base64 = Base64.strict_encode64(wire_bytes)

# Get the transaction signature (fee payer's signature, base58)
sig = Txns.get_signature_from_transaction(signed_tx)

# Check completeness and size
Txns.fully_signed_transaction?(tx)      # => true / false
Txns.assert_fully_signed_transaction!(tx)

Txns.within_size_limit?(tx)             # => true if wire size <= 1232 bytes
Txns.assert_within_size_limit!(tx)

# Sendable = fully signed AND within size limit
Txns.sendable_transaction?(signed_tx)   # => true / false
Txns.assert_sendable_transaction!(signed_tx)
```

### `Solana::Ruby::Kit::Rpc` — `@solana/rpc`

Synchronous JSON-RPC client backed by `Net::HTTP`.

```ruby
rpc = Solana::Ruby::Kit::Rpc::Client.new(
  Solana::Ruby::Kit::RpcTypes.devnet,
  timeout:      10,
  open_timeout: 5
)

rpc.get_slot                                  # => Integer
rpc.get_block_height                          # => Integer
rpc.get_balance(address)                      # resp.value => lamports
rpc.get_latest_blockhash                      # resp.value.blockhash, .last_valid_block_height
rpc.get_account_info(address, encoding: 'base64')
rpc.get_multiple_accounts([addr1, addr2])
rpc.get_program_accounts(program_address)
rpc.get_signature_statuses([sig_str])
rpc.is_blockhash_valid(blockhash, commitment: :confirmed)
rpc.get_minimum_balance_for_rent_exemption(data_length)
rpc.get_transaction(signature, encoding: 'base64')
rpc.get_token_account_balance(token_account)
rpc.get_token_accounts_by_owner(owner, mint: mint_address)
rpc.get_epoch_info
rpc.get_epoch_schedule
rpc.get_block_time(slot)
rpc.get_inflation_reward([address])
rpc.get_signatures_for_address(address)
rpc.get_vote_accounts
rpc.get_ag_genesis_cert                      # Alpenglow genesis cert, or nil
rpc.simulate_transaction(encoded_tx)
rpc.send_transaction(encoded_tx)
rpc.request_airdrop(address, lamports)        # devnet / testnet only
```

Errors:

```ruby
rescue Solana::Ruby::Kit::Rpc::RpcError => e
  puts e.code     # JSON-RPC error code
  puts e.message  # JSON-RPC error message
rescue Solana::Ruby::Kit::Rpc::HttpTransportError => e
  puts e.status_code  # HTTP status code
```

### `Solana::Ruby::Kit::RpcTypes` — `@solana/rpc-types`

Cluster URL helpers and typed wrappers.

```ruby
RpcTypes = Solana::Ruby::Kit::RpcTypes

RpcTypes.mainnet                             # default mainnet URL
RpcTypes.mainnet('https://my-rpc.com')       # custom mainnet URL
RpcTypes.devnet                              # devnet
RpcTypes.testnet                             # testnet
RpcTypes.cluster_url('http://localhost:8899') # custom / localnet
```

### `Solana::Ruby::Kit::Options` — `@solana/options`

Rust-style `Option<T>` for Solana's on-chain option codec pattern.

```ruby
Opts = Solana::Ruby::Kit::Options

some = Opts.some(42)          # => Some(42)
none = Opts.none              # => None

Opts.some?(some)              # => true
Opts.none?(none)              # => true
Opts.option?(some)            # => true

Opts.unwrap_option(some)      # => 42
Opts.unwrap_option(none)      # => nil
Opts.unwrap_option(none, -> { 0 })  # => 0

Opts.wrap_nullable(nil)       # => None
Opts.wrap_nullable(42)        # => Some(42)

# Recursively unwrap nested structures
Opts.unwrap_option_recursively({ a: some, b: [none, some] })
# => { a: 42, b: [nil, 42] }
```

### `Solana::Ruby::Kit::Functional` — `@solana/functional`

Functional pipeline composition.

```ruby
Kit = Solana::Ruby::Kit

result = Kit::Functional.pipe(
  Kit::TransactionMessages.create_transaction_message(version: 0),
  ->(tx) { Kit::TransactionMessages.set_fee_payer(fee_payer, tx) },
  ->(tx) { Kit::TransactionMessages.set_blockhash_lifetime(constraint, tx) },
  ->(tx) { Kit::TransactionMessages.append_instructions(tx, [ix]) }
)
```

### `Solana::Ruby::Kit::Codecs` — `@solana/codecs`

Binary encoder/decoder framework for Solana on-chain data.

```ruby
Codecs = Solana::Ruby::Kit::Codecs

# Numbers. Every multi-byte codec takes `endian:`, defaulting to :little
# (which is what Solana uses on-chain).
u8   = Codecs.u8_codec
u16  = Codecs.u16_codec
u32  = Codecs.u32_codec
u64  = Codecs.u64_codec
u128 = Codecs.u128_codec
u256 = Codecs.u256_codec              # 32 bytes
i8   = Codecs.i8_codec
i256 = Codecs.i256_codec              # 32 bytes, two's complement
f32  = Codecs.f32_codec
be   = Codecs.u16_codec(endian: :big)

u16.encode(1000)         # => "\xe8\x03"
u16.decode("\xe8\x03")   # => [1000, 2]   # [value, bytes consumed]

# Strings
utf8  = Codecs.utf8_codec
bytes = Codecs.bytes_codec(32)

# Data structures
struct_codec = Codecs.struct_codec([
  ['amount', u64],
  ['mint',   bytes]
])
```

#### UTF-8 options

By default the UTF-8 codec substitutes `U+FFFD` for malformed input, strips a
leading byte order mark, and strips null characters - the last of which is what
makes fixed-size padded strings read back cleanly, at the cost of being lossy
for strings that legitimately contain nulls.

```ruby
# Reject invalid UTF-8 instead of substituting the replacement character.
strict = Codecs.utf8_codec(fatal: true)
strict.encode("a\xC0\x80")   # raises SolanaError (invalid UTF-8 string)
strict.decode("\xFF".b)      # raises SolanaError (invalid UTF-8 bytes)

# Decode losslessly, keeping null characters and a leading byte order mark.
lossless = Codecs.utf8_codec(ignore_bom: true, remove_null_characters: false)

# The assertions are usable on their own.
Codecs.find_malformed_utf8_sequence_offset("a\xC0\x80".b)  # => 1 (overlong)
Codecs.assert_is_well_formed_utf8_bytes("\xE8\xAA\x9E".b)  # passes ("語")
Codecs.remove_null_characters("a\x00b")                        # => "ab"
```

Note that `ignore_bom` follows `TextDecoder`'s confusing spelling: the default,
`false`, *strips* the mark; `true` keeps it.

#### Requiring a size prefix

A prefixed collection decodes an exhausted buffer to an empty collection rather
than failing, so a program can append a collection to an existing account layout
and still read accounts written before the change. Formats that cannot accept
that leniency - borsh requires the prefix to be present - can opt into failing:

```ruby
Codecs.array_codec(u8).decode(''.b)                              # => [[], 0]
Codecs.array_codec(u8, require_size_prefix: true).decode(''.b)   # raises SolanaError
```

`map_codec` and `set_codec` take the same option. It has no effect on
fixed-count collections, which carry no prefix.

#### Tap combinators

Wrap a codec in one that observes a value - or the bytes - without changing it,
for validation guards or logging. A tap that raises aborts the operation.

```ruby
guarded = Codecs.tap_encoder(u8.encoder) do |value|
  raise ArgumentError, 'Value must not exceed 100' if value > 100
end
guarded.encode(42)   # => "\x2a"
guarded.encode(200)  # raises ArgumentError

# Both sides at once; decode_tap is optional.
Codecs.tap_codec(u8, encode_tap: ->(v) { log(v) }, decode_tap: ->(v) { log(v) })

# Observe the bytes instead of the value.
Codecs.tap_decoder_bytes(u8.decoder) do |bytes, offset|
  raise ArgumentError, 'Expected a 0 or a 1' if bytes.bytes[offset] > 1
end
```

Upstream's byte taps take `(bytes, pre_offset, post_offset)` because encoders
there write into a shared buffer. A Ruby `Encoder` returns a standalone byte
String, so the encode-side taps receive exactly the bytes that were written.

### `Solana::Ruby::Kit::RpcSubscriptions` — `@solana/rpc-subscriptions`

WebSocket-based subscription client.

```ruby
ws = Solana::Ruby::Kit::RpcSubscriptions::Client.new(
  'wss://api.devnet.solana.com'
)

sub = ws.account_subscribe(address, commitment: :confirmed)
sub.on_message { |notification| puts notification }
sub.on_error   { |err|          puts err }

ws.account_unsubscribe(sub.id)
ws.close
```

### `Solana::Ruby::Kit::Sysvars` — `@solana/sysvars`

Well-known sysvar addresses and decoded account data.

```ruby
Sysvars = Solana::Ruby::Kit::Sysvars

Sysvars::Addresses::CLOCK_ADDRESS          # => Address
Sysvars::Addresses::RENT_ADDRESS
Sysvars::Addresses::EPOCH_SCHEDULE_ADDRESS

# Fetch and decode via an RPC client
clock = Sysvars.fetch_sysvar_clock(rpc)
clock.slot              # => Integer
clock.epoch             # => Integer
clock.unix_timestamp    # => Integer

rent = Sysvars.fetch_sysvar_rent(rpc)
rent.lamports_per_byte_year  # => Integer
rent.exemption_threshold     # => Float
```

### `Solana::Ruby::Kit::Programs` — `@solana/programs`

Program error helpers and well-known program interfaces.

```ruby
Programs = Solana::Ruby::Kit::Programs

# Inspect custom program errors in transaction simulation results
Programs.program_error?(err)                   # => true / false
Programs.program_error?(err, expected_code: 1) # match a specific code
Programs.get_program_error_code(err)           # => Integer or nil
```

#### `Programs::StakeProgram`

Create and delegate stake accounts.

```ruby
Stake = Solana::Ruby::Kit::Programs::StakeProgram

# Well-known addresses
Stake::PROGRAM_ID       # Stake11111111111111111111111111111111111111
Stake::STAKE_CONFIG_ID  # StakeConfig11111111111111111111111111111111
Stake::STAKE_ACCOUNT_SPACE  # => 200 (bytes required for a stake account)

# Build two instructions that allocate and initialise a new stake account.
# The caller appends both to a transaction message.
create_ixs = Stake.create_account_instructions(
  from:          fee_payer_address,   # funding wallet (writable, signer)
  stake_account: stake_keypair.address, # new stake account address (writable, signer)
  authorized:    owner_address,       # becomes both staker and withdrawer
  lamports:      2_282_880            # enough for rent + some stake
)

# Build one instruction that delegates an initialised stake account.
delegate_ix = Stake.delegate_instruction(
  stake_account: stake_keypair.address,
  vote_account:  validator_vote_address,
  authorized:    owner_address         # must sign the transaction
)
```

#### `Programs::AssociatedTokenAccount`

Create SPL token accounts at their canonical (Associated Token Account) address.

```ruby
ATA = Solana::Ruby::Kit::Programs::AssociatedTokenAccount

# Well-known program IDs
ATA::PROGRAM_ID          # ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL
ATA::TOKEN_PROGRAM_ID    # TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA
ATA::TOKEN_2022_PROGRAM_ID
ATA::SYSTEM_PROGRAM_ID

# Derive the ATA address (no RPC call required)
pda = ATA.get_associated_token_address(
  wallet:           owner_address,
  mint:             mint_address,
  token_program_id: ATA::TOKEN_PROGRAM_ID   # default; omit for SPL Token
)
pda.address  # => Addresses::Address (the ATA)
pda.bump     # => Integer

# Build the createAssociatedTokenAccount instruction
ix = ATA.create_instruction(
  payer:            fee_payer_address,  # pays rent
  wallet:           owner_address,      # will own the ATA
  mint:             mint_address,
  token_program_id: ATA::TOKEN_PROGRAM_ID,
  idempotent:       true   # use CreateIdempotent — safe to call if ATA exists
)
```

### `Solana::Ruby::Kit::OffchainMessages` — `@solana/signers`, `@solana/offchain-messages`

Sign and verify off-chain messages (Phantom wallet standard).

```ruby
OffChain = Solana::Ruby::Kit::OffchainMessages

msg = OffChain::Message.new(
  version: 1,                     # 0 = legacy printable ASCII, 1 = extended UTF-8
  domain:  'example.com',
  message: 'Hello, Solana!'
)

encoded = OffChain.encode_offchain_message(msg)
decoded = OffChain.decode_offchain_message(encoded)

signature = OffChain.sign_offchain_message(signer, msg)
OffChain.verify_offchain_message_signature(verify_key_bytes, signature, msg)  # => true
```

#### Checking that a signer signed what you asked

A wallet returns the message bytes it signed alongside its signature. Verifying that
signature only proves the signer produced it over *those* bytes — not that those bytes
are the message you asked for. Compare the two before you verify the signature, so a
signer that signed the wrong thing is reported as a content mismatch rather than as a
confusing cryptographic failure.

```ruby
Addresses = Solana::Ruby::Kit::Addresses

expected = OffChain::MessageV1.new(
  content:              'Transfer 1 SOL to Alice',
  required_signatories: [OffChain::Signatory.new(address: Addresses::Address.new(my_address))]
)

# Raises SolanaError if the content or the required signatories differ.
# Required signatories are compared ignoring order; content is compared exactly.
OffChain.assert_offchain_message_v1_equal(received, expected)
```

The error context reports content lengths in UTF-8 bytes rather than the content itself,
so message text never reaches your logs or error reporting.

> **Note:** `MessageV1` mirrors the newer `@solana/offchain-messages` v1 shape (UTF-8
> `content` plus `required_signatories`) and is a distinct type from `Message` above,
> which models the older `@solana/signers` domain form. The v1 wire codec is not yet
> translated, so `received` must come from your own decoding for now.

### `Solana::Ruby::Kit::ResourceLimitEstimation` — `@solana/kit`

Estimate and set compute unit limits and loaded accounts data size limits by simulating
the transaction before sending.

```ruby
RLE = Solana::Ruby::Kit::ResourceLimitEstimation

# 1. Fill provisory (0) limits as placeholders during message construction.
#    This reserves space in the transaction for the limit instructions so the
#    size estimate used by compile_transaction_message is accurate.
msg = RLE.fill_transaction_message_provisory_resource_limits(msg)

# 2. After construction, estimate actual resource usage via simulation and
#    stamp the real values onto the message.
estimator = RLE.estimate_resource_limits_factory(rpc: rpc)
# estimate returns { compute_unit_limit: Integer, loaded_accounts_data_size_limit?: Integer }
estimate = estimator.call(msg)

# 3. Or combine steps 2 + set in one call.
setter  = RLE.estimate_and_set_resource_limits_factory(estimator)
msg     = setter.call(msg)
```

### `Solana::Ruby::Kit::TransactionConfirmation` — `@solana/transaction-confirmation`

Poll for transaction confirmation with timeout.

```ruby
Confirm = Solana::Ruby::Kit::TransactionConfirmation

Confirm.wait_for_confirmation(
  rpc,
  sig,
  commitment:   :confirmed,
  timeout_secs: 60
)
```

### `Solana::Ruby::Kit::InstructionPlans` — `@solana/instruction-plans`

Plan and execute instruction sequences that may span multiple transactions.
The planner packs instructions into messages respecting the 1232-byte transaction
size limit; the executor walks the resulting plan tree and sends each transaction.

```ruby
require 'base64'
Plans = Solana::Ruby::Kit::InstructionPlans
Kit   = Solana::Ruby::Kit

# ── 1. Build an instruction plan ─────────────────────────────────────────────
# Instructions are auto-wrapped in SingleInstructionPlan.
# Use parallel_instruction_plan for instructions that can run concurrently.
plan = Plans.sequential_instruction_plan([ix1, ix2, ix3])

# ── 2. Create a planner ───────────────────────────────────────────────────────
# create_transaction_message is called whenever a new (empty) transaction is
# needed. It must return a message with a fee payer and blockhash already set.
#
# max_instructions_per_transaction caps how many top-level instructions the
# planner packs into a single message. Must be a positive integer no greater
# than 64 (the transaction format's hard limit); defaults to 16, leaving
# headroom for inner (CPI) instructions the planner can't see ahead of time.
planner = Plans.create_transaction_planner(
  create_transaction_message: -> {
    Kit::Functional.pipe(
      Kit::TransactionMessages.create_transaction_message(version: :legacy),
      ->(tx) { Kit::TransactionMessages.set_fee_payer(signer.address, tx) },
      ->(tx) { Kit::TransactionMessages.set_blockhash_lifetime(constraint, tx) }
    )
  },
  max_instructions_per_transaction: 12  # optional; omit for the default of 16
)

# plan! distributes instructions across as few transactions as possible.
# The cap can also be overridden per call:
transaction_plan = planner.call(plan, max_instructions_per_transaction: 8)

# ── 3. Create an executor and run it ─────────────────────────────────────────
# execute_transaction_message receives a fresh, mutable context Hash and each
# fully-packed TransactionMessage, and returns the context a successful result
# should carry. The two serve different outcomes: what you *store* on the context
# reaches a failed or canceled result, what you *return* reaches a successful one
# (merged over what was stored, the returned value winning).
# If it raises, the executor cancels all remaining messages and re-raises — and the
# context as it stood at that moment is preserved on the failed result.
executor = Plans.create_transaction_plan_executor(
  execute_transaction_message: ->(context, message) {
    transaction = Kit::Transactions.compile_transaction_message(message)
    signed      = Kit::Transactions.sign_transaction([signer.key_pair.signing_key], transaction)
    context[:transaction] = signed  # recorded now, so it survives a failure below
    wire = Base64.strict_encode64(Kit::Transactions.wire_encode_transaction(signed))
    rpc.send_transaction(wire)
    { transaction: signed }
  }
)

result = executor.call(transaction_plan)
# result is a TransactionPlanResult tree mirroring the transaction_plan structure.
# Each leaf is a SingleTransactionPlanResult with status :successful, :failed, or :canceled.
# Every status carries a #context; a :successful one also exposes #transaction.

# A one-argument lambda returning { transaction:, context: } — the shape this method
# required before v7.1.0 — is still accepted and adapted onto the flow above.

# ── 3b. Executing every leaf concurrently ────────────────────────────────────
# For work that has no execution dependencies — signing or serializing, say —
# create_transaction_plan_executor_with_concurrent_leaves takes the same callback
# contract but starts every leaf immediately, each on its own thread. It preserves
# the plan's nesting, order and divisibility in the result, supports non-divisible
# sequential plans, and cancels nothing: a leaf that raises does not stop the others,
# so every leaf runs to completion before the failure is reported. Because the leaves
# run at the same time, the callback must be safe to call concurrently with itself.
concurrent = Plans.create_transaction_plan_executor_with_concurrent_leaves(
  execute_transaction_message: ->(_context, message) {
    { transaction: Kit::Transactions.compile_transaction_message(message) }
  }
)
result = concurrent.call(transaction_plan)

# ── 4. Plan types ─────────────────────────────────────────────────────────────
Plans.single_instruction_plan(ix)                      # wrap one instruction
Plans.sequential_instruction_plan([ix1, ix2])          # ordered, divisible
Plans.non_divisible_sequential_instruction_plan([ix1, ix2])  # must be atomic
Plans.parallel_instruction_plan([ix1, ix2])            # any order / same tx

# MessagePacker plans for instructions of variable size (e.g. large data writes)
Plans.get_linear_message_packer_instruction_plan(
  total_length:    data.bytesize,
  get_instruction: ->(offset, length) { build_write_ix(offset, data[offset, length]) }
)
```

### `Solana::Ruby::Kit::WalletStandard` — `@solana/wallet-standard`

Server-side handling of the [Wallet Standard](https://github.com/wallet-standard/wallet-standard)
`signTransaction` interface. A browser wallet (Phantom, Backpack, Solflare, …) signs a
transaction and returns wire bytes; Rails decodes those bytes and verifies every Ed25519
signature without broadcasting — because Solana addresses **are** Ed25519 public keys, no
additional key lookup is required.

Full worked examples: [Verify a Wallet-Signed Transaction in Rails](https://github.com/pzupan/solana-ruby-kit/wiki/Verify-a-Wallet-Signed-Transaction-in-Rails) and [Build a Transaction for Browser Signing](https://github.com/pzupan/solana-ruby-kit/wiki/Build-a-Transaction-for-Browser-Signing).

#### Wallet Standard feature constants

Use these when building frontend metadata or documenting required wallet capabilities:

```ruby
WS = Solana::Ruby::Kit::WalletStandard

WS::SIGN_TRANSACTION          # => 'solana:signTransaction'
WS::SIGN_AND_SEND_TRANSACTION # => 'solana:signAndSendTransaction'
WS::SIGN_MESSAGE              # => 'solana:signMessage'
WS::CONNECT                   # => 'standard:connect'
```

### `Solana::Ruby::Kit::TransactionIntrospection` — `@solana/transaction-introspection`

Decode a confirmed `getTransaction` response and walk its outer and inner (CPI)
instructions — useful for indexers, explorers, or auditing what a transaction
actually did on-chain.

```ruby
TI  = Solana::Ruby::Kit::TransactionIntrospection
rpc = Solana::Ruby::Kit.rpc_client

rpc_tx = rpc.get_transaction(
  signature,
  encoding:                           'base64',
  max_supported_transaction_version: 0
)

# Decodes 'base64', 'base58', or 'json' getTransaction responses.
# `transaction` is only present for 'base64'/'base58' (a re-encodable
# Transactions::Transaction); 'json' responses carry no wire bytes to round-trip.
decoded = TI.decode_transaction_from_rpc_response(rpc_tx)

# Outer instructions only, with account indices resolved to full AccountMetas.
outer = TI.get_instructions_from_compiled_transaction_message(
  decoded.compiled_message,
  decoded.loaded_addresses
)

# Every instruction — outer and inner (CPI) — in the order an explorer
# displays them, each tagged with a `trace` describing its position.
instructions = TI.walk_instructions(
  compiled_message: decoded.compiled_message,
  loaded_addresses: decoded.loaded_addresses,
  meta:             rpc_tx['meta']
)

instructions.each do |traced|
  ix = traced.instruction
  puts "#{traced.trace[:kind]} ix -> #{ix.program_address}"
end
```

> **Note** `'jsonParsed'` responses are not supported — their instructions are
> pre-parsed by the server and lack raw bytes, so they can't be resolved here;
> fetch with `'json'` or `'base64'` instead. Wire-format (`'base64'`/`'base58'`)
> decoding only handles legacy and v0 transactions — Ruby's transaction compiler
> doesn't produce v1 transactions yet either, so there is nothing to decompile
> for that version.

## Error handling

All errors inherit from `Solana::Ruby::Kit::SolanaError`.

```ruby
rescue Solana::Ruby::Kit::SolanaError => e
  puts e.code     # => :SOLANA_ERROR__ADDRESSES__INVALID_BASE58_ENCODED_ADDRESS
  puts e.message  # => human-readable description
  puts e.context  # => Hash of structured context values
end
```

Error codes match the TypeScript `@solana/errors` package constants.

## Type checking with Sorbet

Every public method has a `sig` block. To enable static type checking in your project:

```bash
bundle exec srb init
bundle exec srb tc
```

## Development

```bash
bundle install
bundle exec rspec            # run tests
bundle exec srb tc           # type-check
bundle exec tapioca gems     # regenerate gem RBI files (first time or after gem updates)
```

## License

MIT
