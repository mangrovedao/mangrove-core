// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

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



// +/- 2**20-1 because only 20 bits are examined by the tick->ratio function
int constant MIN_TICK = -1048575;
int constant MAX_TICK = 1048575;
uint constant MIN_RATIO_MANTISSA = 4735129379934731672174804159539094721182826496;
int constant MIN_RATIO_EXP = 303;
uint constant MAX_RATIO_MANTISSA = 3441571814221581909035848501253497354125574144;
int constant MAX_RATIO_EXP = 0;
uint constant MANTISSA_BITS = 152;
uint constant MANTISSA_BITS_MINUS_ONE = 151;
// Maximum volume that can be multiplied by a ratio mantissa
uint constant MAX_SAFE_VOLUME = 20282409603651670423947251286015;
// Without optimizer enabled it fails above 79. With optimizer and 200 runs it fails above 80. Set default a bit lower to be safe.
uint constant INITIAL_MAX_RECURSION_DEPTH = 75;
uint constant INITIAL_MAX_GASREQ_FOR_FAILING_OFFERS_MULTIPLIER = 3;

// Price math limits the allowed ticks to a subset of the full range
int constant MIN_BIN_ALLOWED = -1048575;
int constant MAX_BIN_ALLOWED = 1048575;
