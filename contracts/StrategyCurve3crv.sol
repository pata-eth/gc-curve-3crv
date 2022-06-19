// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";

interface ITradeHandler {
    /** 
    @notice Registers trading pair to ySwaps
    @param _tokenIn Token currently in strategy that we'd like to swap out
    @param _tokenOut Token that we'd like to swap `_tokenIn` for
    */
    function enable(address _tokenIn, address _tokenOut) external;
}

interface IGauge is IERC20 {
    /// @notice Deposit `_value` LP tokens for `msg.sender` without claiming pending rewards (if any)
    /// @param _value Number of LP tokens to deposit
    function deposit(uint256 _value) external;

    /// @notice Claim third-party reward tokens (e.g., GNO)
    function claim_rewards() external;

    /// @notice Get the number of claimable CRV tokens per user
    /// @dev This function should be manually changed to "view" in the ABI
    /// @param addr User address to check balance for
    /// @return uint256 number of claimable tokens per user
    function claimable_tokens(address addr) external returns (uint256);

    /// @notice Estimate claimable third-party reward tokens per user
    /// @param _addressToCheck User address to check balance for
    /// @param _rewardToken Third-party token
    /// @return uint256 number of claimable tokens per user
    function claimable_reward(address _addressToCheck, address _rewardToken)
        external
        view
        returns (uint256);

    /// @notice Withdraw `_value` LP tokens without claiming pending rewards (if any)
    /// @param _value Number of LP tokens to withdraw
    function withdraw(uint256 _value) external;

    /// @notice CRV inflation assigned to the gauge for week `week`
    /// @param week weeks
    function inflation_rate(uint256 week) external view returns (uint256);
}

interface IGaugeFactory is IERC20 {
    /// @notice Mints CRV accrued by the user address - msg.sender
    /// @param _gauge Address of the gauge
    function mint(address _gauge) external;
}

abstract contract StrategyCurveBase is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    // these should stay the same across different wants.
    IERC20 public constant crv =
        IERC20(0x712b3d230F3C1c19db860d80619288b1F0BDd0Bd);
    IERC20 public constant gno =
        IERC20(0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb);

    // Trade Handler (ySwaps)
    event UpdatedTradeHandler();
    event RevokedTradeHandler();

    address public tradeHandler;

    bool internal forceHarvestTriggerOnce; // only set this to true externally when we want to trigger our keepers to harvest for us

    string internal stratName; // set our strategy name here

    /* ========== CONSTRUCTOR ========== */

    constructor(address _vault) public BaseStrategy(_vault) {}

    /* ========== VIEWS ========== */

    function name() external view override returns (string memory) {
        return stratName;
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    /**
    @notice Returns the strategy's balance of 3CRV LP tokens.
    @return wantBalance of 3CRV LP tokens
    */
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    /* ========== SETTERS ========== */

    // These functions are useful for setting parameters of the strategy that may need to be adjusted.
    /**
    @notice Force a manual harvest with the keeper as needed.
    @param _forceHarvestTriggerOnce boolean. 
    */
    function setForceHarvestTriggerOnce(bool _forceHarvestTriggerOnce)
        external
        onlyAuthorized
    {
        forceHarvestTriggerOnce = _forceHarvestTriggerOnce;
    }
}

contract StrategyCurve3crv is StrategyCurveBase {
    /* ========== STATE VARIABLES ========== */
    // these will likely change across different wants.

    // Curve contracts
    IGauge public constant gauge =
        IGauge(0xB721Cc32160Ab0da2614CC6aB16eD822Aeebc101); // Curve gauge contract, most are tokenized, held by strategy

    IGaugeFactory public constant gaugeFactory =
        IGaugeFactory(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _vault,
        string memory _name,
        address _tradeHandler
    ) public StrategyCurveBase(_vault) {
        // You can set these parameters on deployment to whatever you want
        maxReportDelay = 1 days;
        healthCheck = 0xE8228A2E7102ce51Bb73115e2964A233248398B9;

        // these are our standard approvals. want = Curve LP token
        want.approve(address(gauge), type(uint256).max);

        // set our strategy's name
        stratName = _name;

        // Set trade handler and enable trades
        tradeHandler = _tradeHandler;
        _enableTrades();
    }

    /* ========== VIEWS ========== */

    /**
    @notice Returns the strategy's balance of 3CRV Gauge tokens.
    @return uint256 Balance of 3CRV Gauge tokens
    */
    function stakedBalance() public view returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    /**
    @notice Returns the strategy's balance of 3CRV Pool and Gauge tokens.
    1 LP token is always 1 Gauge token, which is why they can be added.
    For more information, please refer to BaseStrategy.sol
    @return uint256 Balance of 3CRV LP and Gauge tokens 
    */
    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(stakedBalance());
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    // these will likely change across different wants.

    /**
    @notice Deposit in the gauge any LP tokens available in the strategy,
    usually from a user's deposit in the vault. For more information, please
    refer to BaseStrategy.sol
    @param _debtOutstanding Debt outstanding that the vault requires the 
    strategy to pay back. Paying back 100% of the debt outstanding is 
    not required. Not currently used by this strategy in this function.
    */
    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        // Send all of our LP tokens to deposit to the gauge if we have any
        uint256 _toInvest = balanceOfWant();
        if (_toInvest > 0) {
            gauge.deposit(_toInvest);
        }
    }

    /**
    @notice Liquidate up to `_amountNeeded` of `want` of this strategy's positions. 
    For more information, please refer to BaseStrategy.sol
    @param _amountNeeded Amount requested usually due to a withdrawal, or reduction
    in debt ratio.
    @return _liquidatedAmount The actual amount that the strategy was able to liquidate
    Most of the time `_amountNeeded` = `_liquidatedAmount`
    @return _loss When the strategy is not able to liquidate the requested amount, there
    is a loss. `_liquidatedAmount` + `_loss` = `_amountNeeded` always
    */
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 _wantBal = balanceOfWant();
        if (_amountNeeded > _wantBal) {
            // check if we have enough free funds to cover the withdrawal
            uint256 _stakedBal = stakedBalance();
            if (_stakedBal > 0) {
                gauge.withdraw(
                    Math.min(_stakedBal, _amountNeeded.sub(_wantBal))
                );
            }
            uint256 _withdrawnBal = balanceOfWant();
            _liquidatedAmount = Math.min(_amountNeeded, _withdrawnBal);
            _loss = _amountNeeded.sub(_liquidatedAmount);
        } else {
            // we have enough balance to cover the liquidation available
            return (_amountNeeded, 0);
        }
    }

    /** 
    @notice Unstake LP tokens from gauge and return the total LP token balance.
    This function is used during emergency exit instead of `prepareReturn()` to
    liquidate all of the Strategy's positions back to the Vault.
    @return uint256 LP token balance in the strategy
    */
    function liquidateAllPositions() internal override returns (uint256) {
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            gauge.withdraw(_stakedBal);
        }
        return balanceOfWant();
    }

    /** 
    @notice Do anything necessary to prepare this Strategy for migration. In this
    case, only unstaking LP tokens from the gauge is required.
    @param _newStrategy New strategy to which we are migrating. Not used in this
    strategy.
    */
    function prepareMigration(address _newStrategy) internal override {
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            gauge.withdraw(_stakedBal);
        }

        want.safeTransfer(_newStrategy, want.balanceOf(address(this)));

        // Migrate the strategy's balances of CRV and GNO, if any.
        uint256 crvBalance = crv.balanceOf(address(this));
        uint256 gnoBalance = gno.balanceOf(address(this));
        // if we claimed any CRV, then sell it
        if (crvBalance > 0) {
            crv.safeTransfer(_newStrategy, crvBalance);
        }
        if (gnoBalance > 0) {
            gno.safeTransfer(_newStrategy, gnoBalance);
        }
    }

    /** 
    @notice Claim CRV and all third-party tokens from the gauge
    */
    function _claimRewards() internal {
        // Mints claimable CRV from the factory gauge. Reward tokens are sent to `msg.sender`
        gaugeFactory.mint(address(gauge));

        // claim third-party rewards from the gauge, if any
        gauge.claim_rewards(); // GNO
    }

    function claimRewards() external onlyKeepers {
        _claimRewards();
    }

    /** 
    @notice Claims rewards, calculates debt payment to the vault, and the 
    strategy's PnL.
    @param _debtOutstanding debt repayment requested by the vault
    @return _profit strategy's profit
    @return _loss strategy's loss
    @return _debtPayment debt repayment. Can be less than `_debtOutstanding`
    */
    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // Claim rewards from the gauge. In the future, we might have the claim process outside
        // prepareReturn() so that we avoid calling harvest() twice (with ySwaps in between) as
        // we have to do with the current setup.
        // BaseStrategy could have a virtual function where strategies can perform the rewards
        // claming process; a function that can be called by keepers and ySwaps. Ideally, we would
        // also add a BaseStrategy virtual function so that keepers/ySwaps can see if there are
        // claimable rewards.
        _claimRewards();

        // debtOustanding will only be > 0 in the event of revoking or if we need to
        // rebalance from a withdrawal or lowering the debtRatio
        if (_debtOutstanding > 0) {
            uint256 stakedBal = stakedBalance();
            if (stakedBal > 0) {
                // don't bother withdrawing if we don't have staked funds
                gauge.withdraw(Math.min(stakedBal, _debtOutstanding));
            }
            uint256 _withdrawnBal = balanceOfWant();
            _debtPayment = Math.min(_debtOutstanding, _withdrawnBal);
        }

        // serious loss should never happen, but if it does (for instance, if Curve is hacked),
        // let's record it accurately
        uint256 assets = estimatedTotalAssets();
        uint256 debt = vault.strategies(address(this)).totalDebt;

        // if assets are greater than debt, things are working great!
        if (assets > debt) {
            _profit = assets.sub(debt);
            uint256 _wantBal = balanceOfWant();
            if (_profit.add(_debtPayment) > _wantBal) {
                // this should only be hit following donations to strategy
                liquidateAllPositions();
            }
        }
        // if assets are less than debt, we are in trouble
        else {
            _loss = debt.sub(assets);
        }

        // we're done harvesting, so reset our trigger if we used it
        delete forceHarvestTriggerOnce;
    }

    /* ========== ySwaps ========== */

    /** 
    @notice Update Trade Handler (ySwaps) address, approve handler contract to sell our 
    reward tokens, and register the swaps required by this strategy.
    @param _tradeHandler ySwaps contract address
    */
    function updateTradeHandler(address _tradeHandler) external onlyGovernance {
        _removeTradeHandlerPermissions();
        tradeHandler = _tradeHandler;
        _enableTrades();
        emit UpdatedTradeHandler();
    }

    /** 
    @notice Takes care of the approvals needed by Trade Handler (ySwaps) and 
    enables the swaps required by the strategy
    */
    function _enableTrades() internal {
        // approve and set up trade handler
        crv.safeApprove(tradeHandler, type(uint256).max);
        gno.safeApprove(tradeHandler, type(uint256).max);

        ITradeHandler(tradeHandler).enable(address(crv), address(want));
        ITradeHandler(tradeHandler).enable(address(gno), address(want));
    }

    /** 
    @notice Revoke Trade Handler (ySwaps) contract. Sets allowance to 0 and `tradeHandler`
    to address(0)
    */
    function removeTradeHandlerPermissions() external onlyEmergencyAuthorized {
        _removeTradeHandlerPermissions();
    }

    function _removeTradeHandlerPermissions() internal {
        if (tradeHandler != address(0)) {
            crv.safeApprove(tradeHandler, 0);
            gno.safeApprove(tradeHandler, 0);
            delete tradeHandler;
            emit RevokedTradeHandler();
        }
    }

    /* ========== KEEP3RS ========== */

    /** 
    @notice The trigger returns a boolean indicating whether the keeper
    should make the call to `harvest()`
    @param callCostinEth Expected cost of calling harvest in the native currency 
    of the blockchain
    @return bool Indicates whether `harvest()` should be called
    */
    function harvestTrigger(uint256 callCostinEth)
        public
        view
        override
        returns (bool)
    {
        StrategyParams memory params = vault.strategies(address(this));

        // harvest no matter what once we reach our maxDelay
        if (block.timestamp.sub(params.lastReport) > maxReportDelay) {
            return true;
        }

        // trigger if we want to manually harvest
        if (forceHarvestTriggerOnce) {
            return true;
        }

        // otherwise, we don't harvest
        return false;
    }

    /** 
    @notice convert our keeper's native cost of the `harvest()` call into want. Not 
    currently used in this strategy.
    @param _ethAmount Expected cost of calling harvest in the native currency 
    of the blockchain
    @return uint256 Transaction cost in want units
    */
    function ethToWant(uint256 _ethAmount)
        public
        view
        override
        returns (uint256)
    {}
}
