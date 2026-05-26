// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

contract DemoERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 supply, address receiver) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        totalSupply = supply;
        balanceOf[receiver] = supply;
        emit Transfer(address(0), receiver, supply);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract InitializeDemoPool is Script {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    int24 internal constant TICK_SPACING = 60;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address poolManager = vm.envAddress("POOL_MANAGER");
        address hook = vm.envAddress("HOOK_ADDRESS");

        console2.log("=== Initialize SocialX demo v4 pool ===");
        console2.log("Deployer:", deployer);
        console2.log("PoolManager:", poolManager);
        console2.log("Hook:", hook);
        console2.log("Chain:", block.chainid);

        vm.startBroadcast(pk);
        DemoERC20 tokenA = new DemoERC20("SocialX Demo Token A", "SXA", 18, 1_000_000 ether, deployer);
        DemoERC20 tokenB = new DemoERC20("SocialX Demo Token B", "SXB", 18, 1_000_000 ether, deployer);

        (address currency0, address currency1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        int24 tick = IPoolManager(poolManager).initialize(key, SQRT_PRICE_1_1);
        PoolId poolId = key.toId();
        vm.stopBroadcast();

        console2.log("TokenA:", address(tokenA));
        console2.log("TokenB:", address(tokenB));
        console2.log("Currency0:", currency0);
        console2.log("Currency1:", currency1);
        console2.log("Fee:", LPFeeLibrary.DYNAMIC_FEE_FLAG);
        console2.log("TickSpacing:", TICK_SPACING);
        console2.log("SqrtPriceX96:", SQRT_PRICE_1_1);
        console2.log("InitialTick:", tick);
        console2.logBytes32(PoolId.unwrap(poolId));
    }
}
