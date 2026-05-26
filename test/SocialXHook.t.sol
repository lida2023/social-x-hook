// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {SocialXHook} from "../src/SocialXHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title SocialXHookTest
 * @notice Unit tests for SocialXHook
 *
 * Run: forge test --match-contract SocialXHookTest -vvvv
 */
contract SocialXHookTest is Test {
    SocialXHook hook;
    address owner = makeAddr("owner");
    address keeper = makeAddr("keeper");
    address kol = makeAddr("kol");
    address user = makeAddr("user");

    function setUp() public {
        vm.prank(owner);
        // Deploy with zero PoolManager for unit tests
        hook = new SocialXHook(IPoolManager(address(0)), owner);
    }

    // ──────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────

    function test_Constructor_OwnerIsKeeper() public {
        assertTrue(hook.keepers(owner));
    }

    function test_Constructor_HookPermissions() public {
        Hooks.Permissions memory perms = hook.getHookPermissions();
        assertTrue(perms.beforeSwap);
        assertTrue(perms.afterSwap);
        assertFalse(perms.beforeModifyLiquidity);
    }

    // ──────────────────────────────────────────
    //  Keeper Management
    // ──────────────────────────────────────────

    function test_AddKeeper() public {
        vm.prank(owner);
        hook.addKeeper(keeper);
        assertTrue(hook.keepers(keeper));
    }

    function test_RemoveKeeper() public {
        vm.prank(owner);
        hook.addKeeper(keeper);
        vm.prank(owner);
        hook.removeKeeper(keeper);
        assertFalse(hook.keepers(keeper));
    }

    function test_Revert_NonOwnerCannotAddKeeper() public {
        vm.prank(user);
        vm.expectRevert();
        hook.addKeeper(keeper);
    }

    // ──────────────────────────────────────────
    //  Fee Calculation
    // ──────────────────────────────────────────

    function test_ComputeFee_Score0() public {
        // Score 0 → MAX_FEE (1% = 10000)
        uint24 fee = hook._computeFee(0);
        assertEq(fee, 10000);
    }

    function test_ComputeFee_Score100() public {
        // Score 100 → MIN_FEE (0.01% = 100)
        uint24 fee = hook._computeFee(100);
        assertEq(fee, 100);
    }

    function test_ComputeFee_Score50() public {
        // Score 50 → halfway: 10000 - (50*9900/100) = 10000 - 4950 = 5050
        uint24 fee = hook._computeFee(50);
        assertEq(fee, 5050);
    }

    function test_ComputeFee_Linear() public {
        // Verify linear decrease
        uint24 fee0 = hook._computeFee(0);
        uint24 fee50 = hook._computeFee(50);
        uint24 fee100 = hook._computeFee(100);
        assertGt(fee0, fee50);
        assertGt(fee50, fee100);
    }

    // ──────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────

    function test_Constants() public {
        assertEq(hook.MAX_FEE(), 10000);
        assertEq(hook.MIN_FEE(), 100);
        assertEq(hook.DEFAULT_FEE(), 3000);
        assertEq(hook.MAX_SCORE(), 100);
        assertEq(hook.KOL_FEE_SHARE_BPS(), 3000);
    }

    // ──────────────────────────────────────────
    //  Note: Full KOL registration + score update
    //  flow requires a valid PoolKey and
    //  PoolManager interaction — tested in
    //  integration tests below.
    // ──────────────────────────────────────────
}

/**
 * @title SocialXHookIntegrationTest
 * @notice Integration test with actual PoolManager
 * @dev Run: forge test --match-contract SocialXHookIntegrationTest -vvvv
 */
contract SocialXHookIntegrationTest is Test {
    // TODO: Integration tests with:
    // 1. Deploy PoolManager + V4 periphery
    // 2. Deploy SocialXHook
    // 3. Create pool with hook
    // 4. registerKOL with X handle
    // 5. updateSocialScore → verify fee change
    // 6. Execute swap → verify KOL fee accumulation
    // 7. claimFees → verify KOL receives ETH
}
