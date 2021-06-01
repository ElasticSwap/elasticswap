const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Exchange", () => {
  const name = "EGT LP Token";
  const symbol = "EGTLPS";
  const initialSupply = 1000000000;
  let exchange;
  let baseToken;
  let quoteToken;
  let accounts;

  beforeEach(async () => {
    accounts = await ethers.getSigners();
    const exchangeContractFactory = await ethers.getContractFactory("Exchange");
    const tokenFactory = await ethers.getContractFactory(
      "ERC20PresetFixedSupply"
    );
    quoteToken = await tokenFactory.deploy(
      "ElasticTokenMock",
      "ETM",
      initialSupply,
      accounts[0].address
    );
    baseToken = await tokenFactory.deploy(
      "Fake-USD",
      "FUSD",
      initialSupply,
      accounts[0].address
    );
    exchange = await exchangeContractFactory.deploy(
      name,
      symbol,
      quoteToken.address,
      baseToken.address
    );

    await exchange.deployed();
  });

  it("Should deploy with correct name, symbol and adresses", async () => {
    expect(await exchange.name()).to.equal(name);
    expect(await exchange.symbol()).to.equal(symbol);
    expect(await exchange.baseToken()).to.equal(baseToken.address);
    expect(await exchange.quoteToken()).to.equal(quoteToken.address);
  });

  it("Should allow for user to supply liquidity and immediately withdrawl equal amounts", async () => {
    const amountToAdd = 1000000;
    // create expiration 50 minutes from now.
    const expiration = Math.round(new Date().getTime() / 1000 + 60 * 50);

    // check original balances
    expect(await quoteToken.balanceOf(accounts[0].address)).to.equal(
      initialSupply
    );
    expect(await baseToken.balanceOf(accounts[0].address)).to.equal(
      initialSupply
    );

    // add approvals
    await baseToken.approve(exchange.address, amountToAdd);
    await quoteToken.approve(exchange.address, amountToAdd);

    await exchange.addLiquidity(
      amountToAdd,
      amountToAdd,
      1,
      1,
      accounts[0].address,
      expiration
    );

    // check token balances after (should be reduced)
    expect(await quoteToken.balanceOf(accounts[0].address)).to.equal(
      initialSupply - amountToAdd
    );
    expect(await baseToken.balanceOf(accounts[0].address)).to.equal(
      initialSupply - amountToAdd
    );
    expect(await exchange.balanceOf(accounts[0].address)).to.equal(amountToAdd);

    // add approval for the liquidity tokens we now have.
    const amountToRedeem = amountToAdd / 2;
    await exchange.approve(exchange.address, amountToRedeem);

    await exchange.removeLiquidity(
      amountToRedeem,
      amountToRedeem,
      amountToRedeem,
      accounts[0].address,
      expiration
    );

    // confirm expected balances after redemption
    expect(await quoteToken.balanceOf(accounts[0].address)).to.equal(
      initialSupply - amountToRedeem
    );
    expect(await baseToken.balanceOf(accounts[0].address)).to.equal(
      initialSupply - amountToRedeem
    );
    expect(await exchange.balanceOf(accounts[0].address)).to.equal(
      amountToRedeem
    );
  });

  it("Should allow for user to supply liquidity, a rebase to occur, and correct withdraw of rebased qty", async () => {
    const amountToAdd = 1000000;
    // create expiration 50 minutes from now.
    const expiration = Math.round(new Date().getTime() / 1000 + 60 * 50);
    const liquidityProvider = accounts[1];

    // send a second user (liquduity provider) quote and base tokens for easy accounting.
    await quoteToken.transfer(liquidityProvider.address, amountToAdd);
    await baseToken.transfer(liquidityProvider.address, amountToAdd);

    // check original balances
    expect(await quoteToken.balanceOf(liquidityProvider.address)).to.equal(
      amountToAdd
    );
    expect(await baseToken.balanceOf(liquidityProvider.address)).to.equal(
      amountToAdd
    );

    // add approvals
    await baseToken
      .connect(liquidityProvider)
      .approve(exchange.address, amountToAdd);
    await quoteToken
      .connect(liquidityProvider)
      .approve(exchange.address, amountToAdd);

    await exchange
      .connect(liquidityProvider)
      .addLiquidity(
        amountToAdd,
        amountToAdd,
        1,
        1,
        liquidityProvider.address,
        expiration
      );

    // check token balances after (should be reduced)
    expect(await quoteToken.balanceOf(liquidityProvider.address)).to.equal(0);
    expect(await baseToken.balanceOf(liquidityProvider.address)).to.equal(0);
    expect(await exchange.balanceOf(liquidityProvider.address)).to.equal(
      amountToAdd
    );

    // simluate a rebase by sending more tokens to our exchange contract.
    expect(await quoteToken.balanceOf(exchange.address)).to.equal(amountToAdd);
    const rebaseAmount = 1000;
    await quoteToken.transfer(exchange.address, rebaseAmount);
    // confirm the exchange now has the expected balance after rebase
    expect(await quoteToken.balanceOf(exchange.address)).to.equal(
      amountToAdd + rebaseAmount
    );

    // we should be able to now pull out more tokens than we originally put in due to the rebase
    const totalQuoteTokenQtyToWithdraw = amountToAdd + rebaseAmount;
    // add approval for the liquidity tokens.
    await exchange
      .connect(liquidityProvider)
      .approve(exchange.address, amountToAdd);

    await exchange
      .connect(liquidityProvider)
      .removeLiquidity(
        amountToAdd,
        totalQuoteTokenQtyToWithdraw,
        amountToAdd,
        liquidityProvider.address,
        expiration
      );

    // confirm expected balances after redemption
    expect(await quoteToken.balanceOf(liquidityProvider.address)).to.equal(
      totalQuoteTokenQtyToWithdraw
    );
    expect(await baseToken.balanceOf(liquidityProvider.address)).to.equal(
      amountToAdd
    );
    expect(await exchange.balanceOf(liquidityProvider.address)).to.equal(0);
  });

  it("Should price trades correctly before and after a rebase when trading the base token", async () => {
    const amountToAdd = 1000000;
    // create expiration 50 minutes from now.
    const expiration = Math.round(new Date().getTime() / 1000 + 60 * 50);
    const liquidityProvider = accounts[1];
    const trader = accounts[2];

    // send a second user (liquduity provider) quote and base tokens.
    await quoteToken.transfer(liquidityProvider.address, amountToAdd);
    await baseToken.transfer(liquidityProvider.address, amountToAdd);

    // add approvals
    await baseToken
      .connect(liquidityProvider)
      .approve(exchange.address, amountToAdd);
    await quoteToken
      .connect(liquidityProvider)
      .approve(exchange.address, amountToAdd);

    // create liquidity
    await exchange
      .connect(liquidityProvider)
      .addLiquidity(
        amountToAdd,
        amountToAdd,
        1,
        1,
        liquidityProvider.address,
        expiration
      );

    // send trader base tokens
    await baseToken.transfer(trader.address, amountToAdd);
    // add approvals for exchange to trade their base tokens
    await baseToken.connect(trader).approve(exchange.address, amountToAdd);
    // confirm no balance before trade.
    expect(await quoteToken.balanceOf(trader.address)).to.equal(0);
    expect(await baseToken.balanceOf(trader.address)).to.equal(amountToAdd);

    // trader executes the first trade, our pricing should be 1:1 currently minus fees
    const firstSwapAmount = 1000;
    const expectedFee = 4;
    await exchange
      .connect(trader)
      .swapBaseTokenForQuoteToken(firstSwapAmount, 1, expiration);

    // confirm trade occured at price of 1:1
    // (firstSwapAmount paid and recieved in respective tokens minus fees)
    expect(await quoteToken.balanceOf(trader.address)).to.equal(
      firstSwapAmount - expectedFee
    );
    expect(await baseToken.balanceOf(trader.address)).to.equal(
      amountToAdd - firstSwapAmount
    );

    // simluate a 25% rebase by sending more tokens to our exchange contract.
    const rebaseAmount = amountToAdd * 0.25;
    await quoteToken.transfer(exchange.address, rebaseAmount);

    // since we have now simulated a rebase in quote token,
    // we recalculate the new price we expect to see.
    const quoteTokenBalanceAfterRebase = await quoteToken.balanceOf(
      exchange.address
    );
    const baseTokenBalanceAfterRebase = await baseToken.balanceOf(
      exchange.address
    );
    const calculatedPriceInBaseTokens =
      baseTokenBalanceAfterRebase / quoteTokenBalanceAfterRebase;

    // round and multiple to avoid floating point errors
    expect(Math.round(calculatedPriceInBaseTokens * 100)).to.equal(80);

    // to make accounting easier, we will clear all quote tokens out of our traders wallet now.
    await quoteToken
      .connect(trader)
      .transfer(
        accounts[0].address,
        await quoteToken.balanceOf(trader.address)
      );
    expect(await quoteToken.balanceOf(trader.address)).to.equal(0);

    const secondSwapAmount = 10;
    // no expectedFee; trade is too small for fee
    await exchange
      .connect(trader)
      .swapBaseTokenForQuoteToken(secondSwapAmount, 1, expiration);
    const quoteTokenQtyRecievedExpected =
      secondSwapAmount / calculatedPriceInBaseTokens;

    expect(await quoteToken.balanceOf(trader.address)).to.equal(
      Math.round(quoteTokenQtyRecievedExpected)
    );
    expect(await baseToken.balanceOf(trader.address)).to.equal(
      amountToAdd - firstSwapAmount - secondSwapAmount
    );
  });
});
