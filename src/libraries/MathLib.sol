//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "../contracts/Exchange.sol";

/**
 * @title MathLib
 * @author ElasticDAO
 */
library MathLib {
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant WAD = 10**18; // represent a decimal with 18 digits of precision

    /**
     * @dev divides two float values, required since solidity does not handle
     * floating point values.
     *
     * inspiration: https://github.com/dapphub/ds-math/blob/master/src/math.sol
     *
     * @return uint256 wad value (decimal with 18 digits of precision)
     */
    function wDiv(uint256 a, uint256 b) public pure returns (uint256) {
        return ((a * WAD) + (b / 2)) / b;
    }

    /**
     * @dev multiplies two float values, required since solidity does not handle
     * floating point values
     *
     * inspiration: https://github.com/dapphub/ds-math/blob/master/src/math.sol
     *
     * @return uint256 wad value (decimal with 18 digits of precision)
     */
    function wMul(uint256 a, uint256 b) public pure returns (uint256) {
        return (a * b) + (WAD / 2) / WAD;
    }

    /**
     * @dev used to calculate the qty of token a liquidity provider
     * must add in order to maintain the current reserve ratios
     * @param _tokenAQty quote or base token qty to be supplied by the liquidity provider
     * @param _tokenAReserveQty current reserve qty of the quote or base token (same token as tokenA)
     * @param _tokenBReserveQty current reserve qty of the other quote or base token (not tokenA)
     */
    function calculateQty(
        uint256 _tokenAQty,
        uint256 _tokenAReserveQty,
        uint256 _tokenBReserveQty
    ) public pure returns (uint256 tokenBQty) {
        require(_tokenAQty > 0, "MathLib: INSUFFICIENT_QTY");
        require(
            _tokenAReserveQty > 0 && _tokenBReserveQty > 0,
            "MathLib: INSUFFICIENT_LIQUIDITY"
        );
        tokenBQty = (_tokenAQty * _tokenBReserveQty) / _tokenAReserveQty;
    }

    /**
     * @dev used to calculate the qty of token a trader will receive (less fees)
     * given the qty of token A they are providing
     * @param _tokenASwapQty quote or base token qty to be swapped by the trader
     * @param _tokenAReserveQty current reserve qty of the quote or base token (same token as tokenA)
     * @param _tokenBReserveQty current reserve qty of the other quote or base token (not tokenA)
     * @param _liquidityFeeInBasisPoints fee to liquidity providers represented in basis points
     */
    function calculateQtyToReturnAfterFees(
        uint256 _tokenASwapQty,
        uint256 _tokenAReserveQty,
        uint256 _tokenBReserveQty,
        uint256 _liquidityFeeInBasisPoints
    ) public pure returns (uint256 qtyToReturn) {
        uint256 tokenASwapQtyLessFee =
            _tokenASwapQty * (BASIS_POINTS - _liquidityFeeInBasisPoints);
        qtyToReturn =
            (tokenASwapQtyLessFee * _tokenBReserveQty) /
            ((_tokenAReserveQty * BASIS_POINTS) + tokenASwapQtyLessFee);
    }

    // gamma = deltaY / Y / 2 * (deltaX / alphaDecay')
    function calculateLiquidityTokenQtyForSingleAssetEntry(
        uint256 _totalSupplyOfLiquidityTokens,
        uint256 _tokenQtyAToAdd,
        uint256 _internalTokenAReserveQty,
        uint256 _tokenBDecayChange,
        uint256 _tokenBDecay
    ) public pure returns (uint256 liquidityTokenQty) {
        uint256 wGamma =
            wDiv(
                wMul(
                    wDiv(_tokenQtyAToAdd, _internalTokenAReserveQty),
                    _tokenBDecayChange
                ),
                _tokenBDecay
            ) /
                WAD /
                2;
        liquidityTokenQty =
            (wDiv(_totalSupplyOfLiquidityTokens, WAD - wGamma) * wGamma) /
            WAD;
    }

    function calculateLiquidityTokenQtyForDoubleAssetEntry(
        uint256 _totalSupplyOfLiquidityTokens,
        uint256 _baseTokenQty,
        uint256 _baseTokenReserveBalance
    ) public pure returns (uint256 liquidityTokenQty) {
        liquidityTokenQty =
            (_baseTokenQty * _totalSupplyOfLiquidityTokens) /
            _baseTokenReserveBalance;
    }

    function calculateAddBaseTokenLiquidityQuantities(
        uint256 _totalSupplyOfLiquidityTokens,
        uint256 _baseTokenQtyDesired,
        uint256 _baseTokenQtyMin,
        uint256 _quoteTokenReserveQty,
        Exchange.InternalBalances storage _internalBalances
    ) public returns (uint256 baseTokenQty, uint256 liquidityTokenQty) {
        uint256 quoteTokenDecay =
            _quoteTokenReserveQty - _internalBalances.quoteTokenReserveQty;

        // determine max amount of base token that can be added to offset the current decay
        uint256 wInternalQuoteTokenToBaseTokenRatio =
            wDiv(
                _internalBalances.quoteTokenReserveQty,
                _internalBalances.baseTokenReserveQty
            );

        // alphaDecay / sigma (A/B)
        uint256 maxBaseTokenQty =
            wDiv(quoteTokenDecay, wInternalQuoteTokenToBaseTokenRatio);

        require(
            _baseTokenQtyMin < maxBaseTokenQty,
            "Exchange: INSUFFICIENT_DECAY"
        );

        if (_baseTokenQtyDesired > maxBaseTokenQty) {
            baseTokenQty = maxBaseTokenQty;
        } else {
            baseTokenQty = _baseTokenQtyDesired;
        }
        uint256 quoteTokenQtyDecayChange =
            (baseTokenQty * wInternalQuoteTokenToBaseTokenRatio) / MathLib.WAD;

        _internalBalances.quoteTokenReserveQty += quoteTokenQtyDecayChange;
        _internalBalances.baseTokenReserveQty += baseTokenQty;

        // calculate the number of liquidity tokens to return to user using
        liquidityTokenQty = calculateLiquidityTokenQtyForSingleAssetEntry(
            _totalSupplyOfLiquidityTokens,
            baseTokenQty,
            _internalBalances.baseTokenReserveQty,
            quoteTokenQtyDecayChange,
            quoteTokenDecay
        );
        return (baseTokenQty, liquidityTokenQty);
    }

    function calculateAddQuoteTokenLiquidityQuantities(
        uint256 _totalSupplyOfLiquidityTokens,
        uint256 _quoteTokenReserveQty,
        uint256 _quoteTokenQtyDesired,
        uint256 _quoteTokenQtyMin,
        Exchange.InternalBalances memory _internalBalances
    ) public pure returns (uint256 quoteTokenQty, uint256 liquidityTokenQty) {
        // we can now calculate the amount of base token decay
        uint256 impliedBaseTokenReserveQty =
            (_quoteTokenReserveQty * _internalBalances.baseTokenReserveQty) /
                _internalBalances.quoteTokenReserveQty;
        uint256 baseTokenDecay =
            _internalBalances.baseTokenReserveQty - impliedBaseTokenReserveQty;

        // this may be redundant based on the above math, but will check to ensure the decay wasn't so small
        // that it was <1 and rounded down to 0 saving the caller some gas
        require(baseTokenDecay > 0, "Exchange: NO_BASE_DECAY");

        // determine max amount of quote token that can be added to offset the current decay
        uint256 wInternalBaseToQuoteTokenRatio =
            wDiv(
                _internalBalances.baseTokenReserveQty,
                _internalBalances.quoteTokenReserveQty
            );

        // betaDecay / iSigma (B/A)
        uint256 maxQuoteTokenQty =
            wDiv(baseTokenDecay, wInternalBaseToQuoteTokenRatio);

        require(
            _quoteTokenQtyMin < maxQuoteTokenQty,
            "Exchange: INSUFFICIENT_DECAY"
        );

        if (_quoteTokenQtyDesired > maxQuoteTokenQty) {
            quoteTokenQty = maxQuoteTokenQty;
        } else {
            quoteTokenQty = _quoteTokenQtyDesired;
        }
        uint256 baseTokenQtyDecayChange =
            (quoteTokenQty * wInternalBaseToQuoteTokenRatio) / MathLib.WAD;

        // we are not changing anything about our internal accounting here. We are simply adding tokens
        // to make our internal account "right"...or rather getting the external balances to match our internal
        // baseTokenReserveQty += baseTokenQtyDecayChange;
        // quoteTokenReserveQty += quoteTokenQty;

        // calculate the number of liquidity tokens to return to user using:
        liquidityTokenQty = calculateLiquidityTokenQtyForSingleAssetEntry(
            _totalSupplyOfLiquidityTokens,
            quoteTokenQty,
            _internalBalances.quoteTokenReserveQty,
            baseTokenQtyDecayChange,
            baseTokenDecay
        );

        return (quoteTokenQty, liquidityTokenQty);
    }
}
