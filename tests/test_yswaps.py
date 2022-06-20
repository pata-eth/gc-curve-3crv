from brownie import ZERO_ADDRESS, reverts


def test_yswap_functions(
    gov,
    strategist,
    strategy,
    tradeHandler,
    crv,
    gno,
):
    assert strategy.tradeHandler() == tradeHandler, "Trade Handler nto setup correctly"

    strategy.disableTradeHandlerPermissions({"from": gov})

    assert strategy.tradeHandler() == ZERO_ADDRESS

    with reverts("!authorized"):
        strategy.updateTradeHandler(tradeHandler, {"from": strategist})

    strategy.updateTradeHandler(tradeHandler.address, {"from": gov})

    assert strategy.tradeHandler() == tradeHandler, "Trade Handler nto setup correctly"

    crv.allowance(strategy, tradeHandler) == 0

    gno.allowance(strategy, tradeHandler) == 0
