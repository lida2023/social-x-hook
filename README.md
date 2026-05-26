# 🐦 SocialX Hook

> **Your X influence drives your pool.**  
> *The louder you tweet, the cheaper they swap.*

Built for **OKX Build X Hackathon — Hook Track** on **XLayer**.

[![XLayer](https://img.shields.io/badge/XLayer-Chain%20196-green)](https://www.okx.com/xlayer)
[![Uniswap V4](https://img.shields.io/badge/Uniswap-V4%20Hooks-pink)](https://docs.uniswap.org/contracts/v4/overview)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-blue)](https://soliditylang.org)

Follow us: [@SocialXHook](https://x.com/SocialXHook) (your project's X account)
> 🤖 **Fully autonomous**: the keeper agent auto-posts tweets AND reads engagement — zero manual work after setup.

---

## 🎯 Problem

DeFi pools are **silent**. KOLs and creators drive attention on X, but that attention doesn't translate to on-chain value. LPs in a KOL's pool get no benefit from the KOL's social activity.

## 💡 Solution

**SocialX Hook** connects X engagement directly to Uniswap V4 swap fees.

```
Autonomous Agent posts tweets on schedule 🐦
        ↓
   Engagement flows in (likes, RTs, replies)
        ↓
   Agent reads metrics → calculates "social score"
        ↓
   Agent pushes score on-chain → Hook lowers swap fees
        ↓
   More volume → more LP fees → more KOL revenue
        ↓
   Agent tweets about it. Loop 🔁
```

| Social Score | Swap Fee | Effect |
|:---:|:---:|---|
| 🔥 80-100 | 0.01% | Ultra cheap — volume spikes |
| 📈 50-80 | 0.30% | Moderate |
| 😴 0-20 | 1.00% | Baseline |

**KOLs earn 30% of all swap fees** — the better their content, the more they earn.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────┐
│                  X (Twitter)                 │
│  likes · retweets · replies · impressions   │
└──────────────────┬──────────────────────────┘
                   │  X API v2
                   ▼
┌─────────────────────────────────────────────┐
│           Keeper (Node.js)                   │
│  fetchLatestTweet() → calculateScore()       │
│  → batchUpdateScores()                       │
└──────────────────┬──────────────────────────┘
                   │  on-chain tx
                   ▼
┌─────────────────────────────────────────────┐
│         SocialXHook.sol                      │
│                                              │
│  ┌─────────────┐  ┌──────────────────────┐  │
│  │ KOL Registry │  │  Dynamic Fee Engine  │  │
│  │ @handle→addr │  │  score→fee (linear)  │  │
│  └─────────────┘  └──────────────────────┘  │
│                                              │
│  ┌──────────────────────────────────────┐   │
│  │  beforeSwap  → override fee          │   │
│  │  afterSwap   → accumulate KOL share  │   │
│  └──────────────────────────────────────┘   │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│          Uniswap V4 Pool on XLayer           │
│         (PoolManager + SocialXHook)          │
└─────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
social-x-hook/
├── src/
│   └── SocialXHook.sol              # Core hook contract
├── test/
│   └── SocialXHook.t.sol            # Unit + integration tests
├── script/
│   └── DeploySocialXHook.s.sol      # Foundry deploy script
├── keeper/
│   └── index.js                     # X → chain social score keeper
├── foundry.toml                     # Foundry config (XLayer RPC)
├── remappings.txt                   # Solidity import aliases
├── .env.example                     # Environment template
└── README.md                        # This file
```

---

## 🚀 Quick Start

### Prerequisites

- Node.js 18+
- X/Twitter account
- [X API Free tier app](https://developer.twitter.com) (Read + Write permissions)
- OKB for gas on XLayer

### 1. Get X API Credentials (5 min)

Go to [developer.twitter.com](https://developer.twitter.com) → create a **Free** tier project → generate:

- **API Key & Secret** (OAuth 1.0a)
- **Access Token & Secret** (Read + Write)
- **Bearer Token**

### 2. Configure & Deploy

```bash
cd social-x-hook
cp .env.example .env
# Edit .env → fill in your credentials
./setup.sh
```

### 3. Launch the Autonomous Agent

```bash
cd keeper && npm start
```

**That's it.** The agent will:
- 🐦 Auto-post tweets on schedule (8 queued, loops)
- 📊 Read engagement (likes/RTs/replies)
- 📈 Calculate social scores
- ⛓️ Push scores on-chain → fees update in real-time

No manual tweeting. No manual anything. Just let it run.

> 💡 Test first: `DRY_RUN=true npm start` — simulates everything without real txs/posts.

---

## 🔑 Key Design Decisions

| Decision | Why |
|----------|-----|
| **Linear fee curve** | Simple, predictable, no cliff effects. Score 50 = exactly halfway between min/max fee |
| **Keeper model (not oracle)** | Hackathon-scope: a single JS script is practical. Prod-ready: upgrade to Chainlink Functions or a decentralized keeper network |
| **30% KOL fee share** | High enough to incentivize content creation, low enough that LPs still profit |
| **`beforeSwap` dynamic fee** | True Uniswap V4 dynamic fee — fee changes take effect immediately, no pool migration |
| **Handle on-chain** | Immutable proof of X identity. Enables reverse lookup for third-party UIs |
| **Batch score updates** | Gas-efficient for keeper — update all KOLs in one tx |

---

## 🧪 Future Roadmap

- [ ] **Chainlink Automation** — Decentralized keeper via Chainlink upkeep
- [ ] **Multi-platform** — Support Farcaster, Lens, TikTok metrics
- [ ] **DAO-governed params** — KOL fee share + weightings voted by token holders
- [ ] **Leaderboard UI** — Real-time dashboard of top KOL pools by volume
- [ ] **flapdotsh integration** — Native social oracle for decentralized score feeds

---

## 🌐 XLayer Network Info

| Parameter | Value |
|-----------|-------|
| Chain ID | 196 |
| RPC | `https://rpc.xlayer.tech` |
| Explorer | https://www.oklink.com/x-layer |
| Currency | OKB |
| Tech Stack | Polygon CDK (zkEVM) |

---

## 📣 Hackathon Submission Checklist

- [x] Uniswap V4 Hook contract deployed on XLayer
- [x] Dynamic fee overridden in `beforeSwap`
- [x] Social signal → on-chain via keeper
- [x] X handle stored on-chain
- [x] KOL creator economy (fee share)
- [x] Project X account: [@SocialXHook](https://x.com/SocialXHook)
- [x] Tweets tagging @XLayerOfficial @Uniswap @flapdotsh
- [x] Google Form submitted before May 28 23:59 UTC

---

## 👤 Team

Built with ❤️ + AI for **OKX Build X Hackathon — Hook Track**.

*The best time to provide liquidity was yesterday. The best time to tweet about it is now.*
