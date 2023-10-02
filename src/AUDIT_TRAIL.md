# Audit trail

## Starting point

Mangrove v1.5 (formerly Mangrove v5) is:

mangrove.js@2fc357f369416afdc2846cc9d5be483b75169e8d/packages/mangrove-solidity/contracts/\*.sol

Which corresponds to:

mangrove-core@c9fb1bcd4229da880d2c1c88830c25b9c873f4f0/contracts/\*.sol

## Commits

e6b415de0c4f842c7356feab44e8de1c3812fc08

Updates MgvPack (outside of audit scope), and related imports / `using for` statements.

c379b76d9406b13385f40da17367f8602233ce1d

fix: correct comment in IMangrove.sol

b14bdf4020c5c3abc197dab213379d222f647f2b

refactor: fold ERC20 iface in MgvLib

967b7412c41ef8d69333b422af7a7fd62522d5ae

move contracts/ src/
(big commit that removes hardhat)

967b7412c41ef8d69333b422af7a7fd62522d5ae
a38fb472e145e688b029ea686f170302b7c2e88d
9e350777adfbc48ab1c7e2d3d2692bcc767e0f42

comments

To jump from 9e350777adfbc48ab1c7e2d3d2692bcc767e0f42 to 5a90b43fd89b86d6d907aa0972822a95b0237880, apply the following to ` src/*.sol`, using [ruplacer](https://github.com/your-tools/ruplacer).

```bash
ruplacer ', P,' ', MgvStructs,' --go

ruplacer 'P}' 'MgvStructs}' --go

ruplacer 'Pack.post.sol" as P' 'Structs.post.sol" as MgvStructs' --go

ruplacer 'P\.(.+?)\.t' '${1}' --go

ruplacer 'P\.(.+?)Struct' '${1}Unpacked' --go

ruplacer 'MgvLib as ML' 'MgvLib' --go

ruplacer 'ML' 'MgvLib' --go

ruplacer cancelations cancellations --go

ruplacer 'offer book' 'order book' --go

ruplacer availale available --go

FOUNDRY_FMT_TAB_WIDTH=2 FOUNDRY_FMT_INT_TYPES="short" FOUNDRY_FMT_NUMBER_UNDERSCORE="th
ousands" forge fmt

ruplacer 'P\.(.+?)\.pack' 'MgvStructs.${1}.pack' --go

FOUNDRY_FMT_TAB_WIDTH=2 FOUNDRY_FMT_INT_TYPES="short" FOUNDRY_FMT_NUMBER_UNDERSCORE="th
ousands" forge fmt
```

Only difference left will be the ABI included in comments of IMangrove.sol

c1f4d492a056f46805cf39b3a8e65d1f26ba889e

Change copyright

4f27038fa16250df04fb545dfcf2bfc9bd1a6f38
845a6dc0a4dfbdeac965afce8cf2aa97717160f5
3a86e263a2233293e894f53864a4ece04dc6f411

comments&pragmas

bf2c55a2df6687763aaea33c828998512b1aaa9d
42d10ba5e8ce8bd7381854946f9b43b8fcc0739b

noop taken together

then compare the audit branch's commits with master

# Invariant notes

Some invariants noted auditors:

## Mangrove does not attempt to transfer out more than it has received during an order execution.

Important since fees started being accumulated in Mangrove. Before that, excess transfers would revert. Since the change, they would be stealing accumulated fees. As a particular case:

### When amounts are accumulated in mor.totalGot, no overflow/underflow can make the final mor.totalGot different from the sum of the individual transfers from the makers.

Similarly, fees might be drained if the total owed to takers goes above the total received from makers.

## The "takingWithPermit" functionality can't be abused by setting the contract address as the taker callbacks to external addresses happen toward addresses that act at some point as the msg.sender (makers have to create their own offers), so can't call token addresses outside of the transfer/transferFrom normal flows. Which could be exploitable if IMaker shares signatures with ERC20.
