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
new liquidity provider quoteToken exit: 624 (they put in 1250) (may be incorrect, should be 2500)
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
new liquidity provider base token exit: 1362 (put in 0)
new liquidity provider quoteToken exit: 1135 (put in 2500)
old liquidity provider LP balance: 10000
old liquidity provider base token exit: 13638 (they put in 10000) 3638 more base tokens
old liquidity provider quoteToken exit: 11365 (they put in 10000) 1365 more quote Tokens
exchange quote bal: 0
exchange base bal: 0
- After rebase, after lp2 contributes - Sigma = 15000 / (10000 + 2500) = 1.2
- After lp2 withdraw Sigma should be unchanged = 13638/11365 = 1.2
- 1362 base token: 1135 quote token  1362 / 1.2 = 1135 : 0 tokens too many.



---

### Rebase down scenario - removes partial decay (2500 base tokens)
LP 1 balance : 10000 (put in 10k Base and Quote tokens)

Using the new formula: 
new liquidity provider balance: 0
new liquidity provider LP balance: 2000 (?)
new liquidity provider base token exit: 1250 (put in 0)
new liquidity provider quoteToken exit: 1167 (put in 2500)
old liquidity provider LP balance: 10000
old liquidity provider base token exit: 6250 (they put in 10000) 3750 less base tokens
old liquidity provider quoteToken exit: 8333 (they put in 10000) 1667 less quote Tokens
exchange quote bal: 0
exchange base bal: 0
- After rebase, after lp2 contributes - Sigma = 5000 + 2.5 / (10000) = 0.75
- After lp2 withdraw Sigma should be unchanged = 6250/8333 = 0.75
- 6250 base token: 8333 quote token  6250 / 0.75 = 8333 : 0 tokens too many.

10k   10k
5k    10k
+2.5k  10k

### Rebase down scenario - removes complete decay (5000 base tokens)
LP 1 balance : 10000 (put in 10k Base and Quote tokens)

Using the new formula: 
new liquidity provider balance: 0
new liquidity provider LP balance: 4999 (?)
new liquidity provider base token exit: 3333 (put in 0)
new liquidity provider quoteToken exit: 3333 (put in 5000)
old liquidity provider LP balance: 10000
old liquidity provider base token exit: 6667 (they put in 10000) 3333 less base tokens
old liquidity provider quoteToken exit: 6667 (they put in 10000) 3333 less quote Tokens
exchange quote bal: 0
exchange base bal: 0
- After rebase, after lp2 contributes - Sigma = 5000 + 5000 / (10000) = 1
- After lp2 withdraw Sigma should be unchanged = 6667/6667 = 1
- 3333 base token: 3333 quote token  3333 / 1 = 3333 : 0 tokens too many.