from brownie import ZERO_ADDRESS, reverts


def test_setters(
    gov,
    strategy,
    strategist,
    chain,
    whale,
    token,
    vault,
    amount,
    strategist_ms,
):

    # test our manual harvest trigger
    strategy.setForceHarvestTriggerOnce(True, {"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    print("\nShould we harvest? Should be true.", tx)
    assert tx == True

    strategy.setForceHarvestTriggerOnce(False, {"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    print("\nShould we harvest? Should be false.", tx)
    assert tx == False

    # test our manual harvest trigger, and that a harvest turns it off
    strategy.setForceHarvestTriggerOnce(True, {"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    print("\nShould we harvest? Should be true.", tx)
    assert tx == True
    strategy.harvest({"from": gov})
    tx = strategy.harvestTrigger(0, {"from": gov})
    print("\nShould we harvest? Should be false.", tx)
    assert tx == False

    ## deposit to the vault after approving
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})

    # test our setters in baseStrategy and our main strategy
    strategy.setDebtThreshold(1, {"from": gov})
    strategy.setMaxReportDelay(0, {"from": gov})
    strategy.setMaxReportDelay(1e18, {"from": gov})
    strategy.setMetadataURI(0, {"from": gov})
    strategy.setMinReportDelay(100, {"from": gov})
    strategy.setProfitFactor(1000, {"from": gov})
    strategy.setRewards(gov, {"from": strategist})

    strategy.setStrategist(strategist, {"from": gov})
    name = strategy.name()
    print("Strategy Name:", name)

    # health check stuff
    chain.sleep(86400)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(86400)
    strategy.harvest({"from": gov})
    chain.sleep(86400)

    with reverts():
        strategy.setKeeper(ZERO_ADDRESS, {"from": gov})
    with reverts():
        strategy.setRewards(ZERO_ADDRESS, {"from": strategist})
    with reverts():
        strategy.setStrategist(ZERO_ADDRESS, {"from": gov})
    with reverts():
        strategy.setDoHealthCheck(False, {"from": whale})
    with reverts():
        strategy.setEmergencyExit({"from": whale})
    with reverts():
        strategy.setMaxReportDelay(1000, {"from": whale})
    with reverts():
        strategy.setRewards(strategist, {"from": whale})

    # try a health check with ZERO_ADDRESS address as health check
    strategy.setHealthCheck(ZERO_ADDRESS, {"from": gov})
    strategy.setDoHealthCheck(True, {"from": gov})
    strategy.harvest({"from": gov})

    # try a health check with random contract as health check
    strategy.setHealthCheck(gov, {"from": gov})
    strategy.setDoHealthCheck(True, {"from": gov})


    # set emergency exit last
    strategy.setEmergencyExit({"from": gov})
    with reverts():
        strategy.setEmergencyExit({"from": gov})
