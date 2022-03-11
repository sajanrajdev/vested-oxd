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

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    IVault public bOxSolid;

    bool public withdrawalSafetyCheck = false;
    bool public harvestOnRebalance = false;

    // If nothing is unlocked, processExpiredLocks will revert
    bool public processLocksOnReinvest = false;
    bool public processLocksOnRebalance = false;

    IVlOxd public constant LOCKER = IVlOxd(0xDA00527EDAabCe6F97D89aDb10395f719E5559b9);

    IERC20Upgradeable public constant OXD = IERC20Upgradeable(0xc5A9848b9d145965d821AaeC8fA32aaEE026492d);
    IERC20Upgradeable public constant OXSOLID = IERC20Upgradeable(0xDA0053F0bEfCbcaC208A3f867BB243716734D809);

    IVotingSnapshot public constant VOTING_SNAPSHOT = IVotingSnapshot(0xDA007a39a692B0feFe9c6cb1a185feAb2722c4fD);

    // The initial DELEGATE for the strategy // NOTE we can change it by using manualSetDelegate below
    address public constant DELEGATE = address(0); // TODO

    // event RewardsCollected(
    //     address token,
    //     uint256 amount
    // );

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault, address _bOxSolid) public initializer {
        assert(IVault(_vault).token() == address(OXD));

        __BaseStrategy_init(_vault);

        want = address(OXD);
        bOxSolid = IVault(_bOxSolid);

        OXD.safeApprove(address(LOCKER), type(uint256).max);
        OXSOLID.safeApprove(_bOxSolid, type(uint256).max);

        VOTING_SNAPSHOT.setVoteDelegate(DELEGATE);
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

    ///@dev Should we harvest before doing manual rebalancing
    ///@notice you most likely want to skip harvest if everything is unlocked, or there's something wrong and you just want out
    function setHarvestOnRebalance(bool newHarvestOnRebalance) external {
        _onlyGovernance();
        harvestOnRebalance = newHarvestOnRebalance;
    }

    ///@dev Should we processExpiredLocks during reinvest?
    function setProcessLocksOnReinvest(bool newProcessLocksOnReinvest) external {
        _onlyGovernance();
        processLocksOnReinvest = newProcessLocksOnReinvest;
    }

    ///@dev Should we processExpiredLocks during manualRebalance?
    function setProcessLocksOnRebalance(bool newProcessLocksOnRebalance) external {
        _onlyGovernance();
        processLocksOnRebalance = newProcessLocksOnRebalance;
    }

    // /// @dev Function to move rewards that are not protected
    // /// @notice Only not protected, moves the whole amount using _handleRewardTransfer
    // /// @notice because token paths are harcoded, this function is safe to be called by anyone
    // function sweepRewardToken(address token) public {
    //     _onlyGovernanceOrStrategist();
    //     _onlyNotProtectedTokens(token);
    //
    //     uint256 toSend = IERC20Upgradeable(token).balanceOf(address(this));
    //     _handleRewardTransfer(token, toSend);
    // }
    //
    // /// @dev Bulk function for sweepRewardToken
    // function sweepRewards(address[] calldata tokens) external {
    //     uint256 length = tokens.length;
    //     for(uint i = 0; i < length; i++){
    //         sweepRewardToken(tokens[i]);
    //     }
    // }
    //
    // /// *** Handling of rewards ***
    // function _handleRewardTransfer(address token, uint256 amount) internal {
    //     // NOTE: BADGER is emitted through the tree
    //     if (token == BADGER){
    //         _sendBadgerToTree(amount);
    //     } else {
    //     // NOTE: All other tokens are sent to multisig
    //         _sentTokenToBribesReceiver(token, amount);
    //     }
    // }
    //
    // /// @dev Send funds to the bribes receiver
    // function _sentTokenToBribesReceiver(address token, uint256 amount) internal {
    //     IERC20Upgradeable(token).safeTransfer(BRIBES_RECEIVER, amount);
    //     emit RewardsCollected(token, amount);
    // }
    //
    // /// @dev Send the BADGER token to the badgerTree
    // function _sendBadgerToTree(uint256 amount) internal {
    //     IERC20Upgradeable(BADGER).safeTransfer(BADGER_TREE, amount);
    //     emit TreeDistribution(BADGER, amount, block.number, block.timestamp); // TODO
    // }

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

    // TODO: Right now there are only oxSolid rewards. Should I modify for cases when
    //       are oxd, solid or other rewards?
    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        LOCKER.getReward();

        harvested = new TokenAmount[](1);

        // OXSOLID --> bOXSOLID
        uint256 oxSolidBalance = OXSOLID.balanceOf(address(this));
        harvested[0].token = address(bOxSolid);
        if (oxSolidBalance > 0) {
            bOxSolid.deposit(oxSolidBalance);
            uint256 vaultBalance = bOxSolid.balanceOf(address(this));

            harvested[0].amount = vaultBalance;
            _processExtraToken(address(bOxSolid), vaultBalance);
        }

        _reportToVault(0);
    }

    // Example tend is a no-op which returns the values, could also just revert
    function _tend() internal override returns (TokenAmount[] memory tended) {
        revert("no op"); // NOTE: For now tend is replaced by manualRebalance
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

    // function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory) {
    //     // We need to unlock funds if the lockedBalance (locked + unlocked) is greater than the balance (actively locked for this epoch)
    //     upkeepNeeded = LOCKER.lockedBalanceOf(address(this)) > LOCKER.balanceOf(address(this));
    // }
    //
    // /// @dev Function for ChainLink Keepers to automatically process expired locks
    // function performUpkeep(bytes calldata) external {
    //     // Works like this because it reverts if lock is not expired
    //     LOCKER.processExpiredLocks(false);
    // }

    /// @dev Send all available OXD to the Vault
    /// @notice you can do this so you can earn again (re-lock), or just to add to the redemption pool
    function manualSendOXDToVault() external whenNotPaused {
        _onlyGovernance();
        uint256 oxdAmount = balanceOfWant();
        _transferToVault(oxdAmount);
    }

    /// @dev use the currently available OXD to lock
    /// @notice toLock = 0, lock nothing, deposit in OXD as much as you can
    /// @notice toLock = 10_000, lock everything (OXD) you have
    function manualRebalance(uint256 toLock) external whenNotPaused {
        _onlyGovernance();
        require(toLock <= MAX_BPS, "Max is 100%");

        if (processLocksOnRebalance) {
            // manualRebalance will revert if you have no expired locks
            LOCKER.processExpiredLocks(false);
        }

        if (harvestOnRebalance) {
            _harvest();
        }

        // Token that is highly liquid
        uint256 wantBalance = balanceOfWant();
        // Locked OXD in the locker
        uint256 balanceInLock = LOCKER.balanceOf(address(this));
        uint256 totalOXDBalance = wantBalance.add(balanceInLock);

        // Amount we want to have in lock
        uint256 newLockAmount = totalOXDBalance.mul(toLock).div(MAX_BPS);

        // We can't unlock enough, no-op
        if (newLockAmount <= balanceInLock) {
            return;
        }

        // If we're continuing, then we are going to lock something
        uint256 oxdToLock = newLockAmount.sub(balanceInLock);

        // We only lock up to the available OXD
        uint256 maxOXD = balanceOfWant();
        if (oxdToLock > maxOXD) {
            // Just lock what we can
            LOCKER.lock(address(this), maxOXD, getBoostPayment());
        } else {
            // Lock proper
            LOCKER.lock(address(this), oxdToLock, getBoostPayment());
        }

        // If anything left, send to vault
        uint256 oxdLeft = balanceOfWant();
        if (oxdLeft > 0) {
            _transferToVault(oxdLeft);
        }
    }
}
