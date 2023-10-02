// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

/* The constants below are written as literals to optimize gas. For all the relevant constants here, the non-literal expression that computes them is checked in `Constants.t.sol`. */

uint constant ONE = 1;
uint constant ONES = type(uint).max;
uint constant TOPBIT = 0x8000000000000000000000000000000000000000000000000000000000000000;
uint constant NOT_TOPBIT = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

/* **sizes must match field sizes in `structs.ts` where relevant** */

/* Number of bits used to represent a tick */
uint constant TICK_BITS = 21;
/* Number of bits used to represent an offer id */
uint constant OFFER_BITS = 32;
/* Maximum possible size of a field -- protects against wrong code changes. Constraint given by `BitLib.ctz64`. */
uint constant MAX_FIELD_SIZE = 64;

/* `X_SIZE_BITS` is 1+log2 of the size of `X`, where size is the number of elements it holds.In a field, an element is a bit; in a leaf, an element is a pair of offer ids. For `LEVEL`s and `ROOT`, the value must be exact, so only power-of-2 sizes are allowed. */
uint constant LEAF_SIZE_BITS = 2; 
uint constant LEVEL_SIZE_BITS = 6;
uint constant ROOT_SIZE_BITS = 1;

/* `X_SIZE` is `2**X_SIZE_BITS` */
int constant LEAF_SIZE = 4;
int constant LEVEL_SIZE = 64;
int constant ROOT_SIZE = 2;

/* `X_SIZE_MASK` is `0...01...1` where the number of 1s is `X_SIZE_BITS` */
uint constant LEAF_SIZE_MASK = 0x3;
uint constant LEVEL_SIZE_MASK = 0x3f;
uint constant ROOT_SIZE_MASK = 0x1;
/* `0...01...1` with `OFFER_BITS` 1s at the end */
uint constant OFFER_MASK = 0xffffffff;

/* Same as `ROOT_SIZE` */
int constant NUM_LEVEL1 = 2;
/* Same as `NUM_LEVEL1 * LEVEL_SIZE` */
int constant NUM_LEVEL2 = 128;
/* Same as `NUM_LEVEL2 * LEVEL_SIZE` */
int constant NUM_LEVEL3 = 8192;
/* Same as `NUM_LEVEL3 * LEVEL_SIZE` */
int constant NUM_LEAFS = 524288;
/* Same as `NUM_LEAFS * LEAF` */
int constant NUM_BINS = 2097152;
/* min and max bins are defined like min and max int. */
int constant MIN_BIN = -1048576;
int constant MAX_BIN = 1048575;

/* The tick range is the largest such that the mantissa of `1.0001^MAX_TICK` fits on 128 bits (and thus can be multiplied by volumes). */
int constant MIN_TICK = -887272;
int constant MAX_TICK = 887272;
/* These are reference values for what the function `tickFromRatio` function will return, not the most possible accurate values for the min and max tick. */
uint constant MIN_RATIO_MANTISSA = 170153974464283981435225617938057077692;
int constant MIN_RATIO_EXP = 255;
uint constant MAX_RATIO_MANTISSA = 340256786836388094050805785052946541084;
int constant MAX_RATIO_EXP = 0;
/* `MANTISSA_BITS` is the number of bits used in the mantissa of normalized floats that represent ratios. 128 means we can multiply all allowed volumes by the mantissa and not overflow. */
uint constant MANTISSA_BITS = 128;
uint constant MANTISSA_BITS_MINUS_ONE = 127;
/* 
With `|tick|<=887272` and normalized mantissas on 128 bits, the maximum possible mantissa is `340282295208261841796968287475569060645`, so the maximum safe volume before overflow is `NO_OVERFLOW_AMOUNT = 340282438633630198193436196978374475856` (slightly above `2**128`).

For ease of use, we could pick a simpler, slightly smaller max safe volume: `(1<<128)-1`.

However the `*ByVolume` functions get a price by (abstractly) performing `outboundAmount/inboundAmount`. If we limit all volumes to `NO_OVERFLOW_AMOUNT` but aren't more restrictive than that, since `type(uint128).max > 1.0001**MAX_TICK`, we will get ratios that are outside the price boundaries.

We thus pick a uniform, easy to remember constraint on volumes that works everywhere: `(1<<127)-1`
*/
uint constant MAX_SAFE_VOLUME = 170141183460469231731687303715884105727;

/* When a market order consumes offers, the implementation uses recursion consumes additional EVM stack space at each new offer. To avoid reverting due to stack overflow, Mangrove keeps a counter and stops the market order when it reaches a maximum recursion depth. `INITIAL_MAX_RECURSION_DEPTH` is the maximum recursion depth given at deployment time.

See `maxRecursionDepth` in `structs.ts`

Without optimizer enabled it fails above 79. With optimizer and 200 runs it fails above 80. Set default a bit lower to be safe. */
uint constant INITIAL_MAX_RECURSION_DEPTH = 75;

/* When a market order consumes offers, it may use gas on offers that fail to deliver. To avoid reverts after a string of failing offers that consumes more gas than is available in a block, Mangrove stops a market order after it has gone through failing offers such that their cumulative `gasreq` is greater than the global `maxGasreqForFailingOffers` parameter. At deployment, `maxGasreqForFailingOffers` is set to:
```
INITIAL_MAX_GASREQ_FOR_FAILING_OFFERS_MULTIPLIER * gasmax
``` */
uint constant INITIAL_MAX_GASREQ_FOR_FAILING_OFFERS_MULTIPLIER = 3;

/* Those two constants are used in `TickLib.ratioFromTick` to convert a log base 1.0001 to a log base 2. */
uint constant LOG_BP_SHIFT = 235;
uint constant LOG_BP_2X235 = 382733217082594961806491056566382061424140926068392360945012727618364717537;