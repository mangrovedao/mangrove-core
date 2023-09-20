// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

uint constant ONE = 1; // useful to name it for drawing attention sometimes
uint constant ONES = type(uint).max;
uint constant TOPBIT = 1 << 255;
// can't write ~TOPBIT or ~uint(1 << 255) or constant cannot be referred to from assembly
uint constant NOT_TOPBIT = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

// MIN_TICK_TREE_INDEX and MAX_TICK_TREE_INDEX should be inside the addressable range defined by the sizes of LEAF, LEVEL0, LEVEL1, LEVEL2, ROOT
int constant MIN_TICK_TREE_INDEX = -1048576;
int constant MAX_TICK_TREE_INDEX = -MIN_TICK_TREE_INDEX-1;

// sizes must match field sizes in structs.ts where relevant
// FIXME add tests for ^
uint constant TICK_TREE_INDEX_BITS = 24;
uint constant OFFER_BITS = 32;
uint constant MAX_FIELD_SIZE = 64; // Constraint given by BitLib.ctz64

// only power-of-two sizes are supported for LEAF_SIZE and LEVEL*_SIZE
uint constant LEAF_SIZE_BITS = 2; 
uint constant LEVEL_SIZE_BITS = 6;
uint constant ROOT_SIZE_BITS = 1;

int constant LEAF_SIZE = int(2 ** (LEAF_SIZE_BITS));
int constant LEVEL_SIZE = int(2 ** (LEVEL_SIZE_BITS));
int constant ROOT_SIZE = int(2 ** (ROOT_SIZE_BITS));

uint constant LEAF_SIZE_MASK = ~(ONES << LEAF_SIZE_BITS);
uint constant LEVEL_SIZE_MASK = ~(ONES << LEVEL_SIZE_BITS);
uint constant ROOT_SIZE_MASK = ~(ONES << ROOT_SIZE_BITS);

int constant NUM_LEVEL2 = int(ROOT_SIZE);
int constant NUM_LEVEL1 = NUM_LEVEL2 * LEVEL_SIZE;
int constant NUM_LEVEL0 = NUM_LEVEL1 * LEVEL_SIZE;
int constant NUM_LEAFS = NUM_LEVEL0 * LEVEL_SIZE;
int constant NUM_TICK_TREE_INDICES = NUM_LEAFS * LEAF_SIZE;

uint constant OFFER_MASK = ONES >> (256 - OFFER_BITS);



// +/- 2**20-1 because only 20 bits are examined by the logPrice->ratio function
int constant MIN_LOG_PRICE = -((1 << 20)-1);
int constant MAX_LOG_PRICE = -MIN_LOG_PRICE;
uint constant MIN_RATIO_MANTISSA = 4735129379934731672174804159539094721182826496;
int constant MIN_RATIO_EXP = 303;
uint constant MAX_RATIO_MANTISSA = 3441571814221581909035848501253497354125574144;
int constant MAX_RATIO_EXP = 0;
uint constant MANTISSA_BITS = 152;
uint constant MANTISSA_BITS_MINUS_ONE = MANTISSA_BITS-1;
// Maximum volume that can be multiplied by a ratio mantissa
uint constant MAX_SAFE_VOLUME = (1<<(256-MANTISSA_BITS))-1;
// Without optimizer enabled it fails above 79. With optimizer and 200 runs it fails above 80. Set default a bit lower to be safe.
uint constant INITIAL_MAX_RECURSION_DEPTH = 75;
uint constant INITIAL_MAX_GASREQ_FOR_FAILING_OFFERS_MULTIPLIER = 3;

// Price math limits the allowed ticks to a subset of the full range
int constant MIN_TICK_TREE_INDEX_ALLOWED = MIN_LOG_PRICE;
int constant MAX_TICK_TREE_INDEX_ALLOWED = MAX_LOG_PRICE;
