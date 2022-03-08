from brownie import StrategyCurve3crv, accounts, config, network, project, web3


def main():
    with open('./build/contracts/StrategyCurve3crvFlat.sol', 'w') as f:
        StrategyCurve3crv.get_verification_info()
        f.write(StrategyCurve3crv._flattener.flattened_source)
