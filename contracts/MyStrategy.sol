// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/badger/IVault.sol";
import "../interfaces/oxd/IVlOxd.sol";
import "../interfaces/oxd/IVotingSnapshot.sol";

import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    address public constant BADGER_TREE = 0x89122c767A5F543e663DB536b603123225bc3823;

    IVotingSnapshot public constant VOTING_SNAPSHOT =
        IVotingSnapshot(0xDA007a39a692B0feFe9c6cb1a185feAb2722c4fD);

    IVault public constant OXSOLID_VAULT =
        IVault(address(1)); // TODO

    // The initial DELEGATE for the strategy // NOTE we can change it by using manualSetDelegate below
    address public constant DELEGATE = address(1); // TODO

    // We hardcode, an upgrade is required to change this as it's a meaningful change
    address public constant BRIBES_RECEIVER = address(1); // TODO

    // We emit badger through the tree to the vault holders
    address public constant BADGER = address(1); // TODO

    // NOTE: At time of publishing, this contract is under audit
    IVlOxd public constant LOCKER = IVlOxd(0xDA00527EDAabCe6F97D89aDb10395f719E5559b9);

    address public reward; // Token we farm

    bool public withdrawalSafetyCheck = false;
    bool public harvestOnRebalance = false;

    // If nothing is unlocked, processExpiredLocks will revert
    bool public processLocksOnReinvest = false;
    bool public processLocksOnRebalance = false;

    event RewardsCollected(
        address token,
        uint256 amount
    );

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault, address[2] memory _wantConfig) public initializer {
    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
        __BaseStrategy_init(_vault);
        /// @dev Add config here
        want = _wantConfig[0];
        reward = _wantConfig[1];
        
        // Permissions for Locker
        IERC20Upgradeable(want).safeApprove(address(LOCKER), type(uint256).max);

        IERC20Upgradeable(reward).safeApprove(address(OXSOLID_VAULT), type(uint256).max);

        // Delegate voting to DELEGATE
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
    function setProcessLocksOnRebalance(bool newProcessLocksOnRebalance)
        external
    {
        _onlyGovernance();
        processLocksOnRebalance = newProcessLocksOnRebalance;
    }

    /// @dev Function to move rewards that are not protected
    /// @notice Only not protected, moves the whole amount using _handleRewardTransfer
    /// @notice because token paths are harcoded, this function is safe to be called by anyone
    function sweepRewardToken(address token) public {
        _onlyGovernanceOrStrategist();
        _onlyNotProtectedTokens(token);

        uint256 toSend = IERC20Upgradeable(token).balanceOf(address(this));
        _handleRewardTransfer(token, toSend);
    }

    /// @dev Bulk function for sweepRewardToken
    function sweepRewards(address[] calldata tokens) external {
        uint256 length = tokens.length;
        for(uint i = 0; i < length; i++){
            sweepRewardToken(tokens[i]);
        }
    }

    /// *** Handling of rewards ***
    function _handleRewardTransfer(address token, uint256 amount) internal {
        // NOTE: BADGER is emitted through the tree
        if (token == BADGER){
            _sendBadgerToTree(amount);
        } else {
        // NOTE: All other tokens are sent to multisig
            _sentTokenToBribesReceiver(token, amount);
        }
    }

    /// @dev Send funds to the bribes receiver
    function _sentTokenToBribesReceiver(address token, uint256 amount) internal {
        IERC20Upgradeable(token).safeTransfer(BRIBES_RECEIVER, amount);
        emit RewardsCollected(token, amount);
    }

    /// @dev Send the BADGER token to the badgerTree
    function _sendBadgerToTree(uint256 amount) internal {
        IERC20Upgradeable(BADGER).safeTransfer(BADGER_TREE, amount);
        // emit TreeDistribution(BADGER, amount, block.number, block.timestamp); // TODO
    }

    /// ===== View Functions =====

    function getBoostPayment() public view returns(uint256){
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
    function _isTendable() internal override pure returns (bool) {
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
        // TODO
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](2);
        protectedTokens[0] = want;
        protectedTokens[1] = reward;
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
            LOCKER.lockedBalanceOf(address(this)) == 0 &&
                LOCKER.balanceOf(address(this)) == 0,
            "You have to wait for unlock or have to manually rebalance out of it"
        );

        // Make sure to call prepareWithdrawAll before _withdrawAll
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        uint256 max = balanceOfWant();

        if(_amount > max){
            // Try to unlock, as much as possible
            // @notice Reverts if no locks expired
            LOCKER.processExpiredLocks(false);
            max = balanceOfWant();
        }


        if (withdrawalSafetyCheck) {
            require(
                max >= _amount.mul(9_980).div(MAX_BPS),
                "Withdrawal Safety Check"
            ); // 20 BP of slippage
        }

        if (_amount > max) {
            return max;
        }

        return _amount;
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        uint256 _beforeReward = IERC20Upgradeable(reward).balanceOf(address(this));

        // Get rewards
        LOCKER.getReward();

        // Rewards Math
        uint256 earnedReward =
            IERC20Upgradeable(reward).balanceOf(address(this)).sub(_beforeReward);

        uint256 vaultBefore = OXSOLID_VAULT.balanceOf(address(this));
        OXSOLID_VAULT.deposit(earnedReward);
        uint256 vaultAfter = OXSOLID_VAULT.balanceOf(address(this));

        _processExtraToken(address(OXSOLID_VAULT), vaultAfter.sub(vaultBefore));

        /// @dev Harvest must return the amount of want increased
        harvested = new TokenAmount[](1);

        harvested[0] = TokenAmount(reward, earnedReward);
    }

    // Example tend is a no-op which returns the values, could also just revert
    function _tend() internal override returns (TokenAmount[] memory tended){
        revert("no op"); // NOTE: For now tend is replaced by manualRebalance
    }

    /// @dev process all locks, to redeem
    /// @notice No Access Control Checks, anyone can unlock an expired lock
    function manualProcessExpiredLocks() public whenNotPaused {
        // Unlock vlOXD that is expired and redeem OXD back to this strat
        LOCKER.processExpiredLocks(false);
    }

    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData) {
        // We need to unlock funds if the lockedBalance (locked + unlocked) is greater than the balance (actively locked for this epoch)
        upkeepNeeded = LOCKER.lockedBalanceOf(address(this)) > LOCKER.balanceOf(address(this));
    }

    /// @dev Function for ChainLink Keepers to automatically process expired locks
    function performUpkeep(bytes calldata performData) external {
        // Works like this because it reverts if lock is not expired
        LOCKER.processExpiredLocks(false);
    }

    /// @dev Send all available OXD to the Vault
    /// @notice you can do this so you can earn again (re-lock), or just to add to the redemption pool
    function manualSendOXDToVault() external whenNotPaused {
        _onlyGovernance();
        uint256 oxdAmount = IERC20Upgradeable(want).balanceOf(address(this));
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
        uint256 balanceOfWant =
            IERC20Upgradeable(want).balanceOf(address(this));
        // Locked OXD in the locker
        uint256 balanceInLock = LOCKER.balanceOf(address(this));
        uint256 totalOXDBalance =
            balanceOfWant.add(balanceInLock);

        // Amount we want to have in lock
        uint256 newLockAmount = totalOXDBalance.mul(toLock).div(MAX_BPS);

        // We can't unlock enough, no-op
        if (newLockAmount <= balanceInLock) {
            return;
        }

        // If we're continuing, then we are going to lock something
        uint256 oxdToLock = newLockAmount.sub(balanceInLock);

        // We only lock up to the available OXD
        uint256 maxOXD = IERC20Upgradeable(want).balanceOf(address(this));
        if (oxdToLock > maxOXD) {
            // Just lock what we can
            LOCKER.lock(address(this), maxOXD, getBoostPayment());
        } else {
            // Lock proper
            LOCKER.lock(address(this), oxdToLock, getBoostPayment());
        }

        // If anything left, send to vault
        uint256 oxdLeft = IERC20Upgradeable(want).balanceOf(address(this));
        if(oxdLeft > 0){
            _transferToVault(oxdLeft);
        }
    }
}
