//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "../libraries/MathLib.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Exchange contract for Elastic Swap representing a single ERC20 pair of tokens to be swapped.
 * @author Elastic DAO
 * @notice This contract provides all of the needed functionality for a liquidity provider to supply/withdraw ERC20
 * tokens and traders to swap tokens for one another.
 */
contract Exchange is ERC20 {
    using MathLib for uint256;
    using SafeERC20 for IERC20;

    address public immutable quoteToken; // address of ERC20 quote token (elastic or fixed supply)
    address public immutable baseToken; // address of ERC20 base token (WETH or a stable coin w/ fixed supply)

    uint16 public elasticDAOFee; // ElasticDAO development fund fee in basis points
    uint16 public constant liquidityFee = 30; // fee provided to liquidity providers in basis points

    // x*y=k - we track these internally to compare to actual balances of the ERC20's
    // in order to calculate the "decay" or the amount of balances that are not
    // participating in the pricing curve and adding additional liquidity to swap.
    //uint256 public pricingConstantK;     // invariant "k" set by initial liquidity provider
    uint256 public internalQuoteTokenReserveQty; // x
    uint256 public internalBaseTokenReserveQty; // y

    /**
     * @dev Called to check timestamps from users for expiration of their calls.
     * Used in place of a modifier for byte code savings
     */
    function isNotExpired(uint256 _expirationTimeStamp) internal view {
        require(_expirationTimeStamp >= block.timestamp, "Exchange: EXPIRED");
    }

    /**
     * @notice called by the exchange factory to create a new erc20 token swap pair (do not call this directly!)
     * @param _name The human readable name of this pair (also used for the liquidity token name)
     * @param _symbol Shortened symbol for trading pair (also used for the liquidity token symbol)
     * @param _quoteToken address of the ERC20 quote token in the pair. This token can have a fixed or elastic supply
     * @param _baseToken address of the ERC20 base token in the pair. This token is assumed to have a fixed supply.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _quoteToken,
        address _baseToken
    ) ERC20(_name, _symbol) {
        quoteToken = _quoteToken;
        baseToken = _baseToken;
    }

    /**
     * @notice primary entry point for a liquidity provider to add new liquidity (quote and base tokens) to the exchange
     * and receive liquidity tokens in return.
     * Requires approvals to be granted to this exchange for both quote and base tokens.
     * @param _quoteTokenQtyDesired qty of quoteTokens that you would like to add to the exchange
     * @param _baseTokenQtyDesired qty of baseTokens that you would like to add to the exchange
     * @param _quoteTokenQtyMin minimum acceptable qty of quoteTokens that will be added (or transaction will revert)
     * @param _baseTokenQtyMin minimum acceptable qty of baseTokens that will be added (or transaction will revert)
     * @param _liquidityTokenRecipient address for the exchange to issue the resulting liquidity tokens from
     * this transaction to
     * @param _expirationTimestamp timestamp that this transaction must occur before (or transaction will revert)
     */
    function addLiquidity(
        uint256 _quoteTokenQtyDesired,
        uint256 _baseTokenQtyDesired,
        uint256 _quoteTokenQtyMin,
        uint256 _baseTokenQtyMin,
        address _liquidityTokenRecipient,
        uint256 _expirationTimestamp
    ) external {
        isNotExpired(_expirationTimestamp);
        uint256 quoteTokenQty;
        uint256 baseTokenQty;
        uint256 liquidityTokenQty;

        if (this.totalSupply() > 0) {
            // we have outstanding liquidity tokens present and an existing price curve

            // confirm that we have no beta or alpha decay present
            // if we do, in the future we will resolve that first
            // but for our proof of concept, we are disallowing this
            uint256 quoteTokenReserveQty =
                IERC20(quoteToken).balanceOf(address(this));
            require(
                quoteTokenReserveQty == internalQuoteTokenReserveQty,
                "Exchange: ASSET_DECAY_PRESENT"
            ); // TODO fix this!

            uint256 requiredBaseTokenQty =
                MathLib.calculateQty(
                    _quoteTokenQtyDesired,
                    internalQuoteTokenReserveQty,
                    internalBaseTokenReserveQty
                );

            if (requiredBaseTokenQty <= _baseTokenQtyDesired) {
                // user has to provide less than their desired amount
                require(
                    requiredBaseTokenQty >= _baseTokenQtyMin,
                    "Exchange: INSUFFICIENT_BASE_QTY"
                );
                quoteTokenQty = _quoteTokenQtyDesired;
                baseTokenQty = requiredBaseTokenQty;
            } else {
                // we need to check the opposite way.
                uint256 requiredQuoteTokenQty =
                    MathLib.calculateQty(
                        _baseTokenQtyDesired,
                        internalBaseTokenReserveQty,
                        internalQuoteTokenReserveQty
                    );
                assert(requiredQuoteTokenQty <= _quoteTokenQtyDesired);
                require(
                    _quoteTokenQtyDesired >= _quoteTokenQtyMin,
                    "Exchange: INSUFFICIENT_QUOTE_QTY"
                );
                quoteTokenQty = requiredQuoteTokenQty;
                baseTokenQty = _baseTokenQtyDesired;
            }

            liquidityTokenQty = MathLib
                .calculateLiquidityTokenQtyForDoubleAssetEntry(
                this.totalSupply(),
                baseTokenQty,
                IERC20(baseToken).balanceOf(address(this))
            );

            // if (quoteTokenReserveQty >= internalQuoteTokenReserveQty) {
            //     // alphaDecay is present
            //     liquidityTokenQty = MathLib
            //         .calculateLiquidityTokenQtyForDoubleAssetEntry(
            //         this.totalSupply(),
            //         internalQuoteTokenReserveQty,
            //         quoteTokenReserveQty,
            //         baseTokenQty,
            //         internalBaseTokenReserveQty
            //     );
            // } else if (quoteTokenReserveQty < internalQuoteTokenReserveQty) {
            //     // betaDecay is present
            //     uint256 baseTokenReserveQty =
            //         IERC20(baseToken).balanceOf(address(this));
            //     liquidityTokenQty = MathLib
            //         .calculateLiquidityTokenQtyForDoubleAssetEntry(
            //         this.totalSupply(),
            //         internalBaseTokenReserveQty,
            //         baseTokenReserveQty,
            //         quoteTokenQty,
            //         internalQuoteTokenReserveQty
            //     );
            // }
        } else {
            // this user will set the initial pricing curve
            quoteTokenQty = _quoteTokenQtyDesired;
            baseTokenQty = _baseTokenQtyDesired;
            liquidityTokenQty = _baseTokenQtyDesired;
        }

        internalQuoteTokenReserveQty += quoteTokenQty;
        internalBaseTokenReserveQty += baseTokenQty;

        IERC20(quoteToken).safeTransferFrom(
            msg.sender,
            address(this),
            quoteTokenQty
        ); // transfer quote tokens to Exchange
        IERC20(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            baseTokenQty
        ); // transfer base tokens to Exchange
        _mint(_liquidityTokenRecipient, liquidityTokenQty); // mint liquidity tokens to recipient
    }

    /**
     * @notice Entry point for a liquidity provider to add liquidity (quote tokens) to the exchange
     * when base token decay is present due to elastic token supply ( a rebase down event).
     * The caller will receive liquidity tokens in return.
     * Requires approvals to be granted to this exchange for quote tokens.
     * @dev variable names with the prefix "w" represent WAD values (decimals with 18 digits of precision)
     * @param _quoteTokenQtyDesired qty of quoteTokens that you would like to add to the exchange
     * @param _quoteTokenQtyMin minimum acceptable qty of quoteTokens that will be added (or transaction will revert)
     * @param _liquidityTokenRecipient address for the exchange to issue the resulting liquidity tokens from
     * this transaction to
     * @param _expirationTimestamp timestamp that this transaction must occur before (or transaction will revert)
     */
    function addQuoteTokenLiquidity(
        uint256 _quoteTokenQtyDesired,
        uint256 _quoteTokenQtyMin,
        address _liquidityTokenRecipient,
        uint256 _expirationTimestamp
    ) external {
        isNotExpired(_expirationTimestamp);
        // to calculate decay in base token, we need to see if we have less
        // quote token than we expect.  This would mean a rebase down has occurred.
        uint256 quoteTokenReserveQty =
            IERC20(quoteToken).balanceOf(address(this));
        require(
            internalQuoteTokenReserveQty > quoteTokenReserveQty,
            "Exchange: NO_BASE_DECAY"
        );

        // we can now calculate the amount of base token decay
        uint256 impliedBaseTokenReserveQty =
            (quoteTokenReserveQty * internalBaseTokenReserveQty) /
                internalQuoteTokenReserveQty;
        uint256 baseTokenDecay =
            internalBaseTokenReserveQty - impliedBaseTokenReserveQty;

        // this may be redundant based on the above math, but will check to ensure the decay wasn't so small
        // that it was <1 and rounded down to 0 saving the caller some gas
        require(baseTokenDecay > 0, "Exchange: NO_BASE_DECAY");

        // determine max amount of quote token that can be added to offset the current decay
        uint256 wInternalBaseToQuoteTokenRatio =
            internalBaseTokenReserveQty.wDiv(internalQuoteTokenReserveQty);

        // betaDecay / iSigma (B/A)
        uint256 maxQuoteTokenQty =
            baseTokenDecay.wDiv(wInternalBaseToQuoteTokenRatio);

        require(
            _quoteTokenQtyMin < maxQuoteTokenQty,
            "Exchange: INSUFFICIENT_DECAY"
        );

        uint256 quoteTokenQty;
        if (_quoteTokenQtyDesired > maxQuoteTokenQty) {
            quoteTokenQty = maxQuoteTokenQty;
        } else {
            quoteTokenQty = _quoteTokenQtyDesired;
        }
        uint256 baseTokenQtyDecayChange =
            (quoteTokenQty * wInternalBaseToQuoteTokenRatio) / MathLib.WAD;

        // we are not changing anything about our internal accounting here. We are simply adding tokens
        // to make our internal account "right"...or rather getting the external balances to match our internal
        // internalBaseTokenReserveQty += baseTokenQtyDecayChange;
        // internalQuoteTokenReserveQty += quoteTokenQty;

        // calculate the number of liquidity tokens to return to user using:
        uint256 liquidityTokenQty =
            MathLib.calculateLiquidityTokenQtyForSingleAssetEntry(
                this.totalSupply(),
                quoteTokenQty,
                internalQuoteTokenReserveQty,
                baseTokenQtyDecayChange,
                baseTokenDecay
            );

        IERC20(quoteToken).safeTransferFrom(
            msg.sender,
            address(this),
            quoteTokenQty
        ); // transfer quote tokens to Exchange

        _mint(_liquidityTokenRecipient, liquidityTokenQty); // mint liquidity tokens to recipient
    }

    /**
     * @notice Entry point for a liquidity provider to add liquidity (base tokens) to the exchange
     * when quote token decay is present due to elastic token supply.
     * The caller will receive liquidity tokens in return.
     * Requires approvals to be granted to this exchange for base tokens.
     * @dev variable names with the prefix "w" represent WAD values (decimals with 18 digits of precision)
     * @param _baseTokenQtyDesired qty of baseTokens that you would like to add to the exchange
     * @param _baseTokenQtyMin minimum acceptable qty of baseTokens that will be added (or transaction will revert)
     * @param _liquidityTokenRecipient address for the exchange to issue the resulting liquidity tokens from
     * this transaction to
     * @param _expirationTimestamp timestamp that this transaction must occur before (or transaction will revert)
     */
    function addBaseTokenLiquidity(
        uint256 _baseTokenQtyDesired,
        uint256 _baseTokenQtyMin,
        address _liquidityTokenRecipient,
        uint256 _expirationTimestamp
    ) external {
        isNotExpired(_expirationTimestamp);
        uint256 quoteTokenReserveQty =
            IERC20(quoteToken).balanceOf(address(this));

        // calculate decay in opposite token to determine if single asset entry is possible.
        // TODO: handle situation where rebase down would make this underflow. (better error message?)
        uint256 quoteTokenDecay =
            quoteTokenReserveQty - internalQuoteTokenReserveQty;
        require(quoteTokenDecay > 0, "Exchange: NO_QUOTE_DECAY");

        // determine max amount of base token that can be added to offset the current decay
        uint256 wInternalQuoteTokenToBaseTokenRatio =
            internalQuoteTokenReserveQty.wDiv(internalBaseTokenReserveQty);

        // alphaDecay / sigma (A/B)
        uint256 maxBaseTokenQty =
            quoteTokenDecay.wDiv(wInternalQuoteTokenToBaseTokenRatio);

        require(
            _baseTokenQtyMin < maxBaseTokenQty,
            "Exchange: INSUFFICIENT_DECAY"
        );

        uint256 baseTokenQty;
        if (_baseTokenQtyDesired > maxBaseTokenQty) {
            baseTokenQty = maxBaseTokenQty;
        } else {
            baseTokenQty = _baseTokenQtyDesired;
        }
        uint256 quoteTokenQtyDecayChange =
            (baseTokenQty * wInternalQuoteTokenToBaseTokenRatio) / MathLib.WAD;

        internalQuoteTokenReserveQty += quoteTokenQtyDecayChange;
        internalBaseTokenReserveQty += baseTokenQty;

        // calculate the number of liquidity tokens to return to user using
        uint256 liquidityTokenQty =
            MathLib.calculateLiquidityTokenQtyForSingleAssetEntry(
                this.totalSupply(),
                baseTokenQty,
                internalBaseTokenReserveQty,
                quoteTokenQtyDecayChange,
                quoteTokenDecay
            );

        IERC20(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            baseTokenQty
        ); // transfer base tokens to Exchange

        _mint(_liquidityTokenRecipient, liquidityTokenQty); // mint liquidity tokens to recipient
    }

    /**
     * @notice called by a liquidity provider to redeem liquidity tokens from the exchange and receive back
     * quote and base tokens. Required approvals to be granted to this exchange for the liquidity token
     * @param _liquidityTokenQty qty of liquidity tokens that you would like to redeem
     * @param _quoteTokenQtyMin minimum acceptable qty of quote tokens to receive back (or transaction will revert)
     * @param _baseTokenQtyMin minimum acceptable qty of base tokens to receive back (or transaction will revert)
     * @param _tokenRecipient address for the exchange to issue the resulting quote and
     * base tokens from this transaction to
     * @param _expirationTimestamp timestamp that this transaction must occur before (or transaction will revert)
     */
    function removeLiquidity(
        uint256 _liquidityTokenQty,
        uint256 _quoteTokenQtyMin,
        uint256 _baseTokenQtyMin,
        address _tokenRecipient,
        uint256 _expirationTimestamp
    ) external {
        isNotExpired(_expirationTimestamp);
        require(this.totalSupply() > 0, "Exchange: INSUFFICIENT_LIQUIDITY");
        require(
            _quoteTokenQtyMin > 0 && _baseTokenQtyMin > 0,
            "Exchange: MINS_MUST_BE_GREATER_THAN_ZERO"
        );

        uint256 quoteTokenReserveQty =
            IERC20(quoteToken).balanceOf(address(this));
        uint256 baseTokenReserveQty =
            IERC20(baseToken).balanceOf(address(this));

        uint256 quoteTokenQtyToReturn =
            (_liquidityTokenQty * quoteTokenReserveQty) / this.totalSupply();
        uint256 baseTokenQtyToReturn =
            (_liquidityTokenQty * baseTokenReserveQty) / this.totalSupply();

        require(
            quoteTokenQtyToReturn >= _quoteTokenQtyMin,
            "Exchange: INSUFFICIENT_QUOTE_QTY"
        );

        require(
            baseTokenQtyToReturn >= _baseTokenQtyMin,
            "Exchange: INSUFFICIENT_BASE_QTY"
        );

        // we need to ensure no overflow here in the case when
        // we are removing assets when a decay is present.
        if (quoteTokenQtyToReturn > internalQuoteTokenReserveQty) {
            internalQuoteTokenReserveQty = 0;
        } else {
            internalQuoteTokenReserveQty -= quoteTokenQtyToReturn;
        }

        if (baseTokenQtyToReturn > internalBaseTokenReserveQty) {
            internalBaseTokenReserveQty = 0;
        } else {
            internalBaseTokenReserveQty -= baseTokenQtyToReturn;
        }

        _burn(msg.sender, _liquidityTokenQty);
        IERC20(quoteToken).safeTransfer(_tokenRecipient, quoteTokenQtyToReturn);
        IERC20(baseToken).safeTransfer(_tokenRecipient, baseTokenQtyToReturn);
    }

    /**
     * @notice swaps quote tokens for a minimum amount of base tokens.  Fees are included in all transactions.
     * The exchange must be granted approvals for the quote token by the caller.
     * @param _quoteTokenQty qty of quote tokens to swap
     * @param _minBaseTokenQty minimum qty of base tokens to receive in exchange for
     * your quote tokens (or the transaction will revert)
     * @param _expirationTimestamp timestamp that this transaction must occur before (or transaction will revert)
     */
    function swapQuoteTokenForBaseToken(
        uint256 _quoteTokenQty,
        uint256 _minBaseTokenQty,
        uint256 _expirationTimestamp
    ) external {
        isNotExpired(_expirationTimestamp);
        require(
            _quoteTokenQty > 0 && _minBaseTokenQty > 0,
            "Exchange: INSUFFICIENT_TOKEN_QTY"
        );

        uint256 baseTokenQty =
            MathLib.calculateQtyToReturnAfterFees(
                _quoteTokenQty,
                internalQuoteTokenReserveQty,
                internalBaseTokenReserveQty,
                liquidityFee
            );

        require(
            baseTokenQty > _minBaseTokenQty,
            "Exchange: INSUFFICIENT_BASE_TOKEN_QTY"
        );

        internalQuoteTokenReserveQty += _quoteTokenQty;
        internalBaseTokenReserveQty -= baseTokenQty;

        IERC20(quoteToken).safeTransferFrom(
            msg.sender,
            address(this),
            _quoteTokenQty
        );
        IERC20(baseToken).safeTransfer(msg.sender, baseTokenQty);
    }

    /**
     * @notice swaps base tokens for a minimum amount of quote tokens.  Fees are included in all transactions.
     * The exchange must be granted approvals for the base token by the caller.
     * @param _baseTokenQty qty of base tokens to swap
     * @param _minQuoteTokenQty minimum qty of quote tokens to receive in exchange for
     * your base tokens (or the transaction will revert)
     * @param _expirationTimestamp timestamp that this transaction must occur before (or transaction will revert)
     */
    function swapBaseTokenForQuoteToken(
        uint256 _baseTokenQty,
        uint256 _minQuoteTokenQty,
        uint256 _expirationTimestamp
    ) external {
        isNotExpired(_expirationTimestamp);
        require(
            _baseTokenQty > 0 && _minQuoteTokenQty > 0,
            "Exchange: INSUFFICIENT_TOKEN_QTY"
        );

        uint256 quoteTokenQty;
        // check to see if we have experience base token decay / a rebase down event
        uint256 quoteTokenReserveQty =
            IERC20(quoteToken).balanceOf(address(this));
        
        if(quoteTokenReserveQty < internalQuoteTokenReserveQty) 
        { // we have less reserves than our current price curve will expect, we need to adjust the curve
            uint256 wPricingRatio = internalQuoteTokenReserveQty.wDiv(internalBaseTokenReserveQty); // omega
            uint256 impliedBaseTokenQty = quoteTokenReserveQty.wDiv(wPricingRatio) / MathLib.WAD;
            quoteTokenQty =
                MathLib.calculateQtyToReturnAfterFees(
                    _baseTokenQty,
                    impliedBaseTokenQty,
                    quoteTokenReserveQty,
                    liquidityFee
                );
        } else { // we have the same or more reserves, no need to alter the curve.
            quoteTokenQty =
                MathLib.calculateQtyToReturnAfterFees(
                    _baseTokenQty,
                    internalBaseTokenReserveQty,
                    internalQuoteTokenReserveQty,
                    liquidityFee
                );
        }

        require(
            quoteTokenQty > _minQuoteTokenQty,
            "Exchange: INSUFFICIENT_QUOTE_TOKEN_QTY"
        );

        internalQuoteTokenReserveQty -= quoteTokenQty;
        internalBaseTokenReserveQty += _baseTokenQty;

        IERC20(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            _baseTokenQty
        );
        IERC20(quoteToken).safeTransfer(msg.sender, quoteTokenQty);
    }
}
