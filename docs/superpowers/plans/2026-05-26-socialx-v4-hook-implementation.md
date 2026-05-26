# SocialX v4 Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the standalone SocialX registry contract with a real Uniswap v4 `beforeSwap` dynamic-fee hook while preserving the X engagement keeper loop.

**Architecture:** `SocialXHook.sol` implements `IHooks`, validates the `BEFORE_SWAP_FLAG` address permission, and returns per-swap LP fee overrides from KOL scores. Tests deploy the hook to a flag-valid address using Foundry `deployCodeTo`, then exercise registry behavior, direct `beforeSwap`, and a minimal v4 `PoolManager.initialize` dynamic-fee pool path.

**Tech Stack:** Solidity 0.8.26, Foundry, Uniswap v4-core, Node.js keeper with ethers v6.

---

## File Structure

- Modify `src/SocialXHook.sol`: true v4 hook, KOL registry, keeper score updates, `beforeSwap`.
- Modify `test/SocialXHook.t.sol`: TDD coverage for hook permissions, direct `beforeSwap`, and v4 dynamic-fee pool initialization.
- Modify `script/Deploy.s.sol`: deploy helper + salt miner for a hook address whose low bits match `BEFORE_SWAP_FLAG`.
- Modify `keeper/index.js`: remove auto-post claims from runtime behavior and update ABI tuple.
- Modify `.env.example`, `README.md`, `SUMMARY.md`, `TWEETS.md`, `setup.sh`: align docs and setup with manual tweets, read-only keeper, and true v4 hook deployment.

---

### Task 1: Contract Tests First

**Files:**
- Modify: `test/SocialXHook.t.sol`
- Later modify: `src/SocialXHook.sol`

- [ ] **Step 1: Replace the existing test setup with a flag-valid hook deployment**

Use this shape:

```solidity
import {PoolManager} from "v4-core/PoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG));

function setUp() public {
    manager = new PoolManager(owner);
    deployCodeTo(
        "SocialXHook.sol:SocialXHook",
        abi.encode(address(manager), owner),
        hookAddress
    );
    hook = SocialXHook(hookAddress);
}
```

- [ ] **Step 2: Add failing tests for new hook behavior**

Add tests with these names:

```solidity
function test_ConstructorStoresPoolManagerAndOwner() public;
function test_HookAddressHasBeforeSwapPermission() public;
function test_BeforeSwapRevertsWhenCallerIsNotPoolManager() public;
function test_BeforeSwapReturnsOverrideFeeForActiveKOL() public;
function test_BeforeSwapReturnsDefaultOverrideFeeWithoutKOLData() public;
function test_CanInitializeV4DynamicFeePoolWithHook() public;
```

Use direct `beforeSwap` calls for fee assertions:

```solidity
vm.prank(address(manager));
(bytes4 selector, BeforeSwapDelta delta, uint24 fee) =
    hook.beforeSwap(address(this), key, params, abi.encode(kol));

assertEq(selector, IHooks.beforeSwap.selector);
assertEq(BeforeSwapDelta.unwrap(delta), 0);
assertEq(fee, hook.computeFee(80) | LPFeeLibrary.OVERRIDE_FEE_FLAG);
```

- [ ] **Step 3: Run tests and verify RED**

Run:

```bash
forge test --match-path test/SocialXHook.t.sol -vvv
```

Expected: FAIL because the current constructor does not accept `poolManager`, the contract does not implement `beforeSwap`, and v4 imports are not yet used.

---

### Task 2: Implement True v4 Hook Contract

**Files:**
- Modify: `src/SocialXHook.sol`
- Test: `test/SocialXHook.t.sol`

- [ ] **Step 1: Rewrite imports and contract declaration**

Use:

```solidity
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";

contract SocialXHook is IHooks {
```

- [ ] **Step 2: Add constructor and hook permission validation**

Use:

```solidity
address public immutable owner;
IPoolManager public immutable poolManager;

constructor(address _poolManager, address _owner) {
    if (_poolManager == address(0) || _owner == address(0)) revert InvalidAddress();
    poolManager = IPoolManager(_poolManager);
    owner = _owner;
    keepers[_owner] = true;
    IHooks(address(this)).validateHookPermissions(_permissions());
    emit KeeperAdded(_owner);
}
```

- [ ] **Step 3: Implement `beforeSwap`**

Use:

```solidity
function beforeSwap(
    address,
    PoolKey calldata,
    IPoolManager.SwapParams calldata,
    bytes calldata hookData
) external view override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24) {
    address kol = _decodeKOL(hookData);
    uint24 fee = DEFAULT_FEE;
    if (kol != address(0) && kols[kol].active) {
        fee = computeFee(kols[kol].socialScore);
    }
    return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
}
```

- [ ] **Step 4: Implement unused hook functions as explicit reverts**

Each unused `IHooks` function returns its own selector type but should do:

```solidity
revert HookNotImplemented();
```

- [ ] **Step 5: Run tests and verify GREEN**

Run:

```bash
forge test --match-path test/SocialXHook.t.sol -vvv
```

Expected: PASS for the focused test file.

---

### Task 3: Deployment Script

**Files:**
- Modify: `script/Deploy.s.sol`
- Test: `forge build`

- [ ] **Step 1: Add a script-local CREATE2 deployer**

Use:

```solidity
contract HookDeployer {
    function deploy(bytes32 salt, address poolManager, address owner) external returns (SocialXHook hook) {
        hook = new SocialXHook{salt: salt}(poolManager, owner);
    }
}
```

- [ ] **Step 2: Mine salt off-chain inside the script**

Compute predicted addresses until:

```solidity
uint160(predicted) & Hooks.ALL_HOOK_MASK == Hooks.BEFORE_SWAP_FLAG
```

- [ ] **Step 3: Require `POOL_MANAGER` and deploy**

Run:

```bash
forge build
```

Expected: PASS.

---

### Task 4: Keeper and Docs Alignment

**Files:**
- Modify: `keeper/index.js`
- Modify: `.env.example`
- Modify: `README.md`
- Modify: `SUMMARY.md`
- Modify: `TWEETS.md`
- Modify: `setup.sh`

- [ ] **Step 1: Update keeper ABI tuple**

Use:

```javascript
"function getKOL(address) view returns (tuple(string xHandle, uint256 socialScore, uint256 registeredAt, bool active))",
```

- [ ] **Step 2: Remove auto-post claims**

Keep read-only X API, scoring, dry-run, and `batchUpdateScores`. Remove or reword text that says the agent posts tweets.

- [ ] **Step 3: Update docs to match implementation**

Docs must say:

```text
Manual tweets + read-only keeper.
True Uniswap v4 beforeSwap dynamic-fee hook.
KOL fee sharing is roadmap, not live custom accounting.
POOL_MANAGER is required for XLayer deployment.
```

- [ ] **Step 4: Run full verification**

Run:

```bash
forge test -vvv
npm --prefix keeper install
node --check keeper/index.js
```

Expected: Foundry tests pass, keeper installs, JS syntax check passes.
