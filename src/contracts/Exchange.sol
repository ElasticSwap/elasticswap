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

    struct InternalBalances {
        // x*y=k - we track these internally to compare to actual balances of the ERC20's
        // in order to calculate the "decay" or the amount of balances that are not
        // participating in the pricing curve and adding additional liquidity to swap.
        uint256 quoteTokenReserveQty; // x
        uint256 baseTokenReserveQty; // y
    }

    address public immutable quoteToken; // address of ERC20 quote token (elastic or fixed supply)
    address public immutable baseToken; // address of ERC20 base token (WETH or a stable coin w/ fixed supply)

    uint16 public elasticDAOFee; // ElasticDAO development fund fee in basis points
    uint16 public constant liquidityFee = 30; // fee provided to liquidity providers in basis points

    InternalBalances public internalBalances = InternalBalances(0, 0);

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
            // if we do, we need to resolve that first
            uint256 quoteTokenReserveQty =
                IERC20(quoteToken).balanceOf(address(this));

            uint256 quoteTokenQtyFromDecay;
            uint256 baseTokenQtyFromDecay;
            uint256 liquidityTokenQtyFromDecay;

            // TODO: can we end up in an off by one situation where the below always ends up getting called
            // and wasting gas for what is a trivial amount of decay that cannot be resolved?
            // IE we are always off by 1...
            if (quoteTokenReserveQty > internalBalances.quoteTokenReserveQty) {
                // we have more quote token than expected (quote token decay) due to rebase up
                // we first need to handle this situation by requiring this user
                // to add base tokens
                (baseTokenQtyFromDecay, liquidityTokenQtyFromDecay) = MathLib
                    .calculateAddBaseTokenLiquidityQuantities(
                    _baseTokenQtyDesired,
                    0, // there is no minimum for this particular call since we may use base tokens later.
                    quoteTokenReserveQty,
                    this.totalSupply(),
                    internalBalances
                );
            } else if (
                quoteTokenReserveQty < internalBalances.quoteTokenReserveQty
            ) {
                // we have less quote token than expected (base token decay) due to a rebase down
                // we first need to handle this by adding quote tokens to offset this.
                (quoteTokenQtyFromDecay, liquidityTokenQtyFromDecay) = MathLib
                    .calculateAddQuoteTokenLiquidityQuantities(
                    _quoteTokenQtyDesired,
                    0, // there is no minimum for this particular call since we may use quote tokens later.
                    quoteTokenReserveQty,
                    this.totalSupply(),
                    internalBalances
                );
            }

            if (liquidityTokenQtyFromDecay != 0) {
                // the user dealt with part of the decay and we need to add values from that.
                if (
                    baseTokenQtyFromDecay < _baseTokenQtyDesired &&
                    quoteTokenQtyFromDecay < _quoteTokenQtyDesired
                ) {
                    // the user still has qty that they desire to contribute to the exchange for liquidity
                    (quoteTokenQty, baseTokenQty, liquidityTokenQty) = MathLib
                        .calculateAddLiquidityQuantities(
                        _quoteTokenQtyDesired - quoteTokenQtyFromDecay, // safe from underflow based on above IF
                        _baseTokenQtyDesired - baseTokenQtyFromDecay, // safe from underflow based on above IF
                        0, // we will check minimums below
                        0, // we will check minimums below
                        IERC20(baseToken).balanceOf(address(this)) +
                            baseTokenQtyFromDecay,
                        this.totalSupply() + liquidityTokenQtyFromDecay,
                        internalBalances, // NOTE: these balances have already been updated when we did the decay math.
                        false
                    );
                }
                quoteTokenQty += quoteTokenQtyFromDecay;
                baseTokenQty += baseTokenQtyFromDecay;
                liquidityTokenQty += liquidityTokenQtyFromDecay;

                require(
                    quoteTokenQty >= _quoteTokenQtyMin,
                    "Exchange: INSUFFICIENT_QUOTE_QTY"
                );

                require(
                    baseTokenQty >= _baseTokenQtyMin,
                    "Exchange: INSUFFICIENT_BASE_QTY"
                );
            } else {
                // the user is just doing a simple double asset entry / providing both quote and base.
                (quoteTokenQty, baseTokenQty, liquidityTokenQty) = MathLib
                    .calculateAddLiquidityQuantities(
                    _quoteTokenQtyDesired,
                    _baseTokenQtyDesired,
                    _quoteTokenQtyMin,
                    _baseTokenQtyMin,
                    IERC20(baseToken).balanceOf(address(this)),
                    this.totalSupply(),
                    internalBalances,
                    true
                );
            }
        } else {
            // this user will set the initial pricing curve
            quoteTokenQty = _quoteTokenQtyDesired;
            baseTokenQty = _baseTokenQtyDesired;
            liquidityTokenQty = _baseTokenQtyDesired;
            internalBalances.quoteTokenReserveQty += quoteTokenQty;
            internalBalances.baseTokenReserveQty += baseTokenQty;
        }

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
            internalBalances.quoteTokenReserveQty > quoteTokenReserveQty,
            "Exchange: NO_BASE_DECAY"
        );

        (uint256 quoteTokenQty, uint256 liquidityTokenQty) =
            MathLib.calculateAddQuoteTokenLiquidityQuantities(
                _quoteTokenQtyDesired,
                _quoteTokenQtyMin,
                quoteTokenReserveQty,
                this.totalSupply(),
                internalBalances
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

        require(
            quoteTokenReserveQty > internalBalances.quoteTokenReserveQty,
            "Exchange: NO_QUOTE_DECAY"
        );

        (uint256 baseTokenQty, uint256 liquidityTokenQty) =
            MathLib.calculateAddBaseTokenLiquidityQuantities(
                _baseTokenQtyDesired,
                _baseTokenQtyMin,
                quoteTokenReserveQty,
                this.totalSupply(),
                internalBalances
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
        if (quoteTokenQtyToReturn > internalBalances.quoteTokenReserveQty) {
            internalBalances.quoteTokenReserveQty = 0;
        } else {
            internalBalances.quoteTokenReserveQty -= quoteTokenQtyToReturn;
        }

        if (baseTokenQtyToReturn > internalBalances.baseTokenReserveQty) {
            internalBalances.baseTokenReserveQty = 0;
        } else {
            internalBalances.baseTokenReserveQty -= baseTokenQtyToReturn;
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
                internalBalances.quoteTokenReserveQty,
                internalBalances.baseTokenReserveQty,
                liquidityFee
            );

        require(
            baseTokenQty > _minBaseTokenQty,
            "Exchange: INSUFFICIENT_BASE_TOKEN_QTY"
        );

        internalBalances.quoteTokenReserveQty += _quoteTokenQty;
        internalBalances.baseTokenReserveQty -= baseTokenQty;

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

        if (quoteTokenReserveQty < internalBalances.quoteTokenReserveQty) {
            // we have less reserves than our current price curve will expect, we need to adjust the curve
            uint256 wPricingRatio =
                internalBalances.quoteTokenReserveQty.wDiv(
                    internalBalances.baseTokenReserveQty
                ); // omega
            uint256 impliedBaseTokenQty =
                quoteTokenReserveQty.wDiv(wPricingRatio) / MathLib.WAD;
            quoteTokenQty = MathLib.calculateQtyToReturnAfterFees(
                _baseTokenQty,
                impliedBaseTokenQty,
                quoteTokenReserveQty,
                liquidityFee
            );
        } else {
            // we have the same or more reserves, no need to alter the curve.
            quoteTokenQty = MathLib.calculateQtyToReturnAfterFees(
                _baseTokenQty,
                internalBalances.baseTokenReserveQty,
                internalBalances.quoteTokenReserveQty,
                liquidityFee
            );
        }

        require(
            quoteTokenQty > _minQuoteTokenQty,
            "Exchange: INSUFFICIENT_QUOTE_TOKEN_QTY"
        );

        internalBalances.quoteTokenReserveQty -= quoteTokenQty;
        internalBalances.baseTokenReserveQty += _baseTokenQty;

        IERC20(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            _baseTokenQty
        );
        IERC20(quoteToken).safeTransfer(msg.sender, quoteTokenQty);
    }
}
