# next version

# 1.4.1 (January 2022)

- Export SimpleTestMaker bytecode
- Open markets in MangoveJsDeploy script
- TestMaker can revert individual offers

# 1.4.0 (December 2022)

- Added Polygon mainnet deployment addresses
- Added permissionless open markets tracking to MgvReader

# 1.3.0 (December 2022)

- Fix issue in provision calculations in stratlib
- Some gas optimizations in the stratlib
- Update mumbai deployment addresses
- Update PxUSDC and PxMATIC Polygon mainnet addresses

# 1.2.0 (December 2022)

- Added Polygon mainnet deployment addresses
- Remove slippage from MangroveOrder - resting order now posted at same price
- Introduce **reserve** hook on MangroveOffer which replaces other reserve logic
- Add collectByImpersonation to MgvCleaner
- `ILiquidityProvider` provide simple `updateOffer` and `newOffer` public functions, using default values for `gasprice` and `gasreq`. This unifies interface between Forwarder and Direct strats. Strat builders can still implement a public offer management that lets offer owners set gasreq and gasprice

# 1.1.3 (Nov 2022)

- updating test deployment script

# 1.1.2 (nov 2022)

- updating `mangroveorder` deployment address

# 1.1.1 (Nov 2022)

- Updating `MangroveOrder` deployment address

# 1.1.0 (November 2022)

- ABI change to `MangroveOrder` after various fixes (code audit)
- Forwarder strats no longer deprovision offer automatically to fix out of gas issues in posthook (pull based deprovision)
- various improvement to routers and Forwarder strats

# 1.0.4 (October 2022)

- Fix 1.0.3 bad package.json (was not exporting enough)

# 1.0.3 (October 2022)

- Fix 1.0.2 bad index.js (was referencing absent files)

# 1.0.2 (October 2022)

- Export all solidity files
- Change dist/export layout

# 1.0.1 (October 2022)

- Correctly export files in `dist/index.js`.

# 1.0.0 (October 2022)

- Initial release, see `mangrovedao/mangrove` in `packages/mangrove-solidity` for the history before.
