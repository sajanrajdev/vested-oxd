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


def test_after_wait_withdrawSome_unlocks_for_caller(setup_strat, want, sett, deployer):
    ## Try to withdraw all, fail because locked
    initial_dep = sett.balanceOf(deployer)

    with brownie.reverts():
        sett.withdraw(initial_dep, {"from": deployer})

    chain.sleep(86400 * 250)  # 250 days so lock expires

    initial_b = want.balanceOf(deployer)

    ## Not enough liquid balance
    assert want.balanceOf(sett) + want.balanceOf(setup_strat) < initial_dep

    ## Yet we pull it off, because it unlocks for us
    sett.withdraw(
        initial_dep, {"from": deployer}
    )  ## Because we try to withdraw more than

    assert want.balanceOf(deployer) > initial_b  ## Want increased

    ## More accurately
    assert want.balanceOf(deployer) - initial_b >= (
        initial_dep * (10_000 - setup_strat.withdrawalFee()) / 10_000 - 1
    )


def test_if_change_min_some_can_be_withdraw_easy(setup_strat, sett, deployer, want):

    initial_b = want.balanceOf(deployer)
    ## TODO / CHECK This is the ideal math but it seems to revert on me
    ## min = (sett.max() - sett.min() - 1) * sett.balanceOf(deployer) / 10000
    min = (sett.max() - sett.min() - 1) * sett.balanceOf(deployer) / 10000

    sett.withdraw(min, {"from": deployer})

    assert (
        want.balanceOf(deployer) > initial_b
    )  ## You can withdraw as long as it's less than min


def test_after_deposit_locker_has_more_funds(
    locker, deployer, sett, strategy, want, staking
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
    assert want.balanceOf(sett) == 0

    want.approve(sett, MaxUint256, {"from": deployer})
    sett.deposit(depositAmount, {"from": deployer})

    available = sett.available()
    assert available > 0

    sett.earn({"from": deployer})

    chain.sleep(10000 * 13)  # Mine so we get some interest

    ## TEST: Did the proxy get more want?
    assert (
        locker.lockedBalanceOf(strategy) + locker.balanceOf(strategy)
        > intitial_in_locker
    )


def test_delegation_was_correct(strategy):
    target_delegate = strategy.DELEGATE()
    voting_snapshot = interface.IVotingSnapshot(strategy.votingSnaphot)
    assert voting_snapshot.voteDelegatedByAccount(strategy) == target_delegate
