const Math = require("mathjs");
const fs = require("fs");
const path = require("path");

const { parentPort } = require("worker_threads");

const config = {
  number: "BigNumber",
  precision: 64,
};

const M = Math.create(Math.all, config);

const MIN_TICK = -1048575;
const MAX_TICK = 1048575;
const TICK_SPAN = MAX_TICK - MIN_TICK;
const SIGLOG2 = 151;

const priceToFloat = (price) => {
  const l2 = M.floor(M.log2(price));
  let exp = 0;
  if (l2 > SIGLOG2) {
    exp = l2 - SIGLOG2;
    price = M.divide(price, M.pow(M.bignumber(2), M.bignumber(exp)));
  } else if (l2 < SIGLOG2) {
    exp = SIGLOG2 - l2;
    price = M.multiply(price, M.pow(M.bignumber(2), M.bignumber(exp)));
  }
  price = M.floor(price);
  return { sig: price, exp };
};

parentPort.on("message", ({ worker_index, num_workers }) => {
  const FILE = path.join(
    __dirname,
    `ref_ratios_${worker_index + 1}_of_${num_workers}.jsonl`,
  );
  fs.writeFileSync(FILE, "");
  const block_size = Math.floor(TICK_SPAN / num_workers);

  const tick_offset = block_size * worker_index;
  const start_tick = MIN_TICK + tick_offset;
  const end_tick =
    start_tick + 2 * block_size > MAX_TICK
      ? MAX_TICK + 1
      : start_tick + block_size;

  let current_tick = start_tick;
  let num_lines = 0;
  let current_price = M.pow(M.bignumber("1.0001"), M.bignumber(current_tick));

  console.log(
    `Worker ${worker_index}:\n  - Tick range [${start_tick};${end_tick}[:\n  - Writing to file ${FILE}\n  - Starting with price ${current_price}, tick ${current_tick}`,
  );

  while (current_tick < end_tick) {
    const { sig, exp } = priceToFloat(current_price);
    const formatted_sig = M.format(sig, { notation: "fixed" });
    const res = { tick: current_tick, sig: formatted_sig, exp: exp };
    fs.appendFileSync(FILE, JSON.stringify(res) + "\n");

    current_price = M.multiply(current_price, M.bignumber("1.0001"));
    num_lines++;
    current_tick++;
  }
  console.log(worker_index, `wrote ${num_lines} lines`);
  parentPort.postMessage({ is: "done" });

  process.exit(0);
});
