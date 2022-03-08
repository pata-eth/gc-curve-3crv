from pathlib import Path

from brownie import StrategyCurve3crv, accounts, config, network, project, web3, interface
from eth_utils import is_checksum_address
import click

API_VERSION = config["dependencies"][0].split("@")[-1]
Vault = project.load(
    Path.home() / ".brownie" / "packages" / config["dependencies"][0]
).Vault


def get_address(msg: str, default: str = None) -> str:
    val = click.prompt(msg, default=default)

    # Keep asking user for click.prompt until it passes
    while True:

        if is_checksum_address(val):
            return val
        elif addr := web3.ens.address(val):
            click.echo(f"Found ENS '{val}' [{addr}]")
            return addr

        click.echo(
            f"I'm sorry, but '{val}' is not a checksummed address or valid ENS record"
        )
        # NOTE: Only display default once
        val = click.prompt(msg)


def main():
    print(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    print(f"You are using: 'dev' [{dev.address}]")

    if input("Is there a Vault for this strategy already? y/[N]: ").lower() == "y":
        vault = Vault.at(get_address("Deployed Vault: "))
        assert vault.apiVersion() == API_VERSION
    else:
        print("You should deploy one vault using scripts from Vault project")
        return  # TODO: Deploy one using scripts from Vault project

    print(
        f"""
    Strategy Parameters

       api: {API_VERSION}
     token: {vault.token()}
      name: '{vault.name()}'
    symbol: '{vault.symbol()}'
    """
    )
    publish_source = click.confirm("Verify source on etherscan?")
    if input("Deploy Strategy? y/[N]: ").lower() != "y":
        return

    strategy = Strategy.deploy(vault, {"from": dev}, publish_source=publish_source)


def create_3crv_experimental_vault():
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    safe = ApeSafe("0xFB4464a18d18f3FF439680BBbCE659dB2806A187")
    registry = safe.contract("0xe2F12ebBa58CAf63fcFc0e8ab5A61b145bBA3462")
    gDaddy = safe.contract("0x22eAe41c7Da367b9a15e942EB6227DF849Bb498C")

    yv3CRV_address = registry.newExperimentalVault(
        strat,
        gDaddy.address, # governance: ybrain.chad.eth
        safe.address, # guardian: dev.ychad.eth
        safe.address, # rewards: treasury.ychad.eth
        "Curve 3crv", # name
        "yvCurve-3pool", # symbol
    {'from':dev}).return_value

    yv3Crv = interface.yvvault(yv3CRV_address)
    yv3Crv.setHealthCheck("0xE8228A2E7102ce51Bb73115e2964A233248398B9")
    yv3Crv.setManagement(safe)
    yv3Crv.setDepositLimit(50_000 * 1e18) # 50k limit
    yv3Crv.setManagementFee(0)

def create_3crv_strat():
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))

    yv3CRV_address = '0xFfe9fa48A805AC26eEF9DC750765C4dFB530f70b'
    # yv3Crv = interface.yvvault(yv3CRV_address)

    strategy = StrategyCurve3crv.deploy(yv3CRV_address, "Curve 3crv", {"from": dev})
