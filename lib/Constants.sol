// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

/* For all the relevant constants here, the non-literal expression that computes them is checked in `Constants.t.sol`. */

uint constant ONE = 1; // useful to name it for drawing attention sometimes
uint constant ONES = type(uint).max;
uint constant TOPBIT = 1 << 255;
// can't write ~TOPBIT or ~uint(1 << 255) or constant cannot be referred to from assembly
uint constant NOT_TOPBIT = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

// MIN_BIN and MAX_BIN should be inside the addressable range defined by the sizes of LEAF, LEVEL3, LEVEL2, LEVEL1, ROOT
int constant MIN_BIN = -1048576;
int constant MAX_BIN = 1048575;

// sizes must match field sizes in structs.ts where relevant
uint constant TICK_BITS = 21;
uint constant OFFER_BITS = 32;
uint constant MAX_FIELD_SIZE = 64; // Constraint given by BitLib.ctz64

// only power-of-two sizes are supported for LEAF_SIZE and LEVEL*_SIZE
uint constant LEAF_SIZE_BITS = 2; 
uint constant LEVEL_SIZE_BITS = 6;
uint constant ROOT_SIZE_BITS = 1;

int constant LEAF_SIZE = 4;
int constant LEVEL_SIZE = 64;
int constant ROOT_SIZE = 2;

uint constant LEAF_SIZE_MASK = 3;
uint constant LEVEL_SIZE_MASK = 63;
uint constant ROOT_SIZE_MASK = 1;

int constant NUM_LEVEL1 = 2;
int constant NUM_LEVEL2 = 128;
int constant NUM_LEVEL3 = 8192;
int constant NUM_LEAFS = 524288;
int constant NUM_BINS = 2097152;

uint constant OFFER_MASK = 4294967295;

// The tick range is the largest such that 1.0001^MAX_TICK fits on 128 bits (and thus can be multiplied by volumes)
int constant MIN_TICK = -887272;
int constant MAX_TICK = 887272;
// These are reference values for what the function will return, not the most possible accurate values for the min and max tick.
uint constant MIN_RATIO_MANTISSA = 170153974464283981435225617938057077692;
int constant MIN_RATIO_EXP = 255;
uint constant MAX_RATIO_MANTISSA = 340256786836388094050805785052946541084;
int constant MAX_RATIO_EXP = 0;
/* `MANTISSA_BITS is the number of bits used in the mantissa of normalized floats that represent ratios. 128 means we can multiply all allowed volumes by the mantissa and not overflow. */
uint constant MANTISSA_BITS = 128;
uint constant MANTISSA_BITS_MINUS_ONE = 127;
/* 
With |tick|<=887272 and normalized mantissas on 128 bits, the maximum possible mantissa is 340282295208261841796968287475569060645, so the maximum safe volume before overflow is actually 340282438633630198193436196978374475856. 

The immediate idea is to set MAX_SAFE_VOLUME to `(1<<max_safe_volume_bits)-1`, where `max_safe_volume_bits = 256-MANTISSA_BITS`, for simplicity. But we'd have `MAX_SAFE_VOLUME > 1.0001^MAX_TICK`, so a `*ByVolume` function called with `MAX_SAFE_VOLUME` and `1` as arguments would revert. To have uniform constraints on volumes everywhere, we just set `max_safe_volume_bits = 256 - MANTISSA_BITS - 1`.
*/
uint constant MAX_SAFE_VOLUME = 170141183460469231731687303715884105727;
// Without optimizer enabled it fails above 79. With optimizer and 200 runs it fails above 80. Set default a bit lower to be safe.
uint constant INITIAL_MAX_RECURSION_DEPTH = 75;
uint constant INITIAL_MAX_GASREQ_FOR_FAILING_OFFERS_MULTIPLIER = 3;

// Tick range limits the allowed bins to a subset of the full range
int constant MIN_BIN_ALLOWED = MIN_TICK;
int constant MAX_BIN_ALLOWED = MAX_TICK;

// log_1.0001(2)
uint constant LOG_BP_SHIFT = 235;
uint constant LOG_BP_2X235 = 382733217082594961806491056566382061424140926068392360945012727618364717537;
