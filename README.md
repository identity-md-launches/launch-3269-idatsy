# Idatsy (IDATSY)

Idatsy is a fixed supply ERC-20. Its constructor mints all **1,000,000,000 IDATSY**
to the immediate deployer, once. It uses the vendored OpenZeppelin Contracts
v5.1.0 ERC-20 implementation without changing its transfer or approval behavior.

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `Idatsy` |
| Source / artifact selector | `src/Idatsy.sol:Idatsy` |
| Name | `Idatsy` |
| Symbol | `IDATSY` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Base-unit supply / `INITIAL_SUPPLY` | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Constructor `msg.sender` |
| Native currency sent on deployment | `0` |
| Application contracts | None |
| Target specified by the assignment | Robinhood Chain, chain ID `4663` |
| Compiler | Solidity `0.8.26` |
| Build settings | Paris EVM, optimizer enabled, 200 runs, `bytecode_hash = "none"` |

The deployment artifact is `out/Idatsy.sol/Idatsy.json`. Deploy its creation
bytecode without constructor data. The constructor requires no external contracts,
addresses, configuration, or initialization calls. The Paris target avoids
requiring newer EVM opcodes; the token has no chain-specific dependencies, block
number assumptions, timers, or oracles.

When a factory deploys Idatsy, **the factory receives the entire supply**. A caller
of the factory, transaction origin, or intermediary does not receive it. A helper
contract that deploys the token must therefore be able to distribute its balance.
There is no post-deployment minting, burning, owner, pause, blacklist, seizure,
tax, upgrade mechanism, or supply-changing entry point.

## Behavior and assumptions

The unspecified transfer rules are interpreted as standard ERC-20 behavior with
no transfer fees or restrictions beyond balance, allowance, and zero-address
validation. Each successful transfer delivers its exact amount. Zero-amount
transfers and self-transfers succeed for valid addresses and emit `Transfer`.
Sending tokens to the zero address reverts, including a zero-amount transfer.

`approve` replaces the allowance and emits `Approval`. `transferFrom` requires
the caller's allowance, including when the caller is also the holder. A finite
allowance decreases by the amount spent; `type(uint256).max` represents an
unlimited allowance and is not decreased. The inherited implementation emits
`Transfer`, but does not emit `Approval` for allowance consumption. Failures revert
with ERC-6093 custom errors and roll back balances and allowances.

Transfers make no external calls and do not notify recipient contracts. Holders
must check recipients before sending: there is no administrator or rescue method
to recover tokens sent to an unusable address, including this token contract.
Ordinary native-currency payments revert; forced native-currency transfers are
not recoverable either. The token does not implement permit or signed approvals.

## Launch responsibilities

This project supplies the token bytecode. The launch system is responsible for
the manifest, deployment transaction, distribution, pool creation and source
verification. No transaction has been broadcast by this project. The following
values come from the assignment and are not enforced inside the token:

| Launch setting | Assignment value |
| --- | --- |
| Pair | Native ETH |
| Pool fee | `12500` (1.25%; a pool fee, not a token transfer tax) |
| Tick spacing | `60` |
| Pool initialPrice provenance value | `79228162514264337593543950336` |
| Swarm allocation | 10%, sent by the factory to its MerkleDistributor |
| `economics.poolBps` | `8800` (88% of total supply) |
| `economics.initialMarketCapWei` | `10000000000000000000` (10 ETH) |
| `economics.remainderTo` | `0xd3959c80d11b4d2841fda01de9a0d9b36c52217e` |
| Remainder allocation | 2% of total supply |

The launch system derives the actual opening pool price from the initial market
cap, supply and token address. These allocation and pool settings are the launch
system's operations after minting; the constructor itself distributes nothing.
The manifest belongs to the subsequent launch step and is not included here.
Test factory and pool addresses are local fixtures only and are not deployment
parameters.

### After launch

There are no owner settings, setters, keepers, or initialization transactions.
The launch operator should verify the deployed source and metadata, the sole
constructor mint event, total supply, and actual distribution receipts. Holders
control their transfers and approvals. Integrations should query allowances
directly, and approval interfaces should account for the standard allowance
replacement race: revoke a prior allowance and confirm revocation before setting
a replacement. Unlimited approval gives the spender access to future balances
until revoked.

The deployment review remains responsible for the launch factory, distributor,
and AMM integration. The local suite tests representative distribution and
pool-facing token transfers; it does not run a live-chain fork or a full AMM.
The supplied protected harness performs the separate launch integration checks.

## Build and checks

All Solidity dependencies and their licenses are ordinary files in `lib/`, with
versions and integrity hashes described in [DEPENDENCIES.md](DEPENDENCIES.md).
Once Foundry and the pinned compiler are installed, no network, package install,
submodule, RPC, wallet, or environment configuration is needed to build or test.
No FFI or filesystem permissions are enabled.

Run at the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x5969f3ab42539bf851a380edb98bdcc0d386822f311eb41fe4d5011a4e2fe801 forge test
forge fmt --check
```

The seed is an optional command-level test reproducibility setting; tests do not
read or modify environment variables. Without it, `forge test` also works.

`test/Idatsy.t.sol` covers constructor minting and events, factory/CREATE2
deployment, metadata, transfers, approvals, finite and unlimited allowances,
zero and self-transfers, invalid recipients, insufficient balances and allowances,
failure atomicity, launch allocation flows, native-currency rejection, and absent
administrative entry points. Six fuzz tests run 1,000 cases each.

`test/Idatsy.invariant.t.sol` runs three invariants over randomized sequences of
transfers, approvals, delegated spending, overdraws and unauthorized spending.
An independent model tracks four holders and every allowance pair. Each invariant
runs 128 sequences of up to 64 calls, checking fixed supply, balance conservation,
and allowance accounting. Expected failures are checked explicitly; unexpected
handler reverts fail the suite.

This is local implementation and testing, not an independent security audit.
Slither and Mythril have not been run. Independent adversarial and deployment
review remain release responsibilities.
