# next version

# 1.1.3 (nov 2022)

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
