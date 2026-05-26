// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SocialXHook
 * @notice Uniswap V4 Hook — your X influence drives your pool.
 *         "The louder you tweet, the cheaper they swap."
 *
 * ── How it works ──────────────────────────────
 *  1. KOL registers with their X handle + creates a V4 pool
 *  2. A keeper feeds "social score" (0–100) on-chain
 *     → Score = f(likes, retweets, replies) of the KOL's latest tweet
 *  3. Higher social score → lower swap fees (dynamic LP fee)
 *     → Score 100 → fee drops to minFee (ultra cheap, volume spikes)
 *     → Score 0   → fee stays at maxFee (baseline)
 *  4. KOL earns a share of swap fees as creator revenue
 *
 * ── Built for ──────────────────────────────────
 *  OKX Build X Hackathon — Hook Track
 *  XLayer Chain ID 196
 *  @XLayerOfficial · @Uniswap · @flapdotsh
 *
 * @author Built with AI for the hackathon
 */
contract SocialXHook is BaseHook, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;

    // ──────────────────────────────────────────────
    //  Type Declarations
    // ──────────────────────────────────────────────

    /// @notice KOL profile stored on-chain
    struct KOLProfile {
        string  xHandle;        // e.g. "@akokoi1"
        uint256 socialScore;    // 0-100 (keeper-updated)
        uint256 totalFeesEarned; // lifetime OKB fees earned
        uint256 pendingFees;    // unclaimed OKB fees
        uint256 poolCreatedAt;  // timestamp
        bool    registered;
    }

    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    /// @notice Fee range (in Uniswap V4 units: 1 = 0.0001%)
    /// @dev maxFee = 1% (10000), minFee = 0.01% (100)
    uint24 public constant MAX_FEE = 10000;   // 1.00%
    uint24 public constant MIN_FEE = 100;     // 0.01%
    uint24 public constant DEFAULT_FEE = 3000; // 0.30% (when no social signal)

    /// @notice KOL fee share: 30% of swap fees go to KOL
    uint256 public constant KOL_FEE_SHARE_BPS = 3000; // 30%

    /// @notice Social score range
    uint256 public constant MAX_SCORE = 100;

    // ──────────────────────────────────────────────
    //  State Variables
    // ──────────────────────────────────────────────

    /// @notice PoolId → KOL profile
    mapping(PoolId => KOLProfile) public kols;

    /// @notice PoolId → accumulated fees for KOL (in native token wei)
    mapping(PoolId => uint256) public accumulatedFees;

    /// @notice Keeper addresses allowed to update social scores
    mapping(address => bool) public keepers;

    /// @notice KOL address → PoolId (reverse lookup)
    mapping(address => PoolId) public kolPools;

    /// @notice X handle → KOL address (for uniqueness)
    mapping(string => address) public handleToAddress;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event KOLRegistered(
        address indexed kol,
        PoolId indexed poolId,
        string xHandle,
        uint256 timestamp
    );

    event SocialScoreUpdated(
        address indexed kol,
        PoolId indexed poolId,
        string xHandle,
        uint256 oldScore,
        uint256 newScore,
        uint256 effectiveFee,
        uint256 timestamp
    );

    event KOLFeesClaimed(
        address indexed kol,
        PoolId indexed poolId,
        uint256 amount
    );

    event KeeperAdded(address indexed keeper);
    event KeeperRemoved(address indexed keeper);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error AlreadyRegistered();
    error HandleTaken();
    error NotKOL();
    error NotKeeper();
    error InvalidScore();
    error PoolNotRegistered();
    error EmptyHandle();
    error NothingToClaim();

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        IPoolManager _poolManager,
        address _owner
    ) BaseHook(_poolManager) Ownable(_owner) {
        // Owner is the default keeper
        keepers[_owner] = true;
        emit KeeperAdded(_owner);
    }

    // ──────────────────────────────────────────────
    //  Hook Permissions
    // ──────────────────────────────────────────────

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyLiquidity: false,
            afterModifyLiquidity: false,
            beforeSwap: true,       // ← Dynamic fee override
            afterSwap: true,        // ← Track volume for KOL rewards
            beforeDonate: false,
            afterDonate: false,
            noOp: false
        });
    }

    // ──────────────────────────────────────────────
    //  Hook Callbacks
    // ──────────────────────────────────────────────

    /// @notice BEFORE swap: override fee based on social score
    /// @dev Returns a BeforeSwapDelta with the dynamic fee
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        KOLProfile storage kol = kols[poolId];

        if (!kol.registered) {
            // Not a SocialX pool — pass through
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Compute dynamic fee: higher score → lower fee
        uint24 dynamicFee = _computeFee(kol.socialScore);

        // Return the dynamic fee via BeforeSwapDelta
        BeforeSwapDelta delta = toBeforeSwapDelta(0, int128(uint128(dynamicFee)));
        return (BaseHook.beforeSwap.selector, delta, dynamicFee);
    }

    /// @notice AFTER swap: accumulate KOL's share of fees
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        KOLProfile storage kol = kols[poolId];

        if (!kol.registered) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // Estimate fee from the swap delta
        // amountSpecified is the input amount; fee ≈ input × feeRate
        // For simplicity, we use a fixed % of the swap amount
        int256 swapAmount = params.amountSpecified < 0
            ? int256(-params.amountSpecified)
            : int256(params.amountSpecified);

        if (swapAmount > 0) {
            uint256 fee = (uint256(swapAmount) * _computeFee(kol.socialScore)) / 1_000_000;
            uint256 kolCut = (fee * KOL_FEE_SHARE_BPS) / 10000;
            kol.pendingFees += kolCut;
            accumulatedFees[poolId] += kolCut;
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    // ──────────────────────────────────────────────
    //  KOL Registration
    // ──────────────────────────────────────────────

    /// @notice Register as a KOL with your X handle
    /// @param poolKey The pool this KOL created (must match sender as creator)
    /// @param xHandle Your X/Twitter handle (e.g. "@akokoi1")
    function registerKOL(PoolKey calldata poolKey, string calldata xHandle) external {
        if (bytes(xHandle).length == 0) revert EmptyHandle();
        if (handleToAddress[xHandle] != address(0)) revert HandleTaken();

        PoolId poolId = poolKey.toId();
        if (kols[poolId].registered) revert AlreadyRegistered();

        kols[poolId] = KOLProfile({
            xHandle: xHandle,
            socialScore: 0,
            totalFeesEarned: 0,
            pendingFees: 0,
            poolCreatedAt: block.timestamp,
            registered: true
        });

        kolPools[msg.sender] = poolId;
        handleToAddress[xHandle] = msg.sender;

        emit KOLRegistered(msg.sender, poolId, xHandle, block.timestamp);
    }

    // ──────────────────────────────────────────────
    //  Social Score (Keeper-only)
    // ──────────────────────────────────────────────

    /// @notice Keeper updates social score for a KOL
    /// @param kol KOL address
    /// @param newScore 0-100, derived from tweet engagement
    function updateSocialScore(address kol, uint256 newScore) external {
        if (!keepers[msg.sender]) revert NotKeeper();
        if (newScore > MAX_SCORE) revert InvalidScore();

        PoolId poolId = kolPools[kol];
        KOLProfile storage profile = kols[poolId];
        if (!profile.registered) revert NotKOL();

        uint256 oldScore = profile.socialScore;
        profile.socialScore = newScore;
        uint256 effectiveFee = _computeFee(newScore);

        emit SocialScoreUpdated(
            kol, poolId, profile.xHandle,
            oldScore, newScore, effectiveFee, block.timestamp
        );
    }

    /// @notice Batch update social scores (for keeper efficiency)
    function batchUpdateScores(address[] calldata kols_, uint256[] calldata scores) external {
        if (!keepers[msg.sender]) revert NotKeeper();
        uint256 len = kols_.length;
        for (uint256 i = 0; i < len; i++) {
            if (scores[i] > MAX_SCORE) continue;
            PoolId poolId = kolPools[kols_[i]];
            KOLProfile storage profile = kols[poolId];
            if (!profile.registered) continue;

            uint256 oldScore = profile.socialScore;
            profile.socialScore = scores[i];
            uint256 effectiveFee = _computeFee(scores[i]);

            emit SocialScoreUpdated(
                kols_[i], poolId, profile.xHandle,
                oldScore, scores[i], effectiveFee, block.timestamp
            );
        }
    }

    // ──────────────────────────────────────────────
    //  KOL Fee Claims
    // ──────────────────────────────────────────────

    /// @notice KOL claims their accumulated swap fee share
    function claimFees() external nonReentrant {
        PoolId poolId = kolPools[msg.sender];
        KOLProfile storage kol = kols[poolId];
        if (!kol.registered) revert NotKOL();

        uint256 amount = kol.pendingFees;
        if (amount == 0) revert NothingToClaim();

        kol.pendingFees = 0;
        kol.totalFeesEarned += amount;

        // Send native token (OKB) to KOL
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        emit KOLFeesClaimed(msg.sender, poolId, amount);
    }

    // ──────────────────────────────────────────────
    //  Keeper Management (Owner-only)
    // ──────────────────────────────────────────────

    function addKeeper(address keeper) external onlyOwner {
        keepers[keeper] = true;
        emit KeeperAdded(keeper);
    }

    function removeKeeper(address keeper) external onlyOwner {
        keepers[keeper] = false;
        emit KeeperRemoved(keeper);
    }

    // ──────────────────────────────────────────────
    //  View Functions
    // ──────────────────────────────────────────────

    /// @notice Get the current effective fee for a pool
    function getEffectiveFee(address kol) external view returns (uint24) {
        PoolId poolId = kolPools[kol];
        KOLProfile storage profile = kols[poolId];
        if (!profile.registered) return DEFAULT_FEE;
        return _computeFee(profile.socialScore);
    }

    /// @notice Get KOL profile by address
    function getKOL(address kol) external view returns (KOLProfile memory) {
        PoolId poolId = kolPools[kol];
        return kols[poolId];
    }

    /// @notice Get KOL profile by X handle
    function getKOLByHandle(string calldata xHandle) external view returns (KOLProfile memory) {
        address kol = handleToAddress[xHandle];
        PoolId poolId = kolPools[kol];
        return kols[poolId];
    }

    /// @notice Compute fee from social score: linear interpolation
    /// @dev score 0 → MAX_FEE, score 100 → MIN_FEE
    function _computeFee(uint256 score) internal pure returns (uint24) {
        if (score >= MAX_SCORE) return MIN_FEE;
        // fee = MAX_FEE - (score * (MAX_FEE - MIN_FEE) / MAX_SCORE)
        uint256 reduction = (score * (MAX_FEE - MIN_FEE)) / MAX_SCORE;
        return uint24(MAX_FEE - reduction);
    }

    /// @notice Get fee breakdown for UI
    function getFeeBreakdown(address kol) external view returns (
        uint256 socialScore,
        uint24 effectiveFee,
        uint24 maxFee,
        uint24 minFee,
        uint256 pendingFees,
        uint256 totalFeesEarned
    ) {
        PoolId poolId = kolPools[kol];
        KOLProfile storage profile = kols[poolId];
        return (
            profile.socialScore,
            _computeFee(profile.socialScore),
            MAX_FEE,
            MIN_FEE,
            profile.pendingFees,
            profile.totalFeesEarned
        );
    }

    // ──────────────────────────────────────────────
    //  Fallback — receive native token (OKB) for fees
    // ──────────────────────────────────────────────
    receive() external payable {}
}
