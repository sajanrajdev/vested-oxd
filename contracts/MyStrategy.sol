// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";

import {IVault} from "../interfaces/badger/IVault.sol";
import {IVlOxd} from "../interfaces/oxd/IVlOxd.sol";
import {IVotingSnapshot} from "../interfaces/oxd/IVotingSnapshot.sol";
import {route, IBaseV1Router01} from "../interfaces/solidly/IBaseV1Router01.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    bool public withdrawalSafetyCheck = false;

    // If nothing is unlocked, processExpiredLocks will revert
    bool public processLocksOnReinvest = false;

    IVlOxd public constant LOCKER = IVlOxd(0xDA00527EDAabCe6F97D89aDb10395f719E5559b9);

    IERC20Upgradeable public constant OXD = IERC20Upgradeable(0xc5A9848b9d145965d821AaeC8fA32aaEE026492d);
    IERC20Upgradeable public constant OXSOLID = IERC20Upgradeable(0xDA0053F0bEfCbcaC208A3f867BB243716734D809);
    IERC20Upgradeable public constant SOLID = IERC20Upgradeable(0x888EF71766ca594DED1F0FA3AE64eD2941740A20);
    IERC20Upgradeable public constant WFTM = IERC20Upgradeable(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);

    IVotingSnapshot public constant VOTING_SNAPSHOT = IVotingSnapshot(0xDA007a39a692B0feFe9c6cb1a185feAb2722c4fD);

    IBaseV1Router01 public constant SOLIDLY_ROUTER = IBaseV1Router01(0xa38cd27185a464914D3046f0AB9d43356B34829D);

    // The initial DELEGATE for the strategy // NOTE we can change it by using manualSetDelegate below
    address public constant DELEGATE = address(0x781E82D5D49042baB750efac91858cB65C6b0582);

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault) public initializer {
        assert(IVault(_vault).token() == address(OXD));

        __BaseStrategy_init(_vault);

        want = address(OXD);

        OXD.safeApprove(address(LOCKER), type(uint256).max);
        VOTING_SNAPSHOT.setVoteDelegate(DELEGATE);

        OXSOLID.safeApprove(address(SOLIDLY_ROUTER), type(uint256).max);

        autoCompoundRatio = MAX_BPS;
    }

    /// ===== Extra Functions =====

    /// @dev Change Delegation to another address
    function manualSetDelegate(address delegate) external {
        _onlyGovernance();
        // Set delegate is enough as it will clear previous delegate automatically
        VOTING_SNAPSHOT.setVoteDelegate(delegate);
    }

    ///@dev Should we check if the amount requested is more than what we can return on withdrawal?
    function setWithdrawalSafetyCheck(bool newWithdrawalSafetyCheck) external {
        _onlyGovernance();
        withdrawalSafetyCheck = newWithdrawalSafetyCheck;
    }

    ///@dev Should we processExpiredLocks during reinvest?
    function setProcessLocksOnReinvest(bool newProcessLocksOnReinvest) external {
        _onlyGovernance();
        processLocksOnReinvest = newProcessLocksOnReinvest;
    }

    /// ===== View Functions =====

    function getBoostPayment() public view returns (uint256) {
        // uint256 maximumBoostPayment = LOCKER.maximumBoostPayment();
        // require(maximumBoostPayment <= 1500, "over max payment"); //max 15%
        // return maximumBoostPayment;
        return 0;
    }

    /// @dev Return the name of the strategy
    function getName() external pure override returns (string memory) {
        return "vlOXD Voting Strategy";
    }

    /// @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.5";
    }

    /// @dev Does this function require `tend` to be called?
    function _isTendable() internal pure override returns (bool) {
        return false; // Change to true if the strategy should be tended
    }

    /// @dev Return the balance (in want) that the strategy has invested somewhere
    function balanceOfPool() public view override returns (uint256) {
        // Return the balance in locker
        return LOCKER.lockedBalanceOf(address(this));
    }

    /// @dev Return the balance of rewards that the strategy has accrued
    /// @notice Used for offChain APY and Harvest Health monitoring
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {
        IVlOxd.EarnedData[] memory earnedData = LOCKER.claimableRewards(address(this));
        uint256 numRewards = earnedData.length;
        rewards = new TokenAmount[](numRewards);
        for (uint256 i; i < numRewards; ++i) {
            rewards[i] = TokenAmount(earnedData[i].token, earnedData[i].amount);
        }
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](2);
        protectedTokens[0] = want; // OXD
        protectedTokens[1] = address(OXSOLID);
        return protectedTokens;
    }

    /// ===== Internal Core Implementations =====

    /// @dev Deposit `_amount` of want, investing it to earn yield
    function _deposit(uint256 _amount) internal override {
        // Lock tokens for 16 weeks, send credit to strat, always use max boost cause why not?
        LOCKER.lock(address(this), _amount, getBoostPayment());
    }

    /// @dev utility function to withdraw all OXD that we can from the lock
    function prepareWithdrawAll() external {
        manualProcessExpiredLocks();
    }

    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        //NOTE: This probably will always fail unless we have all tokens expired
        require(
            LOCKER.lockedBalanceOf(address(this)) == 0 && LOCKER.balanceOf(address(this)) == 0,
            "You have to wait for unlock or have to manually rebalance out of it"
        );

        // Make sure to call prepareWithdrawAll before _withdrawAll
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        uint256 max = balanceOfWant();

        if (_amount > max) {
            // Try to unlock, as much as possible
            // @notice Reverts if no locks expired
            LOCKER.processExpiredLocks(false);
            max = balanceOfWant();
        }

        if (withdrawalSafetyCheck) {
            require(max >= _amount.mul(9_980).div(MAX_BPS), "Withdrawal Safety Check"); // 20 BP of slippage
        }

        if (_amount > max) {
            return max;
        }

        return _amount;
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        uint256 wantBalanceBefore = balanceOfWant();

        LOCKER.getReward();

        harvested = new TokenAmount[](1);
        harvested[0].token = address(OXD);

        // OXSOLID --> SOLID --> WFTM --> OXD
        uint256 oxSolidBalance = OXSOLID.balanceOf(address(this));
        if (oxSolidBalance > 0) {
            route[] memory routeArray = new route[](3);

            (, bool stable) = SOLIDLY_ROUTER.getAmountOut(oxSolidBalance, address(OXSOLID), address(SOLID));

            routeArray[0] = route(address(OXSOLID), address(SOLID), stable);
            routeArray[1] = route(address(SOLID), address(WFTM), false);
            routeArray[2] = route(address(WFTM), address(OXD), false);

            SOLIDLY_ROUTER.swapExactTokensForTokens(oxSolidBalance, 0, routeArray, address(this), block.timestamp);

            harvested[0].amount = balanceOfWant().sub(wantBalanceBefore);
        }

        _reportToVault(harvested[0].amount);
    }

    // Example tend is a no-op which returns the values, could also just revert
    function _tend() internal override returns (TokenAmount[] memory tended) {
        revert("no op");
    }

    /// MANUAL FUNCTIONS ///

    /// @dev manual function to reinvest all OXD that was locked
    function reinvest() external whenNotPaused returns (uint256) {
        _onlyGovernance();

        if (processLocksOnReinvest) {
            // Withdraw all we can
            LOCKER.processExpiredLocks(false);
        }

        // Redeposit all into veOXD
        uint256 toDeposit = IERC20Upgradeable(want).balanceOf(address(this));

        // Redeposit into veOXD
        _deposit(toDeposit);

        return toDeposit;
    }

    /// @dev process all locks, to redeem
    /// @notice No Access Control Checks, anyone can unlock an expired lock
    function manualProcessExpiredLocks() public whenNotPaused {
        // Unlock vlOXD that is expired and redeem OXD back to this strat
        LOCKER.processExpiredLocks(false);
    }

    /// @dev Send all available OXD to the Vault
    /// @notice you can do this so you can earn again (re-lock), or just to add to the redemption pool
    function manualSendOXDToVault() external whenNotPaused {
        _onlyGovernance();
        uint256 oxdAmount = balanceOfWant();
        _transferToVault(oxdAmount);
    }
}
