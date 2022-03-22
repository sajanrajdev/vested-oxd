from brownie import interface

from helpers.StrategyCoreResolver import StrategyCoreResolver
from rich.console import Console
from _setup.config import WANT

console = Console()


class StrategyResolver(StrategyCoreResolver):
    def get_strategy_destinations(self):
        """
        Track balances for all strategy implementations
        (Strategy Must Implement)
        """
        strategy = self.manager.strategy
        sett = self.manager.sett
        return {
            "locker": strategy.LOCKER(),
            "badgerTree": sett.badgerTree(),
        }

    def add_balances_snap(self, calls, entities):
        super().add_balances_snap(calls, entities)
        strategy = self.manager.strategy

        oxSolid = interface.IERC20(strategy.OXSOLID())

        calls = self.add_entity_balances_for_tokens(calls, "oxSolid", oxSolid, entities)

        return calls

    def confirm_harvest(self, before, after, tx):
        console.print("=== Compare Harvest ===")
        self.manager.printCompare(before, after)
        self.confirm_harvest_state(before, after, tx)

        # No autocompounding
        # super().confirm_harvest(before, after, tx)

        # NOTE: Harvesting increases this while management fee decreases this
        # assert after.get("sett.getPricePerFullShare") <= before.get(
        #     "sett.getPricePerFullShare"
        # )

        assert len(tx.events["Harvested"]) == 1
        event = tx.events["Harvested"][0]

        assert event["token"] == WANT

        assert event["amount"] > 0
        assert event["amount"] == after.get("sett.balance") - before.get("sett.balance")

        if before.get("sett.performanceFeeGovernance") > 0:
            assert after.balances("sett", "treasury") > before.balances(
                "sett", "treasury"
            )

        if before.get("sett.performanceFeeStrategist") > 0:
            assert after.balances("sett", "strategist") > before.balances(
                "sett", "strategist"
            )
