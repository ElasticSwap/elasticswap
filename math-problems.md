### Removes entire decay (5000 quote tokens)- everything works. 

new liquidity provider balance: 0
new liquidity provider LP balance: 1999
new liquidity provider base token exit: 2498 (they put in 0)
new liquidity provider quoteToken exit: 2498 (they put in 5000)
old liquidity provider LP balance: 10000
old liquidity provider base token exit: 12502 (they put in 15000)
old liquidity provider quoteToken exit: 12502 (they put in 10000)
exchange quote bal: 0
exchange base bal: 0


### Removes partial decay (2500 quote tokens - half of the above)

new liquidity provider balance: 0
new liquidity provider LP balance: 526 
new liquidity provider base token exit: 749 (they put in 0)
new liquidity provider quoteToken exit: 624 (they put in 1250)
old liquidity provider LP balance: 10000
old liquidity provider base token exit: 14251 (they put in 15000) 749  less base tokens
old liquidity provider quoteToken exit: 11876 (they put in 10000) 1876 more quote tokens
exchange quote bal: 0
exchange base bal: 0

This _should_ be zero sum so these should be equivalent.

- 749 base tokens ~ 1876 quote tokens
- Sigma is the relationship between actual balances of base/quote Sigma = Alpha / Beta
- After rebase, after lp2 contributes - Sigma = 15000 / (10000 + 2500) = 1.2
- After lp2 withdraw Sigma should be unchanged = (15000 - 749) / (12500 - 624) = 14251 / 11876 = 1.2
- 749 base token : 1876 quot tokens    749 / 1.2 = 624 quote tokens.... 1252 quote tokens too many!

-------------------

Other notes:

- Our Ro issuance in the presence of decay is not linear. 1/2 the quote tokens in gives 1/4 of the LP tokens
- Another problem lp3 could come along and add 1/2 the quote tokens and get 3/4 of the lp tokens (since its not linear!)


Possible solutions:

- Apply a correction factor when redemption occurs in the presence of decay. 
- Re-evaluate the issuance of Ro. 


-------------------
Using the new formula: 
new liquidity provider balance: 0
new liquidity provider LP balance: 999
new liquidity provider base token exit: 1362
new liquidity provider quoteToken exit: 1135
old liquidity provider LP balance: 10000
old liquidity provider base token exit: 13638 (they put in 15000) 1362 less base tokens
old liquidity provider quoteToken exit: 11365 (they put in 15000) 3635 less quote Tokens
exchange quote bal: 0
exchange base bal: 0
- After rebase, after lp2 contributes - Sigma = 15000 / (10000 + 2500) = 1.2
- After lp2 withdraw Sigma should be unchanged = 13638/11365 = 1.2