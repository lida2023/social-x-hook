// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SocialXHook} from "../src/SocialXHook.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title DeployAll
 * @notice Deploys Uniswap V4 PoolManager + SocialXHook on XLayer.
 *         Self-contained — no need to find a pre-deployed PoolManager.
 *
 * Usage:
 *   forge script script/DeployAll.s.sol:DeployAll \\
 *     --rpc-url xlayer \\
 *     --broadcast
 */
contract DeployAll is Script {
    /// @notice Owner of the hook (can add keepers, manage config)
    address constant HOOK_OWNER = address(0); // 0 = deployer becomes owner

    /// @notice PoolManager controller gas limit
    /// @dev 500_000 is the Uniswap V4 default
    uint256 constant CONTROLLER_GAS_LIMIT = 500_000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address owner = HOOK_OWNER == address(0) ? deployer : HOOK_OWNER;

        console2.log("=== SocialX Hook - Full Deploy ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Uniswap V4 PoolManager
        console2.log("-- Deploying PoolManager --");
        PoolManager poolManager = new PoolManager(CONTROLLER_GAS_LIMIT);
        console2.log("PoolManager:", address(poolManager));

        // 2. Deploy SocialXHook
        console2.log("-- Deploying SocialXHook --");
        SocialXHook hook = new SocialXHook(IPoolManager(address(poolManager)), owner);
        console2.log("SocialXHook:", address(hook));

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== All contracts deployed ===");
        console2.log("");
        console2.log("PoolManager: ", address(poolManager));
        console2.log("SocialXHook: ", address(hook));
        console2.log("Owner:       ", owner);
        console2.log("");
        console2.log("── Next steps ──");
        console2.log("1. Create a pool via PoolManager:");
        console2.log("   cast send", address(poolManager), "'initialize(PoolKey)' ...");
        console2.log("2. Register KOL:");
        console2.log("   cast send", address(hook), "'registerKOL(...)' '@your_handle'");
        console2.log("3. Launch agent:");
        console2.log("   cd keeper && npm start");
    }
}
