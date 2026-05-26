// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";

/**
 * @title SocialXHook
 * @notice Uniswap v4 beforeSwap hook that maps X engagement scores to dynamic LP fees.
 */
contract SocialXHook is IHooks {
    using Hooks for IHooks;

    uint24 public constant MAX_FEE = 10000; // 1.00%
    uint24 public constant MIN_FEE = 100; // 0.01%
    uint24 public constant DEFAULT_FEE = 3000; // 0.30%
    uint256 public constant MAX_SCORE = 100;
    string public constant VERSION = "2.0.0";

    address public immutable owner;
    IPoolManager public immutable poolManager;

    struct KOL {
        string xHandle;
        uint256 socialScore;
        uint256 registeredAt;
        bool active;
    }

    mapping(address => KOL) public kols;
    mapping(string => address) public handleToAddress;
    mapping(address => bool) public keepers;
    uint256 public totalKolsRegistered;

    event KOLRegistered(address indexed kol, string xHandle);
    event ScoreUpdated(address indexed kol, uint256 oldScore, uint256 newScore, uint24 effectiveFee);
    event KeeperAdded(address indexed keeper);
    event KeeperRemoved(address indexed keeper);

    error NotOwner();
    error NotKeeper();
    error NotPoolManager();
    error NotKOL();
    error HandleTaken();
    error AlreadyRegistered();
    error InvalidScore();
    error EmptyHandle();
    error InvalidAddress();
    error LengthMismatch();
    error HookNotImplemented();

    constructor(address _poolManager, address _owner) {
        if (_poolManager == address(0) || _owner == address(0)) revert InvalidAddress();

        owner = _owner;
        poolManager = IPoolManager(_poolManager);
        keepers[_owner] = true;

        IHooks(address(this)).validateHookPermissions(_hookPermissions());

        emit KeeperAdded(_owner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyKeeper() {
        if (!keepers[msg.sender]) revert NotKeeper();
        _;
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function registerKOL(string calldata xHandle) external {
        if (bytes(xHandle).length == 0) revert EmptyHandle();
        if (handleToAddress[xHandle] != address(0)) revert HandleTaken();
        if (kols[msg.sender].active) revert AlreadyRegistered();

        kols[msg.sender] = KOL({xHandle: xHandle, socialScore: 0, registeredAt: block.timestamp, active: true});
        handleToAddress[xHandle] = msg.sender;
        totalKolsRegistered++;

        emit KOLRegistered(msg.sender, xHandle);
    }

    function updateScore(address kol, uint256 newScore) external onlyKeeper {
        if (newScore > MAX_SCORE) revert InvalidScore();

        KOL storage k = kols[kol];
        if (!k.active) revert NotKOL();

        uint256 oldScore = k.socialScore;
        k.socialScore = newScore;

        emit ScoreUpdated(kol, oldScore, newScore, computeFee(newScore));
    }

    function batchUpdateScores(address[] calldata kols_, uint256[] calldata scores) external onlyKeeper {
        uint256 len = kols_.length;
        if (len != scores.length) revert LengthMismatch();

        for (uint256 i = 0; i < len; i++) {
            if (scores[i] > MAX_SCORE) continue;

            KOL storage k = kols[kols_[i]];
            if (!k.active) continue;

            uint256 oldScore = k.socialScore;
            k.socialScore = scores[i];
            emit ScoreUpdated(kols_[i], oldScore, scores[i], computeFee(scores[i]));
        }
    }

    function addKeeper(address keeper) external onlyOwner {
        if (keeper == address(0)) revert InvalidAddress();
        keepers[keeper] = true;
        emit KeeperAdded(keeper);
    }

    function removeKeeper(address keeper) external onlyOwner {
        keepers[keeper] = false;
        emit KeeperRemoved(keeper);
    }

    function computeFee(uint256 score) public pure returns (uint24) {
        if (score >= MAX_SCORE) return MIN_FEE;
        uint256 reduction = (score * (MAX_FEE - MIN_FEE)) / MAX_SCORE;
        // score is capped at 100, so the result always fits in uint24.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint24(MAX_FEE - reduction);
    }

    function getKOL(address kol) external view returns (KOL memory) {
        return kols[kol];
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata hookData)
        external
        view
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        address kol = _decodeKOL(hookData);
        uint24 fee = DEFAULT_FEE;

        if (kol != address(0) && kols[kol].active) {
            fee = computeFee(kols[kol].socialScore);
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        override
        returns (bytes4, int128)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function _decodeKOL(bytes calldata hookData) internal pure returns (address kol) {
        if (hookData.length == 20) {
            assembly ("memory-safe") {
                kol := shr(96, calldataload(hookData.offset))
            }
        } else if (hookData.length >= 32) {
            kol = abi.decode(hookData, (address));
        }
    }

    function _hookPermissions() internal pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}
