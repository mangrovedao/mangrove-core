# TODO FOR THE USUAL DEMO

       
## DONE
- implement LUsDAO, PLUsDAO, Meta-PLUsDAO
- consider whether TakerProxy is required
  - for a demo, it shouldn't be needed and it makes mangrove.js less useful
- implement trivial price-lock contract - done in the strat
  - no checks, just wrap LUsDAO in PLUsDAO and post offer
- market
  - for demo, we can accept that there is a bids list, we just wont use it
  - can't we use symbols instead of addresses in the activation script? yes
- mangrove.js
  - how do we get localhost addresses into mangrove.js?
    - manually (they are quite stable) or using npm link
  - how do we get ABI's into mangrove.js?
    - not needed in this demo since we're using standard ABI's
- web app - not implemented
  - what is needed to add support for UsUSD and Meta-PLUsDAO tokens?
  - will the web app blow up when there are no bids? (not a problem for this demo)
- approvals/whitelisting - the below might not be entirely up-to-date
  + PLUsDAO needed approvals/whitelisting:
    + LUsDAO:
      + whitelisted to allow taking/releasing custody of LUsDAO tokens  <-- achieved in deployment script
      + approved to allow transfers from: seller                        <-- achieved in mangrove.js
  + Meta-PLUsDAO needed approvals/whitelisting:
    + PLUsDAO:
      + whitelisted to allow transfers and unlocks                      <-- achieved in deployment script
      + approved to allow transfers from: PLUsMgvStrat                  <-- achieved in PLUsMgvStrat constructor
  + Price-Locking dApp approvals/whitelisting:                          <-- N/A in this demo
    + PLUsDAO:
      + whitelisted to allow locking
    + PLUsMgvStrat:
      + whitelisted to allow posting offers
  + PLUsMgvStrat needed approvals/whitelisting:
    + PLUsDAO:
      + whitelisted to allow transfers/locking                          <-- achieved in deployment script
      + approved to allow transfers from: seller                        <-- N/A in this demo
    + Meta-PLUsDAO:
      + whitelisted to allow transfers/locking                          <-- achieved in deployment script
      + approved to allow transfers from: seller                        <-- achieved in mangrove.js via LiquidityProvider
  + Mangrove needed approvals/whitelisting:
    + UsUSD:
      + approved to allow transfers from: proxy/taker                   <-- achieved in mangrove.js
    + Meta-PLUsDAO:
      + whitelisted to allow transfers/locking                          <-- achieved in deployment script
      + approved to allow transfers from: PLUsMgvStrat                  <-- achieved in deployment script via activation
- make a demo clone with no real secrets
  

