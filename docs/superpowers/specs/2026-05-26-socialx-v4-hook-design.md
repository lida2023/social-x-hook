# SocialX v4 Hook Design

Date: 2026-05-26
Project: SocialX Hook
Goal: Convert the current standalone social-score contract into a real Uniswap v4 dynamic-fee hook for the OKX Build X Hook Track.

## Problem

The current project has a strong product idea: X engagement changes swap fees. The implementation does not yet satisfy the Hook Track's core technical requirement because `SocialXHook.sol` is a standalone registry contract, not a Uniswap v4 hook. It does not implement `IHooks`, does not expose `beforeSwap`, and cannot be called by a v4 `PoolManager`.

The README also claims behavior that the code does not provide, including automatic X posting, `beforeSwap` fee overrides, and KOL fee sharing. The new design makes the code and docs honest while preserving the social-to-fee product loop.

## Goals

1. Implement a true Uniswap v4 hook that uses `beforeSwap` to return a dynamic LP fee override.
2. Keep the X engagement keeper model: off-chain read-only X API metrics produce on-chain social scores.
3. Keep KOL identity and score state on-chain.
4. Make tests prove the v4 hook path, not only standalone registry behavior.
5. Keep deployment practical for XLayer by deploying the hook against an existing v4 `PoolManager` when one is provided.

## Non-Goals

1. Do not implement production-grade KOL fee extraction in the first pass. Correct v4 custom accounting is more complex than needed for the hackathon core.
2. Do not rely on X API write access. Tweets are manual; the keeper only reads engagement and pushes scores.
3. Do not deploy `PoolManager` on XLayer as the main happy path. Use an existing official or activity-provided manager address when available.
4. Do not add a frontend unless the core hook, keeper, tests, and docs are already solid.

## Architecture

`SocialXHook.sol` becomes a compact `IHooks` implementation. It imports v4-core interfaces and libraries directly:

- `IHooks`
- `IPoolManager`
- `PoolKey`
- `BeforeSwapDelta` and `BeforeSwapDeltaLibrary`
- `LPFeeLibrary`
- `Hooks`

The hook stores:

- immutable `owner`
- immutable `poolManager`
- `KOL` records keyed by wallet address
- `handleToAddress`
- keeper allowlist

The constructor validates that the deployed hook address has the required v4 permission bit for `BEFORE_SWAP_FLAG`. This catches invalid deployments early. The deployment script is responsible for mining or selecting a salt so the hook address has the correct low bits.

## Hook Behavior

The pool is expected to be created with `LPFeeLibrary.DYNAMIC_FEE_FLAG`.

`beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata hookData)`:

1. Allows calls only from `poolManager`.
2. Decodes `hookData` as an address when at least 20 bytes are provided.
3. Looks up that KOL's social score.
4. Computes the LP fee from the score.
5. Returns:
   - `IHooks.beforeSwap.selector`
   - `BeforeSwapDeltaLibrary.ZERO_DELTA`
   - `computedFee | LPFeeLibrary.OVERRIDE_FEE_FLAG`

If `hookData` is empty, invalid, or points to an inactive KOL, the hook returns `DEFAULT_FEE | OVERRIDE_FEE_FLAG`.

Unused hook functions required by `IHooks` revert with `HookNotImplemented`. They should not be called because the hook address only opts into `beforeSwap`.

## Fee Curve

Use Uniswap v4 fee units: hundredths of a bip, where 1,000,000 equals 100%.

Initial curve:

- score 0: `MAX_FEE = 10000` (1.00%)
- score 100: `MIN_FEE = 100` (0.01%)
- linear interpolation between them

This preserves the existing product message and keeps test expectations simple.

## Keeper

The existing Node keeper remains the off-chain bridge:

1. Reads latest public X post metrics through X API v2 bearer token.
2. Computes score from likes, retweets, replies, and quotes.
3. Resolves X handle to KOL address through `handleToAddress`.
4. Calls `batchUpdateScores(address[], uint256[])`.

The keeper should be updated to remove auto-posting claims from logs and comments. It may keep dry-run mode and the scoring code.

## Deployment

Deployment is split into two concerns:

1. Hook deployment:
   - Read `POOL_MANAGER` from `.env`.
   - Deploy `SocialXHook(poolManager, deployer)` at an address with `BEFORE_SWAP_FLAG`.
   - Print `HOOK_ADDRESS`.

2. Local/test integration:
   - Tests can deploy a local `PoolManager`.
   - Tests may use Foundry `vm.etch` or a helper deployer to place code at a flag-valid hook address.

If a production-grade salt miner is too large for this pass, the first implementation can include a simple deterministic deploy script and a documented manual fallback. The core requirement is that tests and deployment guidance reflect the address-bit constraint.

## Documentation

README, SUMMARY, `.env.example`, `setup.sh`, and `TWEETS.md` must be updated to match reality:

- "Manual tweets, read-only keeper"
- "True Uniswap v4 beforeSwap dynamic-fee hook"
- "KOL revenue share is roadmap/demo, not live fee extraction"
- "Use XLayer testnet or mainnet according to hackathon rules"
- "Provide `POOL_MANAGER` when deploying to XLayer"

## Testing

Tests should cover:

1. Constructor stores owner and PoolManager and validates hook permissions.
2. Keeper allowlist add/remove behavior.
3. KOL registration and handle uniqueness.
4. Score update and batch score update.
5. Fee calculation for score 0, 50, and 100.
6. `beforeSwap` reverts when caller is not the PoolManager.
7. `beforeSwap` returns the selector, zero delta, and override fee for an active KOL.
8. `beforeSwap` returns default override fee for missing or inactive KOL data.
9. A v4 dynamic-fee pool test proves that the hook can be used with a `PoolKey` using `LPFeeLibrary.DYNAMIC_FEE_FLAG`.

## Risks

The main risk is hook address mining. v4 decides which callbacks to invoke from the low bits of the hook address. A normal deployment address will usually be invalid. The implementation must either mine a salt for CREATE2 deployment or make the requirement impossible to miss through constructor validation, tests, and deployment docs.

The second risk is overbuilding fee sharing. Fee extraction is intentionally deferred so the project can ship a credible Hook Track submission first.
