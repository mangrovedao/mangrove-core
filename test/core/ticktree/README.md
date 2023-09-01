This folder contains tests of Mangrove's tick tree to ensure that the tree is always in a consistent state.

# High-level test approach

For optimization reasons, the tick tree data structure is not encapsulated but read and manipulated in a low-level way in all the operations that use it (and this is interleaved with other non-tree logic). This means that we cannot unit test the data structure, but instead have to make integration tests of all the functions that manipulate the tree.

The approach taken in these integration tests is to simulate what Mangrove should be doing to its tick tree in a parallel tick tree implementation which is simpler and easier to reason about. By comparing the resulting tick trees (MGV and the test implementation) we can check that they agree on the end state; If not, we can report exactly where the discrepancy is.

In overview, the tests are structured as follows:

1. Set up Mangrove's initial state, i.e, post offers at relevant ticks (and possibly retract some of them).
2. Take a snapshot of Mangrove's tick tree, i.e, a copy in the form of a test `TickTree`
3. Perform some operation on Mangrove (e.g, add or remove an offer)
4. Perform equivalent operation(s) on the test `TickTree`
5. Compare Mangrove's tick tree to the test `TickTree`.

# Structure of the test contracts

There are multiple test contracts named `TickTree*` all located in `test/core/ticktree`.

The base contract is `TickTreeTest` and implements the test `TickTree` struct and operations on it as well as shared functions for the test contracts.

For each Mangrove operation that modifies the tick tree, there is a separate contract which tests that operation on the tick tree. For example, `newOffer*` is tested in `TickTreeNewOfferTest`.

# Test scenarios

Mangrove's tick tree is quite complex due to the different levels each being stored separately as well as some things being stored in `local`. There are there many scenarios to test, e.g, updating an offer to another tick within the same `Leaf` is different than updating it to a tick below a different level1 position.

## Tick scenarios

### Tick of interest, higher tick, and lower tick

For all the tests, there's a notion of "tick of interest", a higher tick, and a lower tick. This allows us to capture the different scenarios where ticks are in the same/different leaf, level0, level1, and level2. `TickTreeTest` contains functions for generating all relevant higher and lower ticks for a given tick of interest. Combinations of three such ticks (including the absence of higher/lower) is captured by the `TickScenario` struct.

For each test contract, these we define a `*Scenario` struct (eg `UpdateOfferScenario`) that defines what a scenario looks like and we describe how the `TickScenario` should be interpreted in these scenarios.

## Structure of test contracts

The tests contracts are therefore generally structured as follows:

1. An execute scenario function (e.g, `run_update_offer_scenario`)

- This executes a single scenario.
- As this function may be called multiple times within a single `test_*` function, it does a `vm.snapshot()` initially and a `vm.revertTo(vmSnapshotId)` at the end. This is super fragile and if a scenario fails, you may see other, totally unrelated tests fail...

2. An execute scenarios for a specific tick (e.g, `run_update_offer_scenarios_for_tick`)

- This runs all scenarios for a particular tick of interest
- The reason for running multiple scenarios in one function is to avoid having to manually write many `test_*` functions that enumerate all the scenarios.

3. One or more `test_*` functions (e.g, `test_clean_offer_for_tick_0`)

- This is the actual test function that `forge` will run.
- The reason for having multiple `test*_` functions instead of running all scenarios in one test is that we run into limitations of `Foundry` when we do this.
- In other words, there's a limit to how many scenarios we can run in one `test_*` function which depends on the memory used by the `run_*_scenario` function.
- We've tried to minimize the number of `test_*` functions, but for `updateOffer` we've had to make 4 `test_*` functions per tick we want to test :-/
