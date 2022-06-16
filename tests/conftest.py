import pytest
from brownie import config, Wei, Contract, interface

# Snapshots the chain before each test and reverts after test completion.
@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass


@pytest.fixture(scope="module")
def whale(accounts):
    # Totally in it for the tech
    # Update this with a large holder of your want token (the largest EOA holder of LP)
    yield accounts.at("0x59e5D93c06F8390D2072bdaB5D6d66f7Cd15ab23", force=True)


@pytest.fixture(scope="module")
def xdai_whale(accounts):
    # Totally in it for the tech
    # Update this with a large holder of your want token (the largest EOA holder of LP)
    yield accounts.at("0x9fc062032d4F2Fe7dAA601bd8B06C45F9c8f17Be", force=True)


# this is the amount of funds we have our whale deposit. adjust this as needed based on their wallet balance
@pytest.fixture(scope="module")
def amount(token):
    yield (5_000 * 10 ** token.decimals())


# this is the name we want to give our strategy
@pytest.fixture(scope="module")
def strategy_name():
    yield "StrategyCurve3crv"


# Only worry about changing things above this line, unless you want to make changes to the vault or strategy.
# ----------------------------------------------------------------------- #


@pytest.fixture(scope="function")
def crv():
    yield interface.ERC20("0x712b3d230F3C1c19db860d80619288b1F0BDd0Bd")


# strategy to migrate from
@pytest.fixture(scope="module")
def other_vault_strategy(pm):
    strategy = pm(config["dependencies"][0]).interface.StrategyAPI
    yield strategy("0x404647837B1D3454E9C2e23D9ffeEBD3442D5C4A")


@pytest.fixture(scope="module")
def gno():
    yield interface.ERC20(
        "0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb"
    )  # gno bridged from mainnet


@pytest.fixture(scope="module")
def healthCheck():
    yield interface.HealthCheck("0xE8228A2E7102ce51Bb73115e2964A233248398B9")


# Define relevant tokens and contracts in this section
@pytest.fixture(scope="module")
def token():
    # this should be the address of the ERC-20 used by the strategy/vault
    yield interface.ERC20("0x1337BedC9D22ecbe766dF105c9623922A27963EC")


# gauge for the curve gauge
@pytest.fixture(scope="module")
def gauge():
    yield interface.IGauge("0xB721Cc32160Ab0da2614CC6aB16eD822Aeebc101")


@pytest.fixture(scope="module")
def gaugeFactory():
    yield interface.IGaugeFactory("0xabC000d88f23Bb45525E447528DBF656A9D55bf5")


@pytest.fixture(scope="module")
def tradeFactory():
    yield interface.ITradeFactory(
        "0xabC000d88f23Bb45525E447528DBF656A9D55bf5"
    )  # TODO: update address


# Define any accounts in this section
# for live testing, governance is the strategist MS; we will update this before we endorse
# normal gov is ychad, 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
@pytest.fixture(scope="module")
def gov(accounts):
    yield accounts.at("0x22eAe41c7Da367b9a15e942EB6227DF849Bb498C", force=True)


@pytest.fixture(scope="module")
def keeper(accounts):
    yield accounts.at("0x2757ae02f65db7ce8cf2b2261c58f07a0170e58e", force=True)


@pytest.fixture(scope="module")
def rewards(accounts):
    yield accounts.at("0x2757ae02f65db7ce8cf2b2261c58f07a0170e58e", force=True)


@pytest.fixture(scope="module")
def guardian(accounts):
    yield accounts.at("0x2757ae02f65db7ce8cf2b2261c58f07a0170e58e", force=True)


@pytest.fixture(scope="module")
def management(accounts):
    yield accounts.at("0xFB4464a18d18f3FF439680BBbCE659dB2806A187", force=True)


@pytest.fixture(scope="module")
def strategist_ms(accounts):
    # like governance, but better
    yield accounts.at("0xFB4464a18d18f3FF439680BBbCE659dB2806A187", force=True)


@pytest.fixture(scope="module")
def strategist(accounts):
    strategist = accounts.at("0x2757ae02f65db7ce8cf2b2261c58f07a0170e58e", force=True)
    yield strategist


# use this if your vault is already deployed
# @pytest.fixture(scope="function")
# def vault(pm, gov, management):
#     vault = pm(config["dependencies"][0]).Vault
#     vault = vault.at("0xFfe9fa48A805AC26eEF9DC750765C4dFB530f70b")
#     vault.setGovernance(gov, {"from": management})
#     vault.acceptGovernance({"from": gov})
#     vault.setManagementFee(200, {"from": gov})
#     vault.setPerformanceFee(2000, {"from": gov})
#     yield vault


# use a fresh vault
@pytest.fixture(scope="function")
def vault(pm, gov, rewards, strategist, management, token, chain):
    Vault = pm(config["dependencies"][0]).Vault
    vault = strategist.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", strategist)
    vault.setDepositLimit(Wei("50_000 ether"), {"from": gov})
    vault.setManagement(management, {"from": gov})
    vault.setManagementFee(200, {"from": gov})
    vault.setPerformanceFee(2000, {"from": gov})
    yield vault


# replace the first value with the name of your strategy
@pytest.fixture(scope="function")
def strategy(
    StrategyCurve3crv,
    strategist,
    vault,
    gov,
    strategy_name,
    other_vault_strategy,
    xdai_whale,
    tradeFactory,
):
    # make sure to include all constructor parameters needed here
    xdai_whale.transfer(strategist, "1 ether")

    strategy = StrategyCurve3crv.deploy(
        vault,
        strategy_name,
        {"from": strategist},
    )

    # add our new strategy
    vault.addStrategy(strategy, 10_000, 0, 2**256 - 1, 0, {"from": gov})
    # other_vault_strategy.harvest({"from": gov})
    # vault.migrateStrategy(other_vault_strategy, strategy, {"from": gov})
    # vault.updateStrategyPerformanceFee(strategy, 0, {"from": gov})
    strategy.setDoHealthCheck(True, {"from": gov})
    strategy.setTradeFactory(tradeFactory, {"from": gov})
    yield strategy
