// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

uint constant ONES = type(uint).max;
uint constant TOPBIT = 1 << 255;

// MIN_TICK and MAX_TICK should be inside the addressable range defined by the sizes of LEAF, LEVEL0, LEVEL1, LEVEL2
int constant MIN_TICK = -524288;
int constant MAX_TICK = -MIN_TICK - 1;

// sizes must match field sizes in structs.ts where relevant
uint constant TICK_BITS = 24;
uint constant OFFER_BITS = 32;

// only power-of-two sizes are supported for LEAF_SIZE and LEVEL*_SIZE
uint constant LEAF_SIZE_BITS = 2; 
uint constant LEVEL0_SIZE_BITS = 6;
uint constant LEVEL1_SIZE_BITS = 6;
uint constant LEVEL2_SIZE_BITS = 6;

int constant LEAF_SIZE = int(2 ** (LEAF_SIZE_BITS));
int constant LEVEL0_SIZE = int(2 ** (LEVEL0_SIZE_BITS));
int constant LEVEL1_SIZE = int(2 ** (LEVEL1_SIZE_BITS));
int constant LEVEL2_SIZE = int(2 ** (LEVEL2_SIZE_BITS));

uint constant LEAF_SIZE_MASK = ~(ONES << LEAF_SIZE_BITS);
uint constant LEVEL0_SIZE_MASK = ~(ONES << LEVEL0_SIZE_BITS);
uint constant LEVEL1_SIZE_MASK = ~(ONES << LEVEL1_SIZE_BITS);
uint constant LEVEL2_SIZE_MASK = ~(ONES << LEVEL2_SIZE_BITS);

int constant NUM_LEVEL1 = int(LEVEL2_SIZE);
int constant NUM_LEVEL0 = NUM_LEVEL1 * LEVEL1_SIZE;
int constant NUM_LEAFS = NUM_LEVEL0 * LEVEL0_SIZE;
int constant NUM_TICKS = NUM_LEAFS * LEAF_SIZE;

// FIXME: Should these be here or placed somewhere else? Besides being useful in tests, they serve as documentation for the datastructure
int constant MIN_LEAF_INDEX = -NUM_LEAFS / 2;
int constant MAX_LEAF_INDEX = -MIN_LEAF_INDEX - 1;
int constant MIN_LEVEL0_INDEX = -NUM_LEVEL0 / 2;
int constant MAX_LEVEL0_INDEX = -MIN_LEVEL0_INDEX - 1;
int constant MIN_LEVEL1_INDEX = -NUM_LEVEL1 / 2;
int constant MAX_LEVEL1_INDEX = -MIN_LEVEL1_INDEX - 1;
uint constant MAX_LEAF_POSITION = uint(LEAF_SIZE - 1);
uint constant MAX_LEVEL0_POSITION = uint(LEVEL0_SIZE - 1);
uint constant MAX_LEVEL1_POSITION = uint(LEVEL1_SIZE - 1);
uint constant MAX_LEVEL2_POSITION = uint(LEVEL2_SIZE - 1);

uint constant OFFER_MASK = ONES >> (256 - OFFER_BITS);



// +/- 2**20-1 because only 20 bits are examined by the logPrice->price function
int constant MIN_LOG_PRICE = -((1 << 20)-1);
int constant MAX_LOG_PRICE = -MIN_LOG_PRICE;
uint constant MIN_PRICE_MANTISSA = 4735129379934731672174804159539094721182826496;
int constant MIN_PRICE_EXP = 303;
uint constant MAX_PRICE_MANTISSA = 3441571814221581909035848501253497354125574144;
int constant MAX_PRICE_EXP = 0;
uint constant MANTISSA_BITS = 152;
uint constant MANTISSA_BITS_MINUS_ONE = MANTISSA_BITS-1;
// Maximum volume that can be multiplied by a price mantissa
uint constant MAX_SAFE_VOLUME = (1<<(256-MANTISSA_BITS+1))-1;