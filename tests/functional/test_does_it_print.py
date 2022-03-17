import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager

MAX_BASIS = 10000
SECS_PER_YEAR = 31_556_952


def test_is_profitable(deployed):
    deployer = deployed.deployer
    vault = deployed.vault
    strategy = deployed.strategy
    want = deployed.want
    randomUser = accounts[6]

    initial_balance = want.balanceOf(deployer)

    settKeeper = accounts.at(vault.keeper(), force=True)

    snap = SnapshotManager(vault, strategy, "StrategySnapshot")

    reward = interface.IERC20(strategy.bOxSolid())
    reward_before = reward.balanceOf(vault.treasury())

    # Deposit
    assert want.balanceOf(deployer) > 0

    depositAmount = int(want.balanceOf(deployer) * 0.8)
    assert depositAmount > 0

    want.approve(vault.address, MaxUint256, {"from": deployer})

    snap.settDeposit(depositAmount, {"from": deployer})

    # Earn
    with brownie.reverts("onlyAuthorizedActors"):
        vault.earn({"from": randomUser})

    snap.settEarn({"from": settKeeper})

    chain.sleep(86400 * 250)  ## Wait 250 days
    chain.mine(1)

    snap.settHarvest({"from": settKeeper})

    strategy.setProcessLocksOnRebalance(True, {"from": deployed.governance})
    strategy.manualRebalance(0, {"from": deployed.governance})

    snap.settWithdrawAll({"from": deployer})

    ending_balance = want.balanceOf(deployer)

    initial_balance_with_fees = initial_balance * (
        1
        - (vault.withdrawalFee() / MAX_BASIS)
        - (vault.managementFee() * 86400 * 250 / SECS_PER_YEAR)
    )

    print("Initial Balance")
    print(initial_balance)
    print("initial_balance_with_fees")
    print(initial_balance_with_fees)
    print("Ending Balance")
    print(ending_balance)

    reward_after = reward.balanceOf(vault.treasury())

    ## Custom check for rewards being sent to gov as resolver is too complex
    assert reward_after > reward_before

    assert ending_balance > initial_balance_with_fees
