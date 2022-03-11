import pytest
import brownie
from brownie import *
from helpers.constants import MaxUint256
from eth_utils import encode_hex

"""
  Checks that ratio changes allow different investment profiles
"""

SETT_ADDRESS = "0xfd05D3C7fe2924020620A8bE4961bBaA747e6305"

STRAT_ADDRESS = "0x3ff634ce65cDb8CC0D569D6d1697c41aa666cEA9"

@pytest.fixture
def strat_proxy():
    return MyStrategy.at(STRAT_ADDRESS)
@pytest.fixture
def sett_proxy():
    return SettV4.at(SETT_ADDRESS)

@pytest.fixture
def real_strategist(strat_proxy):
    return accounts.at(strat_proxy.strategist(), force=True)

## Forces reset before each test
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass

@pytest.fixture(autouse=True)
def whale():
    """
        https://etherscan.io/token/0xfd05D3C7fe2924020620A8bE4961bBaA747e6305?a=0x53461e4fddcc1385f1256ae24ce3505be664f249
        Has about 200k tokens
        Second unlock is around 200k so they can't withdraw all but they can withdraw a bunch
    """
    return accounts.at("0x53461e4fddcc1385f1256ae24ce3505be664f249", force=True)

@pytest.fixture(autouse=True)
def fish():
    """
        https://etherscan.io/token/0xfd05D3C7fe2924020620A8bE4961bBaA747e6305?a=0xd50f649a2c9fd7ae88c223da80e985d71de45593
        Has about 17k tokens
        Second unlock is around 200k so they can just withdrawAll
    """
    return accounts.at("0xd50f649a2c9fd7ae88c223da80e985d71de45593", force=True)
    
## NOTE: use https://dune.xyz/tianqi/Convex-Locked-CVX to figure out unlocking schedule

KNOWN_UNLOCK_TIME = 1643846400 ## Change every time you need to make the experiment

LOCK_INDEX = 1 ## UNUSED, convenience

EXPECTED_AMOUNT = 501132161317262692740431 ## Used to check we get the amount from lock
## just go to https://etherscan.io/address/0xd18140b4b819b895a3dba5442f959fa44994af50#readContract
## userLocks and get the amount and time to lock so you can run an accurate test each week / unlock period

def test_real_world_unlock(
    strat_proxy, sett_proxy, governance, want, whale, fish
):

    initial_bal = want.balanceOf(strat_proxy)

    modest_amount = 10_000e18 ## 10k CVX

    ## Can't withdraw all without unlocking
    with brownie.reverts("Withdrawal Safety Check"):
        sett_proxy.withdrawAll({"from": whale})

    with brownie.reverts("Withdrawal Safety Check"):
        sett_proxy.withdrawAll({"from": fish})

    with brownie.reverts("Withdrawal Safety Check"):
        sett_proxy.withdraw(modest_amount, {"from": whale}) ## Can't withdraw as not unlocked




    ## Sleep until unlock time
    if(chain.time() < KNOWN_UNLOCK_TIME):
      chain.sleep(KNOWN_UNLOCK_TIME - chain.time() + 1)

    ## Process unlock
    strat_proxy.manualProcessExpiredLocks({"from": governance})

    assert want.balanceOf(strat_proxy) >= initial_bal + EXPECTED_AMOUNT
    assert sett_proxy.getPricePerFullShare() == 1e18 ## no increase in ppfs, just unlock

    ## Whale can withdraw 10k shares here easily
    sett_proxy.withdraw(modest_amount, {"from": whale})

    ## Then transfer to vault
    strat_proxy.manualSendCVXToVault({"from": governance})

    ## Whale can withdraw more shares as well
    sett_proxy.withdraw(modest_amount, {"from": whale})

    ## Because whale has still around 170k shares, they can withdraw
    sett_proxy.withdrawAll({"from": whale})

    ## Fish can withdraw all
    sett_proxy.withdrawAll({"from": fish})



