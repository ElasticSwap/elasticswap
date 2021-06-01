//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Exchange is ERC20, Ownable {
    using SafeERC20 for IERC20;

    address public immutable quoteToken; // address of ERC20 quote token (elastic or fixed supply)
    address public immutable baseToken; // address of ERC20 base token (WETH or a stable coin)

    uint16 public elasticDAOFee; // ElasticDAO development fund fee in basis points
    uint16 public constant liquidityFee = 30; // fee provided to liquiduty providers in basis points
    uint16 public constant basisPoints = 10000;

    modifier notExpired(uint256 _expirationTimeStamp) {
        require(
            _expirationTimeStamp >= block.timestamp,
            "ElasticSwap: EXPIRED"
        );
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _quoteToken,
        address _baseToken
    ) ERC20(_name, _symbol) {
        require(
            _quoteToken != _baseToken,
            "ElasticSwap: IDENTICAL_TOKEN_ADDRESSES"
        );
        quoteToken = _quoteToken;
        baseToken = _baseToken;
    }

    function addLiquidity(
        uint256 _quoteTokenQtyDesired,
        uint256 _baseTokenQtyDesired,
        uint256 _quoteTokenQtyMin,
        uint256 _baseTokenQtyMin,
        address _liquidityTokenRecipient,
        uint256 _expirationTimestamp
    )
        external
        notExpired(_expirationTimestamp)
        returns (
            uint256 quoteTokenQty,
            uint256 baseTokenQty,
            uint256 liquidityTokenQty
        )
    {
        if (this.totalSupply() > 0) {
            // we have outstanding liquidity tokens present and an existing price curve
            uint256 quoteTokenReserveQty =
                IERC20(quoteToken).balanceOf(address(this));
            uint256 baseTokenReserveQty =
                IERC20(baseToken).balanceOf(address(this));
            uint256 requiredBaseTokenQty =
                _calculateQty(
                    _quoteTokenQtyDesired,
                    quoteTokenReserveQty,
                    baseTokenReserveQty
                );

            if (requiredBaseTokenQty <= _baseTokenQtyDesired) {
                // user has to provide less than their desired amount
                require(
                    requiredBaseTokenQty >= _baseTokenQtyMin,
                    "ElasticSwap: INSUFFICIENT_BASE_QTY"
                );
                quoteTokenQty = _quoteTokenQtyDesired;
                baseTokenQty = requiredBaseTokenQty;
            } else {
                // we need to check the opposite way.
                uint256 requiredQuoteTokenQty =
                    _calculateQty(
                        _baseTokenQtyDesired,
                        baseTokenReserveQty,
                        quoteTokenReserveQty
                    );
                assert(requiredQuoteTokenQty <= _quoteTokenQtyDesired);
                require(
                    _quoteTokenQtyDesired >= _quoteTokenQtyMin,
                    "ElasticSwap: INSUFFICIENT_QUOTE_QTY"
                );
                quoteTokenQty = requiredQuoteTokenQty;
                baseTokenQty = _baseTokenQtyDesired;
            }

            liquidityTokenQty =
                (baseTokenQty * this.totalSupply()) /
                baseTokenReserveQty;
        } else {
            // this user will set the initial pricing curve
            quoteTokenQty = _quoteTokenQtyDesired;
            baseTokenQty = _baseTokenQtyDesired;
            liquidityTokenQty = _baseTokenQtyDesired;
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
        ); // trasnfer base tokens to Exchange
        _mint(_liquidityTokenRecipient, liquidityTokenQty); // mint liquidity tokens to recipient
    }

    function removeLiquidity(
        uint256 _liquidityTokenQty,
        uint256 _quoteTokenQtyMin,
        uint256 _baseTokenQtyMin,
        address _tokenRecipient,
        uint256 _expirationTimestamp
    )
        external
        notExpired(_expirationTimestamp)
        returns (uint256 quoteTokenQtyToReturn, uint256 baseTokenQtyToReturn)
    {
        require(this.totalSupply() > 0, "ElasticSwap: INSUFFICIENT_LIQUIDITY");
        require(
            _quoteTokenQtyMin > 0 && _baseTokenQtyMin > 0,
            "ElasticSwap: MINS_MUST_BE_GREATER_THAN_ZERO"
        );

        uint256 quoteTokenReserveQty =
            IERC20(quoteToken).balanceOf(address(this));
        uint256 baseTokenReserveQty =
            IERC20(baseToken).balanceOf(address(this));

        quoteTokenQtyToReturn =
            (_liquidityTokenQty * quoteTokenReserveQty) /
            this.totalSupply();
        baseTokenQtyToReturn =
            (_liquidityTokenQty * baseTokenReserveQty) /
            this.totalSupply();

        require(
            quoteTokenQtyToReturn >= _quoteTokenQtyMin,
            "ElasticSwap: INSUFFICIENT_QUOTE_QTY"
        );

        require(
            baseTokenQtyToReturn >= _baseTokenQtyMin,
            "ElasticSwap: INSUFFICIENT_BASE_QTY"
        );

        _burn(msg.sender, _liquidityTokenQty);

        IERC20(quoteToken).safeTransfer(_tokenRecipient, quoteTokenQtyToReturn);
        IERC20(baseToken).safeTransfer(_tokenRecipient, baseTokenQtyToReturn);
    }

    function swapQuoteTokenForBaseToken(
        uint256 _quoteTokenQty,
        uint256 _minBaseTokenQty,
        uint256 _expirationTimestamp
    ) external notExpired(_expirationTimestamp) returns (uint256 baseTokenQty) {
        require(
            _quoteTokenQty > 0 && _minBaseTokenQty > 0,
            "ElasticSwap: INSUFFICIENT_TOKEN_QTY"
        );
        uint256 quoteTokenReserveQty =
            IERC20(quoteToken).balanceOf(address(this));
        uint256 baseTokenReserveQty =
            IERC20(quoteToken).balanceOf(address(this));
        baseTokenQty = _getPrice(
            _quoteTokenQty,
            quoteTokenReserveQty,
            baseTokenReserveQty
        );
        require(
            baseTokenQty > _minBaseTokenQty,
            "ElasticSwap: INSUFFICIENT_BASE_TOKEN_QTY"
        );

        IERC20(quoteToken).safeTransferFrom(
            msg.sender,
            address(this),
            _quoteTokenQty
        );
        IERC20(baseToken).safeTransfer(msg.sender, baseTokenQty);
    }

    function swapBaseTokenForQuoteToken(
        uint256 _baseTokenQty,
        uint256 _minQuoteTokenQty,
        uint256 _expirationTimestamp
    )
        external
        notExpired(_expirationTimestamp)
        returns (uint256 quoteTokenQty)
    {
        require(
            _baseTokenQty > 0 && _minQuoteTokenQty > 0,
            "ElasticSwap: INSUFFICIENT_TOKEN_QTY"
        );

        uint256 quoteTokenReserveQty =
            IERC20(quoteToken).balanceOf(address(this));
        uint256 baseTokenReserveQty =
            IERC20(baseToken).balanceOf(address(this));

        quoteTokenQty = _getPrice(
            _baseTokenQty,
            baseTokenReserveQty,
            quoteTokenReserveQty
        );

        require(
            quoteTokenQty > _minQuoteTokenQty,
            "ElasticSwap: INSUFFICIENT_QUOTE_TOKEN_QTY"
        );

        IERC20(baseToken).safeTransferFrom(
            msg.sender,
            address(this),
            _baseTokenQty
        );
        IERC20(quoteToken).safeTransfer(msg.sender, quoteTokenQty);
    }

    function _calculateQty(
        uint256 _tokenAQty,
        uint256 _reserveAQty,
        uint256 _reserveBQty
    ) internal pure returns (uint256 tokenBQty) {
        require(_tokenAQty > 0, "ElasticSwap: INSUFFICIENT_QTY");
        require(
            _reserveAQty > 0 && _reserveBQty > 0,
            "ElasticSwap: INSUFFICIENT_LIQUIDITY"
        );
        tokenBQty = (_tokenAQty * _reserveBQty) / _reserveAQty;
    }

    function _getPrice(
        uint256 _tokenATradeQty,
        uint256 _tokenAReserveQty,
        uint256 _tokenBReserveQty
    ) internal pure returns (uint256 price) {
        uint256 tokenATradeQtyWithFee =
            _tokenATradeQty * (basisPoints - liquidityFee);
        price =
            (tokenATradeQtyWithFee * _tokenBReserveQty) /
            ((_tokenAReserveQty * basisPoints) + tokenATradeQtyWithFee);
    }
}
