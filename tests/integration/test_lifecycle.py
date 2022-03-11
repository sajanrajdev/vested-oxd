from brownie import *
from helpers.constants import MaxUint256


def test_setting_min_impacts_ratio_locked(
    strategy, vault, governance, want, deployer, locker
):
    rando = accounts[6]

    vault.setToEarnBps(5000, {"from": governance})  ## 50%

    startingBalance = want.balanceOf(deployer)
    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(startingBalance, {"from": deployer})

    vault.earn({"from": governance})

    ## Assert that 50% is invested and 50% is not
    assert (
        abs(want.balanceOf(vault) - startingBalance // 2) <= 1
    )  ## 50% is deposited in the vault
    assert (
        locker.lockedBalanceOf(strategy) >= startingBalance // 2
    )  ## 50% is locked (due to rounding between oxd and boxd we use >=)
