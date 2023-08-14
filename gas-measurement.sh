#!/bin/sh

forge test --mp "test/core/gas/*" -vv --silent --json > out/gas-measurement.json

{
  echo "file:class:test;file:class;test;gas;description"
  jq -r 'to_entries[] |
    .key as $file |
    .value.test_results |
    to_entries[] |
    select(.value.decoded_logs) |
    .key as $test |
    {
        gasLogs: (.value.decoded_logs | map(select(startswith("Gas used: "))) | if length == 0 then [null] else . end),
        descLogs: (.value.decoded_logs | map(select(startswith("Description: "))) | if length == 0 then [null] else . end)
    } |
    "\($file):\($test);\($file);\($test);\(.gasLogs[0] // "MISSING-GAS-OR-SKIPPED" | sub("Gas used: "; ""));\(.descLogs[0] // "MISSING-DESCRIPTION" | sub("Description: "; ""))"' out/gas-measurement.json
 } > out/gas-measurement.csv

repeats=`cat out/gas-measurement.csv | cut -d ';' -f5 | grep -v "MISSING-DESCRIPTION" | sort | uniq -d`

echo "Gas measurement results: out/gas-measurement.csv"

if [ ! -z "$repeats" ]
then
  echo "Repeated descriptions:"
  echo "$repeats"
  exit 1
fi