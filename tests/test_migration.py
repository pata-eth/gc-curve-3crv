from scripts.utils import getSnapshot
import math


def test_migration(
    StrategyCurve3crv,
    gov,
    token,
    vault,
    guardian,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    healthCheck,
    amount,
    strategy_name,
    gauge,
    gaugeFactory,
    tradeFactory,
    crv,
    gno,
):

    ## deposit to the vault after approving
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # deploy our new strategy
    new_strategy = StrategyCurve3crv.deploy(vault, strategy_name, {"from": strategist})
    total_old = strategy.estimatedTotalAssets()

    # can we harvest an unactivated strategy? should be no
    # under our new method of using min and maxDelay, this no longer matters or works
    # tx = new_strategy.harvestTrigger(0, {"from": gov})
    # print("\nShould we harvest? Should be False.", tx)
    # assert tx == False

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # migrate our old strategy
    getSnapshot(vault, strategy, crv, gno, gauge, gaugeFactory)
    strategy.harvest({"from": gov})
    getSnapshot(vault, strategy, crv, gno, gauge, gaugeFactory)

    # Reward tokens to migrate
    crvToMigrate = crv.balanceOf(strategy)
    gnoToMigrate = gno.balanceOf(strategy)

    vault.migrateStrategy(strategy, new_strategy, {"from": gov})
    new_strategy.setDoHealthCheck(True, {"from": gov})
    new_strategy.setTradeFactory(tradeFactory, {"from": gov})

    # Reward tokens migrated
    crvMigrated = crv.balanceOf(new_strategy)
    gnoMigrated = gno.balanceOf(new_strategy)

    assert crvToMigrate == crvMigrated
    assert gnoToMigrate == gnoMigrated

    # assert that our old strategy is empty
    updated_total_old = strategy.estimatedTotalAssets()
    assert updated_total_old == 0

    # harvest to get funds back in strategy
    chain.sleep(1)
    getSnapshot(vault, new_strategy, crv, gno, gauge, gaugeFactory)
    new_strategy.harvest({"from": gov})
    getSnapshot(vault, new_strategy, crv, gno, gauge, gaugeFactory)
    new_strat_balance = new_strategy.estimatedTotalAssets()

    # confirm we made money, or at least that we have about the same
    assert new_strat_balance >= total_old or math.isclose(
        new_strat_balance, total_old, abs_tol=5
    )

    startingVault = vault.totalAssets()
    print("\nVault starting assets with new strategy: ", startingVault)

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # Test out our migrated strategy, confirm we're making a profit
    new_strategy.harvest({"from": gov})
    vaultAssets_2 = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    assert vaultAssets_2 >= startingVault or math.isclose(
        vaultAssets_2, startingVault, abs_tol=5
    )
    print("\nAssets after 1 day harvest: ", vaultAssets_2)
