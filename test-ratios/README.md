# Test TickLib / tick-ratio conversion

This folder contains tests that run too slowly to be run during the normal course of development.

Those tests verify that

- `ratioFromTick` matches a set of reference (ratio,tick) pairs for all valid ticks.
- `tickFromRatio(ratioFromTick(tick)) = tick` for all valid `tick`s.

To generate the reference (ratio,tick) pairs, run the following (takes ~5mn)

```
yarn generate-ratios
```

To run the tests run the following (takes ~1mn)

```
yarn test-ratios
```
