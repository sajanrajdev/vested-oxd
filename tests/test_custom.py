import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""


def test_after_wait_withdrawSome_unlocks_for_caller(setup_strat, want, vault, deployer):
    ## Try to withdraw all, fail because locked
    initial_dep = vault.balanceOf(deployer)

    with brownie.reverts():
        vault.withdraw(initial_dep, {"from": deployer})

    chain.sleep(86400 * 250)  # 250 days so lock expires

    initial_b = want.balanceOf(deployer)

    ## Not enough liquid balance
    assert want.balanceOf(vault) + want.balanceOf(setup_strat) < initial_dep

    ## Yet we pull it off, because it unlocks for us
    vault.withdraw(
        initial_dep, {"from": deployer}
    )  ## Because we try to withdraw more than

    assert want.balanceOf(deployer) > initial_b  ## Want increased

    ## More accurately
    assert want.balanceOf(deployer) - initial_b >= (
        initial_dep * (10_000 - vault.withdrawalFee()) // 10_000 - 1
    )


def test_if_change_min_some_can_be_withdraw_easy(setup_strat, vault, deployer, want):

    initial_b = want.balanceOf(deployer)
    ## TODO / CHECK This is the ideal math but it seems to revert on me
    ## min = (vault.MAX_BPS() - vault.toEarnBps() - 1) * vault.balanceOf(deployer) / 10000
    min = (vault.MAX_BPS() - vault.toEarnBps() - 1) * vault.balanceOf(deployer) / 10000

    vault.withdraw(min, {"from": deployer})

    assert (
        want.balanceOf(deployer) > initial_b
    )  ## You can withdraw as long as it's less than min


def test_after_deposit_locker_has_more_funds(
    locker, deployer, vault, strategy, want, governance
):
    """
    We have to check that the Locker get's more funds after a deposit
    """

    intitial_in_locker = locker.lockedBalanceOf(strategy) + locker.balanceOf(strategy)

    # Setup
    startingBalance = want.balanceOf(deployer)
    depositAmount = startingBalance // 2
    assert startingBalance >= depositAmount
    assert startingBalance >= 0
    # End Setup
    # Deposit
    assert want.balanceOf(vault) == 0

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    available = vault.available()
    assert available > 0

    vault.earn({"from": governance})

    chain.sleep(10000 * 13)  # Mine so we get some interest

    ## TEST: Did the proxy get more want?
    assert (
        locker.lockedBalanceOf(strategy) + locker.balanceOf(strategy)
        > intitial_in_locker
    )


def test_delegation_was_correct(strategy):
    delegate = strategy.DELEGATE()
    voting_snapshot = interface.IVotingSnapshot(strategy.VOTING_SNAPSHOT())
    assert voting_snapshot.voteDelegateByAccount(strategy) == delegate

    pool = "0xDf9181Fe9a39Ec5D845D7351309C2D408a0dA4d6"
    voting_snapshot.vote(pool, 1, {"from": delegate})
