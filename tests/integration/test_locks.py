import pytest
import brownie
from brownie import *
from helpers.constants import MaxUint256


def test_withdraw_more_than_liquid_tries_to_unlock(
    setup_strat, deployer, vault, strategy, want, locker, deployed
):

    ## Try to withdraw all, fail because locked
    initial_dep = vault.balanceOf(deployer)

    with brownie.reverts():
        vault.withdraw(initial_dep, {"from": deployer})

    can_withdraw = want.balanceOf(vault) + want.balanceOf(setup_strat)

    with brownie.reverts():
        vault.withdraw(can_withdraw + 100)  ## Expect to fail as lock is not expired
