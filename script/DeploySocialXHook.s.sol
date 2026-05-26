// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SocialXHook} from "../src/SocialXHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title DeploySocialXHook
 * @notice Deploy SocialXHook on XLayer for the Build X Hackathon
 *
 * Usage:
 *   forge script script/DeploySocialXHook.s.sol:DeploySocialXHook \
 *     --rpc-url xlayer \
 *     --broadcast
 */
contract DeploySocialXHook is Script {
    // ── Edit these before deploying ─────────────────

    /// @notice Uniswap V4 PoolManager on XLayer
    /// @dev Replace with actual deployed address on XLayer
    IPoolManager constant POOL_MANAGER = IPoolManager(0x0000000000000000000000000000000000000000);

    /// @notice Hook owner (can add keepers, manage config)
    address constant HOOK_OWNER = 0x0000000000000000000000000000000000000000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Deploy SocialXHook ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        address owner = HOOK_OWNER == address(0) ? deployer : HOOK_OWNER;

        vm.startBroadcast(deployerPrivateKey);

        SocialXHook hook = new SocialXHook(POOL_MANAGER, owner);

        vm.stopBroadcast();

        console2.log("──────────────────────────────────");
        console2.log("✅ SocialXHook deployed at:", address(hook));
        console2.log("   PoolManager:", address(POOL_MANAGER));
        console2.log("   Owner:", owner);
        console2.log("──────────────────────────────────");
        console2.log("");
        console2.log("Next steps:");
        console2.log("1. Create a V4 pool with this hook address");
        console2.log('2. Call hook.registerKOL(poolKey, "@your_handle")');
        console2.log("3. Add keeper: hook.addKeeper(keeperAddress)");
        console2.log("4. Start keeper: node keeper/index.js");
        console2.log("5. Tweet → see fee drop on-chain!");
    }
}
