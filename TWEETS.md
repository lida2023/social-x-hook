# 🐦 SocialX Hook — Tweet Schedule

> **Manual posting schedule.**
> X API write access is not required. Post these manually, then the keeper reads engagement and pushes scores on-chain.
> 
> 赛事要求：提交时 @XLayerOfficial @Uniswap @flapdotsh，赛事期间持续运营发推
> 策略：每天 2-3 条，混搭「产品介绍 + 技术亮点 + 互动话题」
> 
> Keeper 只负责读取互动和更新分数，不负责自动发推。

---

## Day 1 — 项目亮相 (5/26)

### 推文 1：官宣参赛
```
🚀 Building on @XLayerOfficial for the Build X Hackathon!

Introducing SocialX Hook — the first Uniswap V4 Hook that connects your X influence directly to on-chain swap fees.

The louder you tweet, the cheaper your pool trades. 🐦

@Uniswap @flapdotsh
#BuildXHackathon #XLayer #UniswapV4
```
👉 *附上合约截图或架构图*

### 推文 2：问题 & 痛点
```
DeFi pools are SILENT 🤫

KOLs drive attention on X, but that signal rarely reaches on-chain liquidity. LPs still trade with static pool parameters.

SocialX Hook fixes this: your tweets → on-chain score → dynamic V4 fee → cheaper swaps when attention spikes.

Retweet if this resonates 🔁
@XLayerOfficial @Uniswap @flapdotsh
```

### 推文 3：技术亮点（深夜）
```
🛠️ Tech deep dive:

SocialX Hook uses @Uniswap V4's `beforeSwap` hook to override LP fees dynamically based on a "social score" (0-100).

Score = f(likes, retweets, replies) → pushed on-chain by a lightweight keeper → fee adjusts instantly.

Read-only keeper, on-chain score, real V4 fee override. Simple and demoable. ✨

@XLayerOfficial @flapdotsh
```

---

## Day 2 — Demo + 互动 (5/27)

### 推文 4：Demo 视频/截图
```
🎥 Watch SocialX Hook in action:

1. Tweet → score goes up 📈
2. Pool fee drops from 1% → 0.01% ⚡
3. Swaps get cheaper instantly

Your social presence now has on-chain consequences 🐦⛓️

@XLayerOfficial @Uniswap @flapdotsh
#DeFi #Web3Social
```
👉 *附上 Demo 视频/GIF*

### 推文 5：互动投票
```
💭 Which KOL niche would benefit most from SocialX Hook?

• Crypto traders 📊
• NFT artists 🎨  
• Gaming streamers 🎮
• DeFi educators 📚

Vote below + tag your favorite creator who should launch a SocialX pool 👇

@XLayerOfficial @Uniswap @flapdotsh
```

### 推文 6：深夜技术对比
```
Why Uniswap V4 Hooks > V3?

V3: Static fees. Pool creator sets fee once, never changes.
V4 + SocialX Hook: Dynamic fees. Change per-block based on external signals.

This is the killer feature of V4 — hooks make pools PROGRAMMABLE, not just parameterized.

🧵 1/3 — more in the next tweet
@Uniswap @flapdotsh
```

---

## Day 3 — 提交日 (5/28)

### 推文 7：提交确认
```
✅ Submitted SocialX Hook to the @XLayerOfficial Build X Hackathon!

Contract deployed on XLayer testnet (Chain 1952) 🏗️
Keeper running ⚡
Dynamic fees live 🔥

What we built:
• beforeSwap fee override based on X engagement
• read-only keeper that pushes X engagement scores on-chain
• on-chain social identity (X handle → wallet)

Hook: 0x28cA4FBd778F9aAe963ee5E7dF9c3666d1eB8080
PoolId: 0xbbd624df752d0d9d3e3bd7c7b424b44f48d44bbe425f5f21901808a051e0e761
Repo: https://github.com/lida2023/social-x-hook

@Uniswap @flapdotsh
```

### 推文 8：感谢 + 呼吁
```
🏆 Last tweet before the deadline!

Thanks @XLayerOfficial for the opportunity, @Uniswap for the incredible V4 hooks architecture, and @flapdotsh for pushing social × DeFi forward.

If you believe social signals belong on-chain, give us a follow @[your_handle] and RT this 🚀

LFG! 💪
```

---

## 📋 发推 Checklist

- [ ] 每条推文至少 @ 其中 2 个官号
- [ ] 配图/视频 > 纯文字（Engagement 更高）
- [ ] 用 #BuildXHackathon #XLayer #UniswapV4 标签
- [ ] 保持每天至少 2 条
- [ ] 最后一天确认已提交 Google Form
