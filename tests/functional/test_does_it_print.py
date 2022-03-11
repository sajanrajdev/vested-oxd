import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from _config import DEFAULT_WITHDRAWAL_FEE

MAX_BASIS = 10000


def test_is_profitable(deployed):
    deployer = deployed.deployer
    vault = deployed.vault
    controller = deployed.controller
    strategy = deployed.strategy
    want = deployed.want
    randomUser = accounts[6]

    initial_balance = want.balanceOf(deployer)

    settKeeper = accounts.at(vault.keeper(), force=True)

    snap = SnapshotManager(vault, strategy, controller, "StrategySnapshot")

    reward = interface.IERC20(strategy.OXSOLID_VAULT())
    reward_before = reward.balanceOf(strategy.strategist())

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
        1 - (DEFAULT_WITHDRAWAL_FEE / MAX_BASIS)
    )

    print("Initial Balance")
    print(initial_balance)
    print("initial_balance_with_fees")
    print(initial_balance_with_fees)
    print("Ending Balance")
    print(ending_balance)

    reward_after = reward.balanceOf(strategy.strategist())

    ## Custom check for rewards being sent to gov as resolver is too complex
    assert reward_after > reward_before

    assert ending_balance > initial_balance_with_fees
