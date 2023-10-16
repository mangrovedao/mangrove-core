const { Worker } = require("worker_threads");
const path = require("path");

const WORKER = path.join(__dirname, "generate_ratios_worker.js");

// NUM_WORKERS must match the number of TickRatioConversion* solidity contracts
const NUM_WORKERS = 10;

let num_done = 0;
for (let i = 0; i < NUM_WORKERS; i++) {
  const worker = new Worker(WORKER);
  worker.on("message", async (event) => {
    if (event.is == "done") {
      console.log(`Worker ${i} is done`);
      num_done++;
      if (num_done == NUM_WORKERS) {
        console.log("All workers done.");
      }
    } else {
      console.log(`Received from ${i}:`);
      console.log(event);
    }
  });

  worker.on("error", (err) => {
    console.log("Worker encountered an error:", err);
  });

  worker.postMessage({ num_workers: NUM_WORKERS, worker_index: i });
}
