// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRwaVenue} from "./IRwaVenue.sol";

/// @notice A tokenized-equity stand-in, one per ticker.
/// @dev TESTNET ONLY. Mintable and burnable by its venue. On mainnet these are real Robinhood Stock
///      Tokens and the venue trades against actual liquidity.
contract MockRwaToken is ERC20 {
    address public immutable VENUE;

    error OnlyVenue();

    constructor(string memory name_, string memory symbol_, address venue) ERC20(name_, symbol_) {
        VENUE = venue;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != VENUE) revert OnlyVenue();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != VENUE) revert OnlyVenue();
        _burn(from, amount);
    }
}

/// @title MockRwaVenue — a stand-in market for tokenized equities
/// @notice Lets the Drop execute for real on a chain with no swap venue: aggregate purchase,
///         escrow, claim, and the unclaimed-sale buyback all run end to end.
/// @dev
///      ████  T E S T N E T   O N L Y  ████
///
///      Mints assets out of nothing at an owner-set price. There is no liquidity and no price
///      discovery. It exists so the Drop's mechanics are exercisable rather than shipping untested.
///
///      TO SHIP TO MAINNET: implement IRwaVenue against a real venue for Robinhood Stock Tokens,
///      priced by Chainlink Data Feeds (live on Robinhood Chain), and call `Drop.setVenue`. The Drop
///      itself needs no change.
contract MockRwaVenue is IRwaVenue, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Units of asset per 1e18 of payToken, 1e18 fixed point.
    mapping(bytes32 ticker => uint256) public priceOf;
    mapping(bytes32 ticker => address) public tokenOf;
    mapping(bytes32 ticker => bool) public available;

    bytes32[] public tickers;

    event TickerListed(bytes32 indexed ticker, address asset);
    event TickerAvailability(bytes32 indexed ticker, bool available);
    event Bought(bytes32 indexed ticker, uint256 amountIn, uint256 amountOut);
    event Sold(address indexed asset, uint256 amountIn, uint256 amountOut);

    error UnknownTicker();

    constructor() Ownable(msg.sender) {}

    /// @notice Create a mock asset for a ticker at a starting price.
    function listTicker(bytes32 ticker, string calldata name_, string calldata symbol_, uint256 price)
        external
        onlyOwner
        returns (address asset)
    {
        if (tokenOf[ticker] == address(0)) {
            asset = address(new MockRwaToken(name_, symbol_, address(this)));
            tokenOf[ticker] = asset;
            tickers.push(ticker);
        } else {
            asset = tokenOf[ticker];
        }
        priceOf[ticker] = price;
        available[ticker] = true;
        emit TickerListed(ticker, asset);
    }

    /// @notice Simulate a delisting, so the "unavailable ticker" path is testable.
    function setAvailable(bytes32 ticker, bool ok) external onlyOwner {
        available[ticker] = ok;
        emit TickerAvailability(ticker, ok);
    }

    function setPrice(bytes32 ticker, uint256 price) external onlyOwner {
        priceOf[ticker] = price;
    }

    /// @inheritdoc IRwaVenue
    function isAvailable(bytes32 ticker) external view override returns (bool) {
        return available[ticker] && tokenOf[ticker] != address(0);
    }

    /// @inheritdoc IRwaVenue
    function assetFor(bytes32 ticker) external view override returns (address) {
        return tokenOf[ticker];
    }

    /// @inheritdoc IRwaVenue
    function buy(bytes32 ticker, address payToken, uint256 amountIn)
        external
        override
        returns (address asset, uint256 amountOut)
    {
        if (!available[ticker] || tokenOf[ticker] == address(0)) return (address(0), 0);

        IERC20(payToken).safeTransferFrom(msg.sender, address(this), amountIn);
        asset = tokenOf[ticker];
        amountOut = (amountIn * priceOf[ticker]) / 1e18;
        MockRwaToken(asset).mint(msg.sender, amountOut);
        emit Bought(ticker, amountIn, amountOut);
    }

    /// @inheritdoc IRwaVenue
    function sell(address asset, uint256 amount, address wantToken)
        external
        override
        returns (uint256 amountOut)
    {
        MockRwaToken(asset).burn(msg.sender, amount);
        // Reverse the mint rate. The venue holds whatever was paid in on the way through.
        bytes32 ticker = _tickerOf(asset);
        uint256 price = priceOf[ticker];
        amountOut = price == 0 ? 0 : (amount * 1e18) / price;

        uint256 held = IERC20(wantToken).balanceOf(address(this));
        if (amountOut > held) amountOut = held;
        if (amountOut > 0) IERC20(wantToken).safeTransfer(msg.sender, amountOut);
        emit Sold(asset, amount, amountOut);
    }

    function _tickerOf(address asset) internal view returns (bytes32) {
        uint256 n = tickers.length;
        for (uint256 i = 0; i < n; i++) {
            if (tokenOf[tickers[i]] == asset) return tickers[i];
        }
        revert UnknownTicker();
    }

    function tickerCount() external view returns (uint256) {
        return tickers.length;
    }
}
