# import brownie
# from brownie import Contract
# from brownie import config
# import math
#
# def test_very_simple_migration(
#     StrategyCurve3crv,
#     gov,
#     token,
#     vault,
#     strategist,
#     whale,
#     strategy,
#     chain,
#     strategist_ms,
#     gauge,
#     voter,
#     amount,
# ):
#
#     startingWhale = token.balanceOf(whale)
#     token.approve(vault, 2 ** 256 - 1, {"from": whale})
#     print(f"{startingWhale/1e18:_}")
#     vault.deposit({"from": whale})
#     newWhale = token.balanceOf(whale)
#
#     # change our optimal deposit asset
#     strategy.setOptimal(0, {"from": gov})
#
#     # this is part of our check into the staking contract balance
#     stakingBeforeHarvest = gauge.balanceOf(strategy)
#
#     assert stakingBeforeHarvest == 0
#
#     chain.sleep(1)
#     chain.mine(1)
#
#     tx = strategy.harvest({"from": gov})
#     # chain.mine(1, timedelta=43200)
#
#     new_strategy = strategist.deploy(
#         StrategyCurve3crv,
#         vault,
#         "segunda",
#     )
#
#     # sleep for a day
#     chain.sleep(86400)
#
#     # vault.migrateStrategy(strategy, new_strategy, {"from": gov})
#
#     assert False
