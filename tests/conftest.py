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
    whale = accounts.at("0x3eA858248dB056c8Be3844323Bff9e3F5F1FE695", force=True)
    yield whale

@pytest.fixture(scope="module")
def xdai_whale(accounts):
    # Totally in it for the tech
    # Update this with a large holder of your want token (the largest EOA holder of LP)
    whale = accounts.at("0x9fc062032d4F2Fe7dAA601bd8B06C45F9c8f17Be", force=True)
    yield whale


# this is the amount of funds we have our whale deposit. adjust this as needed based on their wallet balance
@pytest.fixture(scope="module")
def amount():
    amount = 50_000 * 1e18
    yield amount


# this is the name we want to give our strategy
@pytest.fixture(scope="module")
def strategy_name():
    strategy_name = "StrategyCurve3crv"
    yield strategy_name


# Only worry about changing things above this line, unless you want to make changes to the vault or strategy.
# ----------------------------------------------------------------------- #


@pytest.fixture(scope="function")
def voter():
    yield interface.sms("0xFB4464a18d18f3FF439680BBbCE659dB2806A187")


@pytest.fixture(scope="function")
def crv():
    yield interface.crvToken("0x712b3d230F3C1c19db860d80619288b1F0BDd0Bd")


@pytest.fixture(scope="module")
def other_vault_strategy():
    yield interface.yvvault("0x7d86C052b20bA21b2E29a7D6cc1D2915F138c53a")


@pytest.fixture(scope="module")
def farmed():
    yield interface.gnoToken("0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb")#gno


@pytest.fixture(scope="module")
def healthCheck():
    yield interface.CommonHealthCheck("0xE8228A2E7102ce51Bb73115e2964A233248398B9")


# Define relevant tokens and contracts in this section
@pytest.fixture(scope="module")
def token():
    # this should be the address of the ERC-20 used by the strategy/vault
    token_address = "0x1337BedC9D22ecbe766dF105c9623922A27963EC"
    yield interface.crvPoolToken(token_address)


# zero address
@pytest.fixture(scope="module")
def zero_address():
    zero_address = "0x0000000000000000000000000000000000000000"
    yield zero_address


# gauge for the curve pool
@pytest.fixture(scope="module")
def gauge():
    # this should be the address of the convex deposit token
    gauge = "0x78CF256256C8089d68Cde634Cf7cDEFb39286470"
    yield interface.crvGauge(gauge)


# curve deposit pool
@pytest.fixture(scope="module")
def pool():
    poolAddress = interface.crvSwap("0x7f90122BF0700F9E7e1F688fe926940E8839F353")
    yield poolAddress


# Define any accounts in this section
# for live testing, governance is the strategist MS; we will update this before we endorse
# normal gov is ychad, 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52
@pytest.fixture(scope="module")
def gov(accounts):
    yield accounts.at("0x22eAe41c7Da367b9a15e942EB6227DF849Bb498C", force=True)


@pytest.fixture(scope="module")
def strategist_ms(accounts):
    # like governance, but better
    yield accounts.at("0xFB4464a18d18f3FF439680BBbCE659dB2806A187", force=True)


@pytest.fixture(scope="module")
def keeper(accounts):
    yield accounts.at("0xC27DdC26F48724AD90E4d152940e4981af7Ed50d", force=True)


@pytest.fixture(scope="module")
def rewards(accounts):
    yield accounts.at("0xC1c734c36a1Fb28502c48239995FC2b2d0031f81", force=True)


@pytest.fixture(scope="module")
def guardian(accounts):
    yield accounts[2]


@pytest.fixture(scope="module")
def management(accounts):
    yield accounts[3]


@pytest.fixture(scope="module")
def strategist(accounts):
    strategist = accounts.at("0xC1c734c36a1Fb28502c48239995FC2b2d0031f81", force=True)
    yield strategist


# # list any existing strategies here
# @pytest.fixture(scope="module")
# def LiveStrategy_1():
#     yield Contract("0xC1810aa7F733269C39D640f240555d0A4ebF4264")


# use this if you need to deploy the vault
@pytest.fixture(scope="function")
def vault(pm, gov, rewards, guardian, management, token, chain, xdai_whale):
    Vault = pm(config["dependencies"][0]).Vault
    xdai_whale.transfer(gov, "1 ether")
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, {'from':gov})
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    chain.sleep(1)
    yield vault


# use this if your vault is already deployed
# @pytest.fixture(scope="function")
# def vault(pm, gov, rewards, guardian, management, token, chain):
#     vault = Contract("0x497590d2d57f05cf8B42A36062fA53eBAe283498")
#     yield vault


# replace the first value with the name of your strategy
@pytest.fixture(scope="function")
def strategy(
    StrategyCurve3crv,
    strategist,
    keeper,
    vault,
    gov,
    guardian,
    token,
    healthCheck,
    chain,
    pool,
    strategy_name,
    gauge,
    strategist_ms,
    xdai_whale
):
    # make sure to include all constructor parameters needed here
    xdai_whale.transfer(strategist, "1 ether")
    xdai_whale.transfer(strategist_ms, "1 ether")
    strategy = strategist.deploy(
        StrategyCurve3crv,
        vault,
        strategy_name,
    )

    strategy.setKeeper(keeper, {"from": gov})
    # set our management fee to zero so it doesn't mess with our profit checking
    vault.setManagementFee(0, {"from": gov})
    # add our new strategy
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    strategy.setHealthCheck(healthCheck, {"from": gov})
    strategy.setDoHealthCheck(True, {"from": gov})
    chain.mine(1)
    chain.sleep(1)
    yield strategy


# use this if your strategy is already deployed
# @pytest.fixture(scope="function")
# def strategy():
#     # parameters for this are: strategy, vault, max deposit, minTimePerInvest, slippage protection (10000 = 100% slippage allowed),
#     strategy = Contract("0xC1810aa7F733269C39D640f240555d0A4ebF4264")
#     yield strategy
