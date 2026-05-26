// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SocialXHook} from "../src/SocialXHook.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract SocialXHookTest is Test {
    SocialXHook hook;
    PoolManager manager;

    address owner = makeAddr("owner");
    address keeper = makeAddr("keeper");
    address kol = makeAddr("kol");
    address otherKol = makeAddr("otherKol");
    address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG));

    PoolKey key;
    IPoolManager.SwapParams params;
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function setUp() public {
        manager = new PoolManager(owner);
        deployCodeTo("SocialXHook.sol:SocialXHook", abi.encode(address(manager), owner), hookAddress);
        hook = SocialXHook(payable(hookAddress));

        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        params =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_1 - 1});
    }

    function test_ConstructorStoresPoolManagerAndOwner() public view {
        assertEq(address(hook.poolManager()), address(manager));
        assertEq(hook.owner(), owner);
        assertTrue(hook.keepers(owner));
    }

    function test_HookAddressHasBeforeSwapPermission() public view {
        assertEq(uint160(address(hook)) & Hooks.ALL_HOOK_MASK, Hooks.BEFORE_SWAP_FLAG);
    }

    function test_ComputeFee() public view {
        assertEq(hook.computeFee(0), 10000);
        assertEq(hook.computeFee(50), 5050);
        assertEq(hook.computeFee(100), 100);
    }

    function test_RegisterKOL() public {
        vm.prank(kol);
        hook.registerKOL("@testkol");

        SocialXHook.KOL memory registered = hook.getKOL(kol);
        assertTrue(registered.active);
        assertEq(registered.xHandle, "@testkol");
        assertEq(hook.totalKolsRegistered(), 1);
        assertEq(hook.handleToAddress("@testkol"), kol);
    }

    function test_HandleUniqueness() public {
        vm.prank(kol);
        hook.registerKOL("@testkol");

        vm.prank(otherKol);
        vm.expectRevert(SocialXHook.HandleTaken.selector);
        hook.registerKOL("@testkol");
    }

    function test_EmptyHandle() public {
        vm.prank(kol);
        vm.expectRevert(SocialXHook.EmptyHandle.selector);
        hook.registerKOL("");
    }

    function test_DoubleRegister() public {
        vm.prank(kol);
        hook.registerKOL("@testkol");

        vm.prank(kol);
        vm.expectRevert(SocialXHook.AlreadyRegistered.selector);
        hook.registerKOL("@another");
    }

    function test_UpdateScore() public {
        vm.prank(kol);
        hook.registerKOL("@testkol");

        vm.prank(owner);
        hook.updateScore(kol, 80);

        assertEq(hook.getKOL(kol).socialScore, 80);
    }

    function test_Revert_NonKeeperUpdate() public {
        vm.prank(kol);
        hook.registerKOL("@testkol");

        vm.prank(address(0xbad));
        vm.expectRevert(SocialXHook.NotKeeper.selector);
        hook.updateScore(kol, 50);
    }

    function test_Revert_InvalidScore() public {
        vm.prank(kol);
        hook.registerKOL("@testkol");

        vm.prank(owner);
        vm.expectRevert(SocialXHook.InvalidScore.selector);
        hook.updateScore(kol, 101);
    }

    function test_AddRemoveKeeper() public {
        vm.prank(owner);
        hook.addKeeper(keeper);
        assertTrue(hook.keepers(keeper));

        vm.prank(owner);
        hook.removeKeeper(keeper);
        assertFalse(hook.keepers(keeper));
    }

    function test_BatchUpdate() public {
        vm.prank(kol);
        hook.registerKOL("@testkol");

        address[] memory kols = new address[](1);
        kols[0] = kol;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 90;

        vm.prank(owner);
        hook.batchUpdateScores(kols, scores);

        assertEq(hook.getKOL(kol).socialScore, 90);
    }

    function test_BeforeSwapRevertsWhenCallerIsNotPoolManager() public {
        vm.expectRevert(SocialXHook.NotPoolManager.selector);
        hook.beforeSwap(address(this), key, params, abi.encode(kol));
    }

    function test_BeforeSwapReturnsOverrideFeeForActiveKOL() public {
        vm.prank(kol);
        hook.registerKOL("@testkol");

        vm.prank(owner);
        hook.updateScore(kol, 80);

        vm.prank(address(manager));
        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) =
            hook.beforeSwap(address(this), key, params, abi.encode(kol));

        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(delta), 0);
        assertEq(fee, hook.computeFee(80) | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function test_BeforeSwapReturnsDefaultOverrideFeeWithoutKOLData() public {
        vm.prank(address(manager));
        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = hook.beforeSwap(address(this), key, params, "");

        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(delta), 0);
        assertEq(fee, hook.DEFAULT_FEE() | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function test_CanInitializeV4DynamicFeePoolWithHook() public {
        int24 tick = manager.initialize(key, SQRT_PRICE_1_1);
        assertEq(tick, 0);
    }
}
