/* # Mangrove Summary
   * Mangrove holds offer lists for `outbound_tkn`,`inbound_tkn` pairs with a given `tickSpacing`.
   * Offers are sorted in a tree (the "tick tree") where each available price point (a `bin`) holds a doubly linked list of offers.
   * Each offer promises `outbound_tkn` and requests `inbound_tkn`.
   * Each offer has an attached `maker` address.
   * When an offer is executed, Mangrove does the following:
     1. Flashloan some `inbound_tkn` to the offer's `maker`.
     2. Call an arbitrary `execute` function on that address.
     3. Transfer back some `outbound_tkn`.
     4. Call back the `maker` so they can update their offers.
    
   **Let the devs know about any error, typo etc, by contacting 	devs@mangrove.exchange**

   More documentation / discussions can be found at https://docs.mangrove.exchange/.


  There is one Mangrove contract that manages all tradeable offer lists. This reduces deployment costs for new offer lists and lets market makers have all their provision for all offer lists in the same place.

   The interaction map between the different actors is as follows:
   <img src="./contactMap.png" width="190%"></img>

   The sequence diagram of a market order is as follows:
   <img src="./sequenceChart.png" width="190%"></img>

   ## Ratio and price

   In the comments, we use the word 'price' to refer to the ratio between the amount promised by an offer and the amount of requests in return. In the code however, we use the generic word `ratio` to avoid confusion with notions of price based on concepts such as 'quote' and 'base' tokens,etc.

   ## `tickSpacing`

   The granularity of available price points in an offer list is controlled by the `tickSpacing` parameter. With a high `tickSpacing`, fewer price points are available, but the gas cost of market orders is lower since a smaller part of the tick tree has to be explored.

   The available prices in an offer list are `1.0001^i` for all `MIN_TICK <= i <= MAX_TICK` such that `i % tickSpacing = 0`.

   ## Tree storage

   Offers are stored in a tree we call a "tick tree". Thanks to this tree structure, offer operations (insert, update, and retract) take constant time (the height of the tree is fixed).


   ### Bins

   <img src="./bin.png" width="80%"></img>

   Below the bottom of the tree are _bins_. A bin is a doubly linked list of offers. All offers in a bin have the same tick. During a market order, offers in a bin are executed in order, from the first to the last. Inserted offers are always appended at the end of a bin. 

   Bins are laid in sequence. In the context of an offer list, each bin has an associated tick (and a tick determines a price). If a bin has tick `t`, the following bin has tick `t+tickSpacing`.

   Bins are identified by their index in the bin sequence, from the first (`MIN_BIN`) to the last (`MAX_BIN`). The number of available bins is larger than the number of available ticks, so some bins will never be used.

   ### Tree structure

   The structure of the tick tree is as follows:
   <img src="./tick_tree_structure.png" width="190%"></img>

   At the bottom of the tree, leaves contain information about 4 bins: their first and last offer. Offer ids use 32 bits, so leaves use 256 bits.

   When a market order runs, execution starts with the first offer of the lowest-numbered nonempty bin and continues from there.

  Once all the offers in the smallest bin have been executed, the next non-empty bin is found. If the leaf of the current bin now only has empty bins, the tree must be searched for the next non-empty bin, starting at the node above the leaf:
   
   A non-leaf node contains a bit field with information about all its children: if the *i*th bit of the node is set, its *i*th child has at least one non-empty bin. Otherwise, its *i*th child only has empty bins.

   To find the next non-empty bin, it may be necessary to keep going up the tree until the root is reached. At each level above, the bit field rule applies similarly: the *i*th bit of a node is set iff its *i*th child has at least one set bit.

   Once a node with a set bit is found, its rightmost nonempty child is examined, and so on until the next nonempty bin is reached, and the first offer of that bin gets executed.

   ## Caching

   At any time, if there is at least one offer in the offer list, the best offer is the first offer of the bin containing the cheapest offers; and that bin is the best bin. Its parent is the best `level3`, whose parent is the best `level2`, and whose parent is the best `level1` (whose parent is the `root`). 


   The `root`, the best `level1`, the  best `level2`, and the best `level3` are always stored in `local`. The position of the best bin in the best leaf is also stored in `local`. 


   This data is useful for two things:
   - Read and modify the tree branch of the best offer without additional storage reads and writes (except for modifying the best leaf).
   - Know the price of the best offer without an additional storage read (it can be computed using the set bit positions in each level, the position of the best bin in the best leaf, and the value of `tickSpacing`).

   The structure of the local config is as follows:
   <img src="./local_config.png" width="140%"></img>

  This caching means that as the price oscillates within a more restricted range, fewer additional storage read/writes have to be performed (as most of the information is available in `local`) when there is a market order or an offer insertion/update.


  ## Some numbers
  Here are some useful numbers, for reference:
   <img src="./numbers.png" width="70%"></img>

 */
//+clear+

/* # Preprocessing

The current file (`structs.js`) is used in `Structs.pre.sol` (not shown here) to generate the libraries in `Struct.pre.sol`. Here is an example of js struct specification and of a generated library:
```
struct_defs = {
  universe: [
    {name: "serialnumber", bits: 16, type: "uint"},
    {name: "hospitable",bits: 8, type:"bool"}
  ]
}
```

The generated file will store all data in a single EVM stack slot (seen as an abstract type `<TypeName>` by Solidity); here is a simplified version:

```
struct UniverseUnpacked {
  uint serialnumber;
  bool hospitable;
}

library Library {
  // use Solidity 0.8* custom types
  type Universe is uint;

  // test word equality
  function eq(Universe ,Universe) returns (bool);

  // word <-> struct conversion
  function to_struct(Universe) returns (UniverseUnpacked memory);
  function t_of_struct(UniverseUnpacked memory) returns (Universe);

  // arguments <-> word conversion
  function unpack(Universe) returns (uint serialnumber, bool hospitable);
  function pack(uint serialnumber, bool hospitable) returns(Universe);

  // read and write first property
  function serialnumber(Universe) returns (uint);
  function serialnumber(Universe,uint) returns (Universe);

  // read and write second property
  function hospitable(Universe) returns (bool);
  function hospitable(Universe,bool) returns (Universe);
}
```
Then, in Solidity code, one can write:
```
Universe uni = UniverseLib.pack(32,false);
uint num = uni.serialnumber();
uni.hospitable(true);
```
*/

/* # Data structures */

/* Struct-like data structures are stored in storage and memory as 256 bits words. We avoid using structs due to significant gas savings gained by extracting data from words only when needed. This is exacerbated by the fact that Mangrove uses one recursive call per executed offer; it is much cheaper to accumulate used stack space than memory space throughout the recursive calls. 

The generation is defined in `lib/preproc.ts`. */

/* Struct fields that are common to multiple structs are factored here. Multiple field names refer to offer identifiers, so the `id_field` is a function that takes a name as argument and returns a field with the right size & type. */

const fields = {
  gives: { name: "gives", bits: 127, type: "uint" },
  gasprice: { name: "gasprice", bits: 26, type: "uint" },
  gasreq: { name: "gasreq", bits: 24, type: "uint" },
  kilo_offer_gasbase: { name: "kilo_offer_gasbase", bits: 9, type: "uint" },
};

const id_field = (name: string) => {
  return { name, bits: 32, type: "uint" };
};

/* # Structs */

/* ## `Offer` */
//+clear+
/* `Offer`s hold doubly linked list pointers to their prev and next offers, as well as price and volume information. 256 bits wide, so one storage read is enough. They have the following fields: */
//+clear+
const struct_defs = {
  offer: {
    fields: [
      /* * `prev` points to immediately better offer at the same price point, if any, and 0 if there is none. _32 bits wide_. */
      id_field("prev"),
      /* * `next` points to immediately worse offer at the same price point, if any, and 0 if there is none. _32 bits wide_. */
      id_field("next"),
      /* * `tick` is the log base 1.0001 of the price of the offer. _21 bits wide_. */
      {name:"tick",bits:21,type:"Tick",underlyingType: "int"},
      /* * `gives` is the amount of `outbound_tkn` the offer will give if successfully executed. _127 bits wide_. */
      fields.gives,
    ],
    additionalDefinitions: `import {Bin} from "@mgv/lib/core/TickTreeLib.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {OfferExtra,OfferUnpackedExtra} from "@mgv/lib/core/OfferExtra.sol";

using OfferExtra for Offer global;
using OfferUnpackedExtra for OfferUnpacked global;
`
  },

  /* ## `OfferDetail` */
  //+clear+
  /* `OfferDetail`s hold the maker's address and provision/penalty-related information.
They have the following fields: */
  offerDetail: {
    fields: [
      /* * `maker` is the address that created the offer. It will be called when the offer is executed and later during the posthook phase. */
      { name: "maker", bits: 160, type: "address" },
      /* * <a id="structs.js/gasreq"></a>`gasreq` gas will be provided to `execute`. _24 bits wide_, i.e. around 16M gas. Note that if more room was needed, we could bring it down to 16 bits and have it represent 1k gas increments.

    */
      fields.gasreq,
      /*
        * <a id="structs.js/gasbase"></a>  `kilo_offer_gasbase` represents the gas overhead used by processing the offer inside Mangrove + the overhead of initiating an entire order, in 1k gas increments.

      The gas considered 'used' by an offer is the sum of
      * gas consumed during the call to the offer
      * `kilo_offer_gasbase * 1e3`
      
    (There is an inefficiency here. The overhead could be split into an "offer-local overhead" and a "general overhead". That general overhead gas penalty could be spread between all offers executed during an order, or all failing offers. It would still be possible for a cleaner to execute a failing offer alone and make them pay the entire general gas overhead. For the sake of simplicity we keep only one "offer overhead" value.)

    If an offer fails, `gasprice` Mwei is taken from the
    provision per unit of gas used. `gasprice` should approximate the average gas
    price at offer creation time.

    `kilo_offer_gasbase` is the actual field name, is _9 bits wide_, and represents 1k gas increments. The accessor `offer_gasbase` returns `kilo_offer_gasbase * 1e3`.

    `kilo_offer_gasbase` is also the name of a local Mangrove
    parameter. When an offer is created, its current value is copied from Mangrove local configuration. The maker does not choose it.

    So, when an offer is created, the maker is asked to provision the
    following amount of wei:
    ```
    (gasreq + offer_gasbase) * gasprice * 1e6
    ```

      where `offer_gasbase` and `gasprice` are Mangrove's current configuration values (or a higher value for `gasprice` if specified by the maker).


      When an offer fails, the following amount is given to the taker as compensation:
    ```
    (gasused + offer_gasbase) * gasprice * 1e6
    ```

    where `offer_gasbase` and `gasprice` are Mangrove's current configuration values.  The rest is given back to the maker.

      */
      fields.kilo_offer_gasbase,
      /* * `gasprice` is in Mwei/gas and _26 bits wide_, which accommodates 0.001 to ~67k gwei / gas.  `gasprice` is also the name of a global Mangrove parameter. When an offer is created, the offer's `gasprice` is set to the max of the user-specified `gasprice` and Mangrove's global `gasprice`. */
      fields.gasprice,
    ],
    additionalDefinitions: (struct) => `import {OfferDetailExtra,OfferDetailUnpackedExtra} from "@mgv/lib/core/OfferDetailExtra.sol";
using OfferDetailExtra for OfferDetail global;
using OfferDetailUnpackedExtra for OfferDetailUnpacked global;
`,
  },

  /* ## Global Configuration
   Configuration information for an offer list is split between a `global` struct (common to all offer lists) and a `local` struct specific to each offer list. Global configuration fields are:
   */
  global: {
    fields: [
      /* * The `monitor` can provide real-time values for `gasprice` and `density` to Mangrove. It can also receive liquidity event notifications. */
      { name: "monitor", bits: 160, type: "address" },
      /* * If `useOracle` is true, Mangrove will use the monitor address as an oracle for `gasprice` and `density`, for every outbound_tkn/inbound_tkn pair, except if the oracle-provided values do not pass a check performed by Mangrove. In that case the oracle values are ignored. */
      { name: "useOracle", bits: 1, type: "bool" },
      /* * If `notify` is true, Mangrove will notify the monitor address after every offer execution. */
      { name: "notify", bits: 1, type: "bool" },
      /* * The `gasprice` is the amount of penalty paid by failed offers, in Mwei per gas used. `gasprice` should approximate the average gas price and will be subject to regular updates. */
      fields.gasprice,
      /* * `gasmax` specifies how much gas an offer may ask for at execution time. An offer which asks for more gas than the block limit would live forever on the book. Nobody could take it or remove it, except its creator (who could cancel it). In practice, we will set this parameter to a reasonable limit taking into account both practical transaction sizes and the complexity of maker contracts.
      */
      { name: "gasmax", bits: 24, type: "uint" },
      /* * `dead`: if necessary, Mangrove can be entirely deactivated by governance (offers can still be retracted and provisions can still be withdrawn). Once killed, Mangrove must be redeployed; It cannot be resurrected. */
      { name: "dead", bits: 1, type: "bool" },
      /* * `maxRecursionDepth` is the maximum number of times a market order can recursively execute offers. This is a protection against stack overflows. */
      { name: "maxRecursionDepth", bits: 8, type: "uint" },      
      /* * `maxGasreqForFailingOffers` is the maximum gasreq failing offers can consume in total. This is used in a protection against failing offers collectively consuming the block gas limit in a market order. Setting it too high would make it possible for successive failing offers to consume up to that limit then trigger a revert (thus the failing offer would not be removed). During a market order, Mangrove keeps a running sum of the `gasreq` of the failing offers it has executed and stops the market order when that sum exceeds `maxGasreqForFailingOffers`. */
      { name: "maxGasreqForFailingOffers", bits: 32, type: "uint" },      
    ],
  },

  /* ## Local configuration */
  local: {
    fields: [
      /* * An offer list is not `active` by default, but may be activated/deactivated by governance. */
      { name: "active", bits: 1, type: "bool" },
      /* * `fee`, in basis points, of `outbound_tkn` given to the taker. This fee is sent to Mangrove. Fee is capped to ~2.5%. */
      { name: "fee", bits: 8, type: "uint" },
      /* * `density` is similar to a 'dust' parameter. We prevent spamming of low-volume offers by asking for a minimum 'density' in `outbound_tkn` per gas requested. For instance, if `density` is worth 10, `offer_gasbase == 5000`, an offer with `gasreq == 30000` must promise at least _10 × (30000 + 5000) = 350000_ `outbound_tkn`. _9 bits wide_.

      We store the density as a float with 2 bits for the mantissa, 7 for the exponent, and an exponent bias of 32, so that density ranges from $2^{-32}$ to $1.75 \times 2^{95}$. For more information, see `DensityLib`.
      
      */
      { name: "density", bits: 9, type: "Density", underlyingType: "uint"},
      /* To save gas, Mangrove caches the entire tick tree branch of the bin that contains the best offer in each offer list's `local` parameter. Taken together, `binPosInLeaf`, `level3`, `level2`, `level1`, and `root` provide the following info:
      - What the current bin is (see `BinLib.bestBinFromLocal`)
      - When a leaf is emptied and the next offer must be fetched, the information in the fields `level3`, `level2`, `level1` and `root` avoid multiple storage reads
      */
      { name: "binPosInLeaf", bits: 2, type: "uint" },
      { name: "level3", bits: 64, type: "Field", underlyingType: "uint" },
      { name: "level2", bits: 64, type: "Field", underlyingType: "uint" },
      { name: "level1", bits: 64, type: "Field", underlyingType: "uint" },
      { name: "root", bits: 2, type: "Field", underlyingType: "uint" },
      /* * `offer_gasbase` represents the gas overhead used by processing the offer inside Mangrove + the overhead of initiating an entire order. Mangrove considers that a failed offer has used at least `offer_gasbase` gas. The actual field name is `kilo_offer_gasbase` and the accessor `offer_gasbase` returns `kilo_offer_gasbase*1e3`. Local to an offer list, because the costs of calling `outbound_tkn` and `inbound_tkn`'s `transferFrom` are part of `offer_gasbase`. Should only be updated when ERC20 contracts change or when opcode prices change. */
      fields.kilo_offer_gasbase,
      /* * If `lock` is true, orders may not be added nor executed, nor the offer list read by external contracts.

        Reentrancy during offer execution is not considered safe:
      * during execution, an offer could consume other offers further up in the list, effectively front-running the taker currently executing the offer.
      * it could also cancel other offers, creating a discrepancy between the advertised and actual market price at no cost to the maker.
      * a maker could potentially distinguish between a clean and a market order based on the current state of the offer list

  Note: An optimization in the `marketOrder` function relies on reentrancy being forbidden.
      */
      { name: "lock", bits: 1, type: "bool" },
      /* * `last` is a counter for offer ids, incremented every time a new offer is created. It can't go above $2^{32}-1$. */
      id_field("last"),
    ],
    /* Import additional libraries for `Local` and `LocalExtra`. */
    additionalDefinitions: (struct) => `import {Density, DensityLib} from "@mgv/lib/core/DensityLib.sol";
import {Bin,TickTreeLib,Field} from "@mgv/lib/core/TickTreeLib.sol";
/* Globally enable global.method(...) */
import {LocalExtra,LocalUnpackedExtra} from "@mgv/lib/core/LocalExtra.sol";
using LocalExtra for Local global;
using LocalUnpackedExtra for LocalUnpacked global;
`,
  }
};

export default struct_defs;
