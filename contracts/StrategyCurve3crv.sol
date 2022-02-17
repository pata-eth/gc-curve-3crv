// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./interfaces/curve.sol";
import "./interfaces/yearn.sol";
import {IUniswapV2Router02} from "./interfaces/uniswap.sol";
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";

interface IBaseFee {
    function isCurrentBaseFeeAcceptable() external view returns (bool);
}

interface IUniV3 {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

abstract contract StrategyCurveBase is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    // these should stay the same across different wants.

    // Curve stuff
    IGauge public constant gauge =
        IGauge(0x78CF256256C8089d68Cde634Cf7cDEFb39286470); // Curve gauge contract, most are tokenized, held by strategy

    // keepCRV stuff
    uint256 public keepCRV; // the percentage of CRV we re-lock for boost (in basis points)
    uint256 internal constant FEE_DENOMINATOR = 10000; // this means all of our fee values are in basis points

    IERC20 public constant crv =
        IERC20(0x712b3d230f3c1c19db860d80619288b1f0bdd0bd);
    IERC20 public constant gno =
        IERC20(0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb);

    bool internal forceHarvestTriggerOnce; // only set this to true externally when we want to trigger our keepers to harvest for us

    string internal stratName; // set our strategy name here

    /* ========== CONSTRUCTOR ========== */

    constructor(address _vault) public BaseStrategy(_vault) {}

    /* ========== VIEWS ========== */

    function name() external view override returns (string memory) {
        return stratName;
    }

    function stakedBalance() public view returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(stakedBalance());
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    // these should stay the same across different wants.

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

    // fire sale, get rid of it all!
    function liquidateAllPositions() internal override returns (uint256) {
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            // don't bother withdrawing zero
            gauge.withdraw(_stakedBal);
        }
        return balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            gauge.withdraw(_stakedBal);
        }
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    /* ========== SETTERS ========== */

    // These functions are useful for setting parameters of the strategy that may need to be adjusted.

    // Set the amount of CRV to be locked in Yearn's veCRV voter from each harvest. Default is 10%.
    function setKeepCRV(uint256 _keepCRV) external onlyAuthorized {
        require(_keepCRV <= 10_000);
        keepCRV = _keepCRV;
    }

    // This allows us to manually harvest with our keeper as needed
    function setForceHarvestTriggerOnce(bool _forceHarvestTriggerOnce)
        external
        onlyAuthorized
    {
        forceHarvestTriggerOnce = _forceHarvestTriggerOnce;
    }
}

contract StrategyCurveTricrypto is StrategyCurveBase {
    /* ========== STATE VARIABLES ========== */
    // these will likely change across different wants.

    // Curve stuff
    ICurveFi public constant curve =
        ICurveFi(0x7f90122BF0700F9E7e1F688fe926940E8839F353); // This is our pool specific to this vault.

    // we use these to deposit to our curve pool
    address public targetToken; // this is the token we sell into, USDT, USDC, or WXDAI
    IERC20 public constant usdt =
        IERC20(0x4ECaBa5870353805a9F068101A40E0f32ed605C6);
    IERC20 public constant usdc =
        IERC20(0xDDAfbb505ad214D7b80b1f830fcCc89B60fb7A83);
    IERC20 public constant wxdai =
        IERC20(0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d);
    IUniswapV2Router02 public router =
        IUniswapV2Router02(0x1C232F01118CB8B424793ae03F870aa7D0ac7f77); // this is the router we swap with, start with honeyswap

    address public constant voter = 0xFB4464a18d18f3FF439680BBbCE659dB2806A187; // sms

    /* ========== CONSTRUCTOR ========== */

    constructor(address _vault, string memory _name)
        public
        StrategyCurveBase(_vault)
    {
        // You can set these parameters on deployment to whatever you want
        maxReportDelay = 2 days; // 2 days in seconds
        healthCheck = 0xf13Cd6887C62B5beC145e30c38c4938c5E627fe0; // health.ychad.eth //TODO: WE NEED TO CHANGE THIS

        // these are our standard approvals. want = Curve LP token
        address honeyswap = 0x1C232F01118CB8B424793ae03F870aa7D0ac7f77;
        address baoswap = 0x6093AeBAC87d62b1A5a4cEec91204e35020E38bE;
        want.approve(address(gauge), type(uint256).max);
        crv.approve(honeyswap, type(uint256).max);
        gno.approve(honeyswap, type(uint256).max);
        crv.approve(baoswap, type(uint256).max);
        gno.approve(baoswap, type(uint256).max);

        // set our strategy's name
        stratName = _name;

        // these are our approvals and path specific to this contract
        wxdai.approve(address(curve), type(uint256).max);
        usdc.approve(address(curve), type(uint256).max);
        usdt.safeApprove(address(curve), type(uint256).max);

        // start off with fusdt
        targetToken = address(wxdai);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    // these will likely change across different wants.

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // harvest our rewards from the gauge
        gauge.claim_rewards();
        uint256 crvBalance = crv.balanceOf(address(this));
        uint256 gnoBalance = gno.balanceOf(address(this));
        // if we claimed any CRV, then sell it
        if (crvBalance > 0) {
            // keep some of our CRV to increase our boost
            uint256 sendToVoter = crvBalance.mul(keepCRV).div(FEE_DENOMINATOR);
            if (keepCRV > 0) {
                crv.safeTransfer(voter, sendToVoter);
            }

            // check our balance again after transferring some crv to our voter
            crvBalance = crv.balanceOf(address(this));

            // sell the rest of our CRV
            if (crvBalance > 0) {
                _sellToken(address(crv), crvBalance);
            }
        }
        // sell WFTM if we have any
        if (gnoBalance > 0) {
            _sellToken(address(gno), gnoBalance);
        }

        uint256 wxdaiBalance = wxdai.balanceOf(address(this));
        uint256 usdcBalance = usdc.balanceOf(address(this));
        uint256 usdtBalance = usdt.balanceOf(address(this));

        // deposit our balance to Curve if we have any
        if (wxdaiBalance > 0 || usdcBalance > 0 || usdtBalance > 0) {
            curve.add_liquidity([wxdaiBalance, usdcBalance, usdtBalance], 0);
        }

        // debtOustanding will only be > 0 in the event of revoking or if we need to rebalance from a withdrawal or lowering the debtRatio
        uint256 stakedBal = stakedBalance();
        if (_debtOutstanding > 0) {
            if (stakedBal > 0) {
                // don't bother withdrawing if we don't have staked funds
                gauge.withdraw(Math.min(stakedBal, _debtOutstanding));
            }
            uint256 _withdrawnBal = balanceOfWant();
            _debtPayment = Math.min(_debtOutstanding, _withdrawnBal);
        }

        // serious loss should never happen, but if it does (for instance, if Curve is hacked), let's record it accurately
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
        forceHarvestTriggerOnce = false;
    }

    // Sells our CRV or GNO for our target token
    function _sellToken(address token, uint256 _amount) internal {
        if (token == address(gno)) {
            address[] memory tokenPath = new address[](2);
            tokenPath[0] = address(gno);
            tokenPath[1] = address(targetToken);
            IUniswapV2Router02(router).swapExactTokensForTokens(
                _amount,
                uint256(0),
                tokenPath,
                address(this),
                block.timestamp
            );
        } else {
            address[] memory tokenPath = new address[](3);
            tokenPath[0] = address(token);
            tokenPath[1] = address(xdai);
            tokenPath[2] = address(targetToken);
            IUniswapV2Router02(router).swapExactTokensForTokens(
                _amount,
                uint256(0),
                tokenPath,
                address(this),
                block.timestamp
            );
        }
    }

    /* ========== KEEP3RS ========== */

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

    // convert our keeper's eth cost into want, we don't need this anymore since we don't use baseStrategy harvestTrigger
    function ethToWant(uint256 _ethAmount)
        public
        view
        override
        returns (uint256)
    {
        return _ethAmount;
    }

    /* ========== SETTERS ========== */

    // These functions are useful for setting parameters of the strategy that may need to be adjusted.
    // Set optimal token to sell harvested funds for depositing to Curve.
    // Default is fUSDT, but can be set to WETH or WBTC as needed by strategist or governance.
    function setOptimal(uint256 _optimal) external onlyAuthorized {
        if (_optimal == 0) {
            targetToken = address(wxdai);
        } else if (_optimal == 1) {
            targetToken = address(usdc);
        } else if (_optimal == 2) {
            targetToken = address(usdt);
        } else {
            revert("incorrect token");
        }
    }

    // spookyswap generally has better liquidity. if this changes, we can use spiritswap.
    function setUseBaoSwap(bool useSpooky) external onlyAuthorized {
        if (useSpooky) {
            router = IUniswapV2Router02(
                0x6093AeBAC87d62b1A5a4cEec91204e35020E38bE
            ); // spookyswap's router
        } else {
            router = IUniswapV2Router02(
                0x1C232F01118CB8B424793ae03F870aa7D0ac7f77
            ); // spiritswap router
        }
    }
}
