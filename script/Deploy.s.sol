// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {SocialXHook} from "../src/SocialXHook.sol";

contract HookDeployer {
    function deploy(bytes32 salt, address poolManager, address owner) external returns (SocialXHook hook) {
        hook = new SocialXHook{salt: salt}(poolManager, owner);
    }
}

contract Deploy is Script {
    uint160 internal constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;
    uint256 internal constant MAX_SALT_SEARCH = 1_000_000;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address poolManager = vm.envAddress("POOL_MANAGER");

        console2.log("=== Deploy SocialXHook v4 ===");
        console2.log("Deployer:", deployer);
        console2.log("PoolManager:", poolManager);
        console2.log("Chain:", block.chainid);

        vm.startBroadcast(pk);
        HookDeployer hookDeployer = new HookDeployer();
        bytes32 salt = _findSalt(address(hookDeployer), poolManager, deployer);
        SocialXHook hook = hookDeployer.deploy(salt, poolManager, deployer);
        vm.stopBroadcast();

        console2.log("HookDeployer:", address(hookDeployer));
        console2.log("Hook:", address(hook));
        console2.log("Hook flags:", uint160(address(hook)) & ALL_HOOK_MASK);
    }

    function _findSalt(address create2Deployer, address poolManager, address owner) internal pure returns (bytes32) {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(SocialXHook).creationCode, abi.encode(poolManager, owner)));

        for (uint256 i = 0; i < MAX_SALT_SEARCH; i++) {
            bytes32 salt = bytes32(i);
            address predicted = _computeCreate2Address(create2Deployer, salt, initCodeHash);
            if (uint160(predicted) & ALL_HOOK_MASK == BEFORE_SWAP_FLAG) {
                return salt;
            }
        }

        revert("SocialXHook: salt not found");
    }

    function _computeCreate2Address(address deployer, bytes32 salt, bytes32 initCodeHash)
        internal
        pure
        returns (address)
    {
        bytes32 digest = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash));
        return address(uint160(uint256(digest)));
    }
}
