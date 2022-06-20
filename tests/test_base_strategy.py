from scripts.utils import getSnapshot


def test_base_strategy(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    amount,
    crv,
    gno,
    gauge,
    gaugeFactory,
):
    ## deposit to the vault after approving
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})

    # test our harvestTrigger for when we have a profit (don't normally need this)
    # our whale donates dust to the vault, what a nice person!
    donation = 1e16
    token.transfer(strategy, donation, {"from": whale})
    chain.sleep(86400 * 4)  # fast forward so our min delay is passed
    chain.mine(1)

    getSnapshot(vault, strategy, crv, gno, gauge, gaugeFactory)

    assert strategy.harvestTrigger(0, {"from": gov}), "This must have been TRUE"

    # test all of our random shit
    strategy.doHealthCheck()
    strategy.healthCheck()
    strategy.apiVersion()
    strategy.name()
    strategy.delegatedAssets()
    strategy.vault()
    strategy.strategist()
    strategy.rewards()
    strategy.keeper()
    strategy.want()
    strategy.minReportDelay()
    strategy.maxReportDelay()
    strategy.profitFactor()
    strategy.debtThreshold()
    strategy.emergencyExit()
