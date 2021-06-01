# Elastic Swap

The first automated market maker (AMM) with native support for tokens with elastic supply


# TODO
1. Create exchange contract factory that sets ownership correctly
  1. Contract factory could provide ownership and aggregate fee withdrawal for ElasticDAO
  1. Can also house lookup of contracts by address
2. Gas optimizations
3. review tracking of reserve amount
4. Add events
5. Fees
6. Fix compile issues in tests using open zepp libs



# Open Questions
1. Supporting arbitrary ERC20 fee intake into ElasticDAO treasury or converting
1. Lock minimum liquidity?
1. Do we need "reverse" pricing?  IE I want to buy as much of tokenA as possible with N tokenB.

# Version 2 
1. Support elastic tokens for both quote and base currencies.
    1. is this valuable vs router and extra hop (fix supply intermediary)?
2. Add boolean flag to handle non elastic supply token optimizations