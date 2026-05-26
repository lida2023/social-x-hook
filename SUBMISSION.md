# SocialX Hook Submission Notes

## Form Fields

- Project name: SocialX Hook
- Official X account followed: yes, submitter should confirm from the active X account before sending the form.
- Team X account: `@guiyan16`
- Telegram: `@guiyan16`
- GitHub: `https://github.com/lida2023/social-x-hook`
- X post link: `https://x.com/guiyan16/status/2059341489365545056?s=20`

```bash
gh auth login
gh repo create social-x-hook --public --source . --remote origin --push
```

Without GitHub CLI:

1. Open `https://github.com/new`.
2. Create a public empty repo named `social-x-hook`; do not add README, `.gitignore`, or license in the UI.
3. Push this already-committed local repo:

```bash
git remote add origin git@github.com:lida2023/social-x-hook.git
git push -u origin main
```

## Project Highlights

SocialX Hook is a real Uniswap v4 `beforeSwap` hook on X Layer testnet. It turns X engagement into an on-chain social score, then maps that score to a dynamic LP fee override. KOLs register their X handle on-chain, a read-only keeper collects public X metrics, and swaps can pass the KOL wallet in `hookData` to receive the fee selected by the hook.

Key points:

- Implements `IHooks` and validates the hook address permission bits.
- Uses `beforeSwap` to return `fee | LPFeeLibrary.OVERRIDE_FEE_FLAG`.
- Uses a dynamic-fee pool (`LPFeeLibrary.DYNAMIC_FEE_FLAG`).
- Keeps X posting manual; the keeper only reads public engagement and pushes scores.
- Does not claim production KOL revenue share; that remains roadmap.

## X Layer Testnet Deployment

- Network: X Layer testnet
- Chain ID: `1952`
- RPC: `https://testrpc.xlayer.tech/terigon`
- Deployer / owner / keeper: `0xE2B76789984CE017B11d076Bc06Db658476A09F1`
- PoolManager: `0x72aFaF53dEA92A2174cb4972DE8Ad137Ce8A39A5`
- SocialXHook: `0x28cA4FBd778F9aAe963ee5E7dF9c3666d1eB8080`
- Hook flags: `0x80` (`BEFORE_SWAP_FLAG`)

KOL registration:

- Handle: `@guiyan16`
- Wallet: `0xE2B76789984CE017B11d076Bc06Db658476A09F1`
- Registration tx: `0x1c411bcdcc4a3321020bee249a5255beabca89dd270b285c284c1d1c6a6b9d53`
- `totalKolsRegistered()`: `1`

Demo v4 pool:

- Token A: `0x29801ABFFab00F859E495Fef04b7f6B508A73dFF`
- Token B: `0xf9E668C10Df3d914523e8c001BC469749b9aD45F`
- Currency0: `0x29801ABFFab00F859E495Fef04b7f6B508A73dFF`
- Currency1: `0xf9E668C10Df3d914523e8c001BC469749b9aD45F`
- Fee: `8388608` (`LPFeeLibrary.DYNAMIC_FEE_FLAG`)
- Tick spacing: `60`
- Sqrt price X96: `79228162514264337593543950336`
- Initial tick: `0`
- PoolId: `0xbbd624df752d0d9d3e3bd7c7b424b44f48d44bbe425f5f21901808a051e0e761`
- Pool initialize tx: `0x2332192f774c92993e2e167f13b3b769407b9e9d99693d96208455890232309b`

## Verification Snapshot

- `forge test -vvv`: 16 tests passed.
- `forge build`: compiler run successful.
- `node --check keeper/index.js`: passed.
- `handleToAddress("@guiyan16")`: `0xE2B76789984CE017B11d076Bc06Db658476A09F1`.
- `getKOL(deployer)`: `("@guiyan16", 0, registeredAt, true)`.
- `DRY_RUN=true RUN_ONCE=true node keeper/index.js`: exited after one cycle.
- `DRY_RUN=false RUN_ONCE=true node keeper/index.js`: exited after one cycle; X fetch failed in this environment, so no score was fabricated or pushed.

## Mainnet Note

The implementation is ready for X Layer mainnet deployment with the official PoolManager `0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32`. Mainnet deployment is pending X Layer mainnet OKB for gas.
