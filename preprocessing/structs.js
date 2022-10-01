/* # Mangrove Summary
   * The Mangrove holds order books for `outbound_tkn`,`inbound_tkn` pairs.
   * Offers are sorted in a doubly linked list.
   * Each offer promises `outbound_tkn` and requests `inbound_tkn`.
   * Each offer has an attached `maker` address.
   * In the normal operation mode (called Mangrove for Maker Mangrove), when an offer is executed, we:
     1. Flashloan some `inbound_tkn` to the offer's `maker`.
     2. Call an arbitrary `execute` function on that address.
     3. Transfer back some `outbound_tkn`.
     4. Call back the `maker` so they can update their offers.
   * There is an inverted operation mode (called InvertedMangrove for Taker Mangrove), the flashloan is reversed (from the maker to the taker).
   * Offer are just promises. They can fail.
   * If an offer fails to transfer the right amount back, the loan is reverted.
   * A penalty mechanism incentivizes keepers to keep the book clean of failing offers.
   * A penalty provision must be posted with each offer.
   * If the offer succeeds, the provision returns to the maker.
   * If the offer fails, the provision is given to the taker as penalty.
   * The penalty should overcompensate for the taker's lost gas.
    
   **Let the devs know about any error, typo etc, by contacting 	devs@mangrove.exchange**
 */
//+clear+

/* # Preprocessing

The current file (`structs.js`) is used in `MgvStructs.pre.sol` (not shown here) to generate the libraries in `MgvType.pre.sol`. Here is an example of js struct specification and of a generated library:
```
structs = {
  universe: [
    {name: "serialnumber", bits: 16, type: "uint"},
    {name: "hospitable",bits: 8, type:"bool"}
  ]
}
```

The generated file will store all data in a single EVM stack slot (seen as an abstract type `<TypeName>Packed` by Solidity); here is a simplified version:

```
struct UniverseUnpacked {
  uint serialnumber;
  bool hospitable;
}

library Library {
  // use Solidity 0.8* custom types
  type UniversePacked is uint;

  // test word equality
  function eq(UniversePacked,UniversePacked) returns (bool);

  // word <-> struct conversion
  function to_struct(UniversePacked) returns (UniverseUnpacked memory);
  function t_of_struct(UniverseUnpacked memory) returns (UniversePacked);

  // arguments <-> word conversion
  function unpack(UniversePacked) returns (uint serialnumber, bool hospitable);
  function pack(uint serialnumber, bool hospitable) returns(UniversePacked);

  // read and write first property
  function serialnumber(UniversePacked) returns (uint);
  function serialnumber(UniversePacked,uint) returns (UniversePacked);

  // read and write second property
  function hospitable(UniversePacked) returns (bool);
  function hospitable(UniversePacked,bool) returns (UniversePacked);
}
```
Then, in Solidity code, one can write:
```
using Universe for Universe.UniversePacked
UniversePacked uni = Universe.pack(32,false);
uint num = uni.serialnumber();
uni.hospitable(true);
```
*/

/* # Data stuctures */

/* Struct-like data structures are stored in storage and memory as 256 bits words. We avoid using structs due to significant gas savings gained by extracting data from words only when needed. To make development easier, we use the preprocessor `solpp` and generate getters and setters for each struct we declare. The generation is defined in `lib/preproc.js`. */

const preproc = require("./lib/preproc.js");

/* Struct fields that are common to multiple structs are factored here. Multiple field names refer to offer identifiers, so the `id` field is a function that takes a name as argument. */

const fields = {
  wants: { name: "wants", bits: 96, type: "uint" },
  gives: { name: "gives", bits: 96, type: "uint" },
  gasprice: { name: "gasprice", bits: 16, type: "uint" },
  gasreq: { name: "gasreq", bits: 24, type: "uint" },
  offer_gasbase: { name: "offer_gasbase", bits: 24, type: "uint" },
};

const id_field = (name) => {
  return { name, bits: 32, type: "uint" };
};

/* # Structs */

/* ## `Offer` */
//+clear+
/* `Offer`s hold the doubly-linked list pointers as well as price and volume information. 256 bits wide, so one storage read is enough. They have the following fields: */
//+clear+
const structs = {
  offer: [
    /* * `prev` points to immediately better offer. The best offer's `prev` is 0. _32 bits wide_. */

    id_field("prev"),
    /* * `next` points to the immediately worse offer. The worst offer's `next` is 0. _32 bits wide_. */
    id_field("next"),
    /* * `wants` is the amount of `inbound_tkn` the offer wants in exchange for `gives`.
     _96 bits wide_, so assuming the usual 18 decimals, amounts can only go up to
  10 billions. */
    fields.wants,
    /* * `gives` is the amount of `outbound_tkn` the offer will give if successfully executed.
    _96 bits wide_, so assuming the usual 18 decimals, amounts can only go up to
    10 billions. */
    fields.gives,
  ],

  /* ## `OfferDetail` */
  //+clear+
  /* `OfferDetail`s hold the maker's address and provision/penalty-related information.
They have the following fields: */
  offerDetail: [
    /* * `maker` is the address that created the offer. It will be called when the offer is executed, and later during the posthook phase. */
    { name: "maker", bits: 160, type: "address" },
    /* * <a id="structs.js/gasreq"></a>`gasreq` gas will be provided to `execute`. _24 bits wide_, i.e. around 16M gas. Note that if more room was needed, we could bring it down to 16 bits and have it represent 1k gas increments.

  */
    fields.gasreq,
    /*
       * <a id="structs.js/gasbase"></a>  `offer_gasbase` represents the gas overhead used by processing the offer inside the Mangrove + the overhead of initiating an entire order.

    The gas considered 'used' by an offer is the sum of
    * gas consumed during the call to the offer
    * `offer_gasbase`
     
   (There is an inefficiency here. The overhead could be split into an "offer-local overhead" and a "general overhead". That general overhead gas penalty could be spread between all offers executed during an order, or all failing offers. It would still be possible for a cleaner to execute a failing offer alone and make them pay the entire general gas overhead. For the sake of simplicity we keep only one "offer overhead" value.)

   If an offer fails, `gasprice` wei is taken from the
   provision per unit of gas used. `gasprice` should approximate the average gas
   price at offer creation time.

   `offer_gasbase` is _24 bits wide_ -- note that if more room was needed, we could bring it down to 8 bits and have it represent 1k gas increments.

   `offer_gasbase` is also the name of a local Mangrove
   parameters. When an offer is created, their current value is copied from the Mangrove local configuration.  The maker does not choose it.

   So, when an offer is created, the maker is asked to provision the
   following amount of wei:
   ```
   (gasreq + offer_gasbase) * gasprice
   ```

    where `offer_gasbase` and `gasprice` are the Mangrove's current configuration values (or a higher value for `gasprice` if specified by the maker).


    When an offer fails, the following amount is given to the taker as compensation:
   ```
   (gasused + offer_gasbase) * gasprice
   ```

   where `offer_gasbase` and `gasprice` are the Mangrove's current configuration values.  The rest is given back to the maker.

    */
    fields.offer_gasbase,
    /* * `gasprice` is in gwei/gas and _16 bits wide_, which accomodates 1 to ~65k gwei / gas.  `gasprice` is also the name of a global Mangrove parameter. When an offer is created, the offer's `gasprice` is set to the max of the user-specified `gasprice` and the Mangrove's global `gasprice`. */
    fields.gasprice,
  ],

  /* ## Configuration and state
   Configuration information for a `outbound_tkn`,`inbound_tkn` pair is split between a `global` struct (common to all pairs) and a `local` struct specific to each pair. Configuration fields are:
*/
  /* ### Global Configuration */
  global: [
    /* * The `monitor` can provide realtime values for `gasprice` and `density` to the dex, and receive liquidity events notifications. */
    { name: "monitor", bits: 160, type: "address" },
    /* * If `useOracle` is true, the dex will use the monitor address as an oracle for `gasprice` and `density`, for every outbound_tkn/inbound_tkn pair. */
    { name: "useOracle", bits: 8, type: "bool" },
    /* * If `notify` is true, the dex will notify the monitor address after every offer execution. */
    { name: "notify", bits: 8, type: "bool" },
    /* * The `gasprice` is the amount of penalty paid by failed offers, in gwei per gas used. `gasprice` should approximate the average gas price and will be subject to regular updates. */
    fields.gasprice,
    /* * `gasmax` specifies how much gas an offer may ask for at execution time. An offer which asks for more gas than the block limit would live forever on the book. Nobody could take it or remove it, except its creator (who could cancel it). In practice, we will set this parameter to a reasonable limit taking into account both practical transaction sizes and the complexity of maker contracts.
     */
    { name: "gasmax", bits: 24, type: "uint" },
    /* * `dead` dexes cannot be resurrected. */
    { name: "dead", bits: 8, type: "bool" },
  ],

  /* ### Local configuration */
  local: [
    /* * A `outbound_tkn`,`inbound_tkn` pair is in`active` by default, but may be activated/deactivated by governance. */
    { name: "active", bits: 8, type: "bool" },
    /* * `fee`, in basis points, of `outbound_tkn` given to the taker. This fee is sent to the Mangrove. Fee is capped to 5%. */
    { name: "fee", bits: 16, type: "uint" },
    /* * `density` is similar to a 'dust' parameter. We prevent spamming of low-volume offers by asking for a minimum 'density' in `outbound_tkn` per gas requested. For instance, if `density == 10`, `offer_gasbase == 5000`, an offer with `gasreq == 30000` must promise at least _10 × (30000 + 5000) = 350000_ `outbound_tkn`. _112 bits wide_. */
    { name: "density", bits: 112, type: "uint" },
    /* * `offer_gasbase` is an overapproximation of the gas overhead associated with processing one offer. The Mangrove considers that a failed offer has used at least `offer_gasbase` gas. Local to a pair because the costs of calling `outbound_tkn` and `inbound_tkn`'s `transferFrom` are part of `offer_gasbase`. Should only be updated when ERC20 contracts change or when opcode prices change. */
    fields.offer_gasbase,
    /* * If `lock` is true, orders may not be added nor executed.

       Reentrancy during offer execution is not considered safe:
     * during execution, an offer could consume other offers further up in the book, effectively frontrunning the taker currently executing the offer.
     * it could also cancel other offers, creating a discrepancy between the advertised and actual market price at no cost to the maker.
     * an offer insertion consumes an unbounded amount of gas (because it has to be correctly placed in the book).

Note: An optimization in the `marketOrder` function relies on reentrancy being forbidden.
     */
    { name: "lock", bits: 8, type: "bool" },
    /* * `best` holds the current best offer id. Has size of an id field. *Danger*: reading best inside a lock may give you a stale value. */
    id_field("best"),
    /* * `last` is a counter for offer ids, incremented every time a new offer is created. It can't go above $2^{32}-1$. */
    id_field("last"),
  ],
};

module.exports = preproc.structs_with_macros(structs);
