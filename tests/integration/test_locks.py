import pytest
import brownie
from brownie import *
from helpers.constants import MaxUint256


def test_withdraw_more_than_liquid_tries_to_unlock(
    setup_strat, deployer, sett, strategy, want, locker, deployed
):

    ## Try to withdraw all, fail because locked
    initial_dep = sett.balanceOf(deployer)

    with brownie.reverts():
        sett.withdraw(initial_dep, {"from": deployer})

    can_withdraw = want.balanceOf(sett) + want.balanceOf(setup_strat)

    with brownie.reverts():
        sett.withdraw(can_withdraw + 100)  ## Expect to fail as lock is not expired


def test_wait_for_all_locks_can_withdraw_easy_after_manual_rebalance(
    setup_strat, deployer, sett, strategy, want, locker, deployed
):
    ## Strategy has funds and they are locked
    ## Wait a bunch and see if you can withdraw all

    initial_dep = sett.balanceOf(deployer)

    ## Wait to unlock
    chain.sleep(86400 * 250)  # 250 days so lock expires
    strategy.setProcessLocksOnRebalance(True, {"from": deployed.governance})

    strategy.manualRebalance(0, {"from": deployed.governance})

    ## Try to withdraw all
    sett.withdraw(initial_dep, {"from": deployer})

    assert (
        want.balanceOf(deployer) * 0.998 > initial_dep
    )  ## Assert that we have not lost more than 10 basis points
    ## If this passes, implicitly it means the lock was expire and we were able to withdraw
    ## NOTE: We have to call strategy.manualRebalance with an amount that unlocks enough funds or we won't be able to withdraw
