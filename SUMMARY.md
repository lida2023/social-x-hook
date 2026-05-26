# SocialX Hook - 项目总结

> OKX Build X Hackathon - Hook Track  
> 当前状态：已从“独立合约”修正为“真实 Uniswap v4 beforeSwap Hook”

---

## 一、项目定位

**SocialX Hook** 将 X/Twitter 互动量转成 Uniswap v4 动态手续费：

```text
手动发推 -> Keeper 读取互动 -> 链上 social score 更新 -> beforeSwap 返回动态 LP fee
```

核心卖点是把赛事要求的 X 运营变成产品机制本身。互动越高，KOL 对应池子的 swap fee 越低。

---

## 二、关键修正

之前版本为了绕开 PoolManager 部署问题，把合约退成了独立 registry 合约。这会导致 Hook Track 的核心不成立，因为它没有实现 `IHooks`，也没有 `beforeSwap`。

本轮修正：

| 项目 | 当前实现 |
| --- | --- |
| Hook 类型 | `SocialXHook` 实现 Uniswap v4 `IHooks` |
| Hook 回调 | `beforeSwap` 返回 `fee | OVERRIDE_FEE_FLAG` |
| 地址权限 | 构造函数校验 `BEFORE_SWAP_FLAG` |
| Pool 要求 | 池子必须使用 `LPFeeLibrary.DYNAMIC_FEE_FLAG` |
| X 发推 | 手动发推，避免依赖 X API Write 权限 |
| Keeper | 只读 X API 指标，然后调用 `batchUpdateScores()` |
| KOL 分成 | 暂列 roadmap，不在本版冒充已完成 |

---

## 三、技术架构

### 合约 `src/SocialXHook.sol`

- KOL 注册：地址绑定 X handle
- Keeper 管理：owner 添加/移除 keeper
- 社交分数：keeper 更新 0-100 分
- 动态费率：score 0 -> 1.00%，score 100 -> 0.01%
- v4 Hook：`beforeSwap` 从 `hookData` 读取 KOL 地址并返回 LP fee override

### Keeper `keeper/index.js`

- 从项目根目录 `.env` 读取配置
- 通过 X API v2 Bearer Token 读取公开推文指标
- 使用 likes / retweets / replies / quotes 算分
- 根据 `handleToAddress()` 找链上 KOL 地址
- 批量调用 `batchUpdateScores()`
- `DRY_RUN=true` 时只模拟，不发交易

### 部署 `script/Deploy.s.sol`

- 需要 `.env` 提供 `POOL_MANAGER`
- 部署 `HookDeployer`
- 离线搜索 CREATE2 salt
- 确保 hook 地址低 14 位只启用 `BEFORE_SWAP_FLAG`
- 部署 `SocialXHook(poolManager, deployer)`

---

## 四、文件清单

```text
social-x-hook/
├── src/SocialXHook.sol
├── test/SocialXHook.t.sol
├── script/Deploy.s.sol
├── keeper/
│   ├── index.js
│   └── package.json
├── .env.example
├── setup.sh
├── TWEETS.md
├── README.md
└── docs/superpowers/
```

---

## 五、验证状态

已通过 focused v4 Hook 测试：

```text
forge test --match-path test/SocialXHook.t.sol -vvv
16 passed, 0 failed
```

覆盖点：

- 构造函数保存 owner / PoolManager
- Hook 地址具备 `BEFORE_SWAP_FLAG`
- KOL 注册和 handle 唯一性
- Keeper 更新 / 批量更新分数
- `beforeSwap` 非 PoolManager 调用会 revert
- `beforeSwap` 对 active KOL 返回动态 override fee
- `beforeSwap` 无 KOL 数据时返回默认 override fee
- v4 dynamic-fee pool 可用该 hook 初始化

---

## 六、当前 X Layer testnet 部署

| 项目 | 地址 / 值 |
| --- | --- |
| Network | X Layer testnet |
| Chain ID | `1952` |
| Deployer / owner / keeper | `0xE2B76789984CE017B11d076Bc06Db658476A09F1` |
| PoolManager | `0x72aFaF53dEA92A2174cb4972DE8Ad137Ce8A39A5` |
| SocialXHook | `0x28cA4FBd778F9aAe963ee5E7dF9c3666d1eB8080` |
| Hook flag | `0x80` (`BEFORE_SWAP_FLAG`) |
| KOL handle | `@guiyan16` |
| KOL 注册交易 | `0x1c411bcdcc4a3321020bee249a5255beabca89dd270b285c284c1d1c6a6b9d53` |
| Demo PoolId | `0xbbd624df752d0d9d3e3bd7c7b424b44f48d44bbe425f5f21901808a051e0e761` |
| Demo pool 初始化交易 | `0x2332192f774c92993e2e167f13b3b769407b9e9d99693d96208455890232309b` |

Demo pool 使用两个脚本部署的 ERC20：

```text
currency0 = 0x29801ABFFab00F859E495Fef04b7f6B508A73dFF
currency1 = 0xf9E668C10Df3d914523e8c001BC469749b9aD45F
fee       = 8388608 (LPFeeLibrary.DYNAMIC_FEE_FLAG)
spacing   = 60
sqrtPrice = 79228162514264337593543950336
```

主网部署路径已准备好，官方 X Layer mainnet PoolManager 为 `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32`，但当前暂停在 mainnet OKB gas。

---

## 七、下一步操作

1. 推送 GitHub 公开仓库：

```bash
gh auth login
gh repo create social-x-hook --public --source . --remote origin --push
```

如果本机没有 GitHub CLI：

```bash
# 先在 https://github.com/new 创建公开空仓库 social-x-hook
git remote add origin git@github.com:lida2023/social-x-hook.git
git push -u origin main
```

2. 把 `SUBMISSION.md` 中的 GitHub 链接和最终 X 发帖链接补齐。
3. 从 `TWEETS.md` 手动发提交确认推文。
4. 提交 Google Form。
5. 如后续拿到 X Layer mainnet OKB，再切换到 mainnet：

```text
XLAYER_RPC_URL=https://rpc.xlayer.tech
POOL_MANAGER=0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32
```

测试网 keeper 单次运行：

```bash
RUN_ONCE=true node keeper/index.js
```

---

## 八、风险提示

当前提交走 X Layer testnet fallback。Keeper 在本环境里能完成单轮运行，但 X API 请求返回 fetch failed，因此没有伪造互动分，也没有强行推非真实分数。
