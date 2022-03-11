from brownie import *
from helpers.constants import MaxUint256


def test_setting_min_impacts_ratio_locked(
    strategy, sett, governance, want, deployer, locker
):
    rando = accounts[6]

    sett.setMin(5000, {"from": governance})  ## 50%

    startingBalance = want.balanceOf(deployer)
    want.approve(sett, MaxUint256, {"from": deployer})
    sett.deposit(startingBalance, {"from": deployer})

    sett.earn({"from": governance})

    ## Assert that 50% is invested and 50% is not
    assert want.balanceOf(sett) == startingBalance / 2  ## 50% is deposited in the vault
    assert (
        locker.lockedBalanceOf(strategy) >= startingBalance / 2
    )  ## 50% is locked (due to rounding between cvx and bcvx we use >=)
