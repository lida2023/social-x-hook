# SocialX Hook

X engagement drives Uniswap v4 swap fees on XLayer.

Built for the OKX Build X Hackathon Hook Track.

## Current Testnet Deployment

SocialX Hook is deployed and smoke-tested on X Layer testnet:

| Item | Value |
| --- | --- |
| Network | X Layer testnet |
| Chain ID | `1952` |
| PoolManager | `0x72aFaF53dEA92A2174cb4972DE8Ad137Ce8A39A5` |
| SocialXHook | `0x28cA4FBd778F9aAe963ee5E7dF9c3666d1eB8080` |
| Hook flags | `0x80` (`BEFORE_SWAP_FLAG`) |
| Registered KOL | `@guiyan16` -> `0xE2B76789984CE017B11d076Bc06Db658476A09F1` |
| Demo PoolId | `0xbbd624df752d0d9d3e3bd7c7b424b44f48d44bbe425f5f21901808a051e0e761` |
| X post | `https://x.com/guiyan16/status/2059341489365545056?s=20` |

The mainnet deployment path is ready, but is pending X Layer mainnet OKB for gas.

## What It Does

SocialX Hook connects public X activity to a Uniswap v4 dynamic-fee pool:

```text
manual tweet -> X engagement -> keeper reads metrics -> score on-chain -> beforeSwap returns lower fee
```

KOLs register an X handle on-chain. A read-only keeper watches those handles, computes a 0-100 social score, and updates the hook. During swaps, callers pass the target KOL address in `hookData`; the hook returns a Uniswap v4 LP fee override based on that score.

## Current Scope

Implemented:

- Real Uniswap v4 `IHooks` contract
- `beforeSwap` dynamic LP fee override
- Hook address permission validation for `BEFORE_SWAP_FLAG`
- On-chain KOL handle registry
- Keeper allowlist for score updates
- Batch score updates
- Read-only X metrics keeper
- Foundry tests for registry behavior, hook behavior, and dynamic-fee pool initialization

Not implemented in this pass:

- Automatic X posting
- Production KOL fee sharing / custom accounting
- Frontend dashboard

KOL revenue sharing remains a roadmap item. The hackathon core is the true v4 Hook path.

## Fee Curve

Uniswap v4 LP fees are measured in hundredths of a bip:

| Social score | LP fee |
| ---: | ---: |
| 0 | 1.00% |
| 50 | 0.505% |
| 100 | 0.01% |

Formula:

```text
fee = MAX_FEE - score * (MAX_FEE - MIN_FEE) / 100
```

## Architecture

```text
X public metrics
       |
       v
keeper/index.js
  - reads latest tweets
  - scores likes / retweets / replies / quotes
  - calls batchUpdateScores()
       |
       v
SocialXHook.sol
  - KOL registry
  - keeper score updates
  - beforeSwap dynamic fee override
       |
       v
Uniswap v4 PoolManager dynamic-fee pool
```

The pool must be created with `LPFeeLibrary.DYNAMIC_FEE_FLAG`. The hook must be deployed to an address whose low bits match `BEFORE_SWAP_FLAG`; `script/Deploy.s.sol` mines a CREATE2 salt for that.

## Project Structure

```text
social-x-hook/
├── src/SocialXHook.sol
├── test/SocialXHook.t.sol
├── script/Deploy.s.sol
├── keeper/index.js
├── setup.sh
├── TWEETS.md
├── SUMMARY.md
└── docs/superpowers/
```

## Setup

Copy the environment template:

```bash
cp .env.example .env
```

Required values:

```text
PRIVATE_KEY=...
POOL_MANAGER=...
TRACKED_KOLS=@your_handle
```

Optional but needed for real X metrics:

```text
X_BEARER_TOKEN=...
```

Use `DRY_RUN=true` to simulate keeper updates without sending transactions.

## Test

```bash
forge test -vvv
node --check keeper/index.js
```

## Deploy

`POOL_MANAGER` must point to the Uniswap v4 PoolManager on the target XLayer network.

```bash
./setup.sh
```

The deploy script:

1. Deploys a small CREATE2 helper.
2. Mines a salt whose predicted hook address has `BEFORE_SWAP_FLAG`.
3. Deploys `SocialXHook(poolManager, deployer)`.
4. Writes `HOOK_ADDRESS` back to `.env`.

## Run Keeper

Register the same handle on-chain first, then start:

```bash
cd keeper
npm start
```

For simulation:

```bash
DRY_RUN=true npm start
```

## Posting

Tweets are manual. Use `TWEETS.md` as the schedule and tag the required hackathon accounts. The keeper only reads public engagement after tweets are posted.

## Roadmap

- KOL fee-share custom accounting
- Dashboard / leaderboard
- Multi-platform scoring
- Decentralized keeper or oracle path
