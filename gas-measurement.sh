#!/bin/bash

out_dir="out"
default_json_file="${out_dir}/gas-measurement.json"

function run_gas_measurement() {
  local json_file=$1
  local tmp_file="$1.tmp"
  forge test --mp "test/core/gas/*" -vv --silent --json > "${json_file}"
  # Forge is very verbose, so we filter the json to keep only the gas information
  jq '
    map_values(
      {
        test: .test_results | keys_unsorted[]?,
        description: .test_results[]? | select(.decoded_logs) | .decoded_logs[] | select(startswith("Description: ")) | sub("Description: "; ""),
        gas: .test_results[]? | select(.decoded_logs) | .decoded_logs[] | select(startswith("Gas used: ")) | sub("Gas used: "; "") | tonumber
      }
    )' "${json_file}" > "${tmp_file}"
  mv "${tmp_file}" "${json_file}"
}

function compare_gas_measurement_json() {
  local json_file_old=$1
  local json_file_new=$2
  local json_file_diff=$3

  jq -s 'flatten | group_by(.key + .value.test) | map({key: .[0].key, value: {test: .[0].value.test, description: .[0].value.description, gas_before: .[0].value.gas, gas_after: .[1].value.gas, gas_delta: (.[1].value.gas - .[0].value.gas)}})' \
    <(jq 'to_entries | map({key: .key, value: .value, source: "before"})' "${json_file_old}") \
    <(jq 'to_entries | map({key: .key, value: .value, source: "after"})' "${json_file_new}") \
    | jq 'map({(.key): .value}) | add' > "${json_file_diff}"
}

function generate_csv_from_gas_measurement_json() {
  local json_file=$1
  local csv_file=$2
  jq -r '# Add header row
    [["file:class:test", "file:class", "test", "gas", "description"]]

    # Union with the rest of the rows
    + (
      # Iterate over each key-value pair in the root object
      to_entries |

      # Create an array for each row
      map(
      [
        (.key + ":" + .value.test),
        .key,
        .value.test,
        .value.gas,
        .value.description
      ])
    )

    # Flatten the array and join array elements with semicolons to create each row
    | .[] | @csv
  ' "${json_file}" > "${csv_file}"
  repeats=`cat out/gas-measurement.csv | cut -d ';' -f5 | grep -v "MISSING-DESCRIPTION" | sort | uniq -d`
  if [ ! -z "$repeats" ]
  then
    echo "Repeated descriptions:"
    echo "$repeats"
    exit 1
  fi
}

function generate_csv_from_diff_json() {
  local json_file=$1
  local csv_file=$2
  jq -r '# Add header row
    [["file:class:test", "file:class", "test", "gas before", "gas after", "gas delta", "description"]]

    # Union with the rest of the rows
    + (
      # Iterate over each key-value pair in the root object
      to_entries |

      # Create an array for each row
      map(
      [
        (.key + ":" + .value.test),
        .key,
        .value.test,
        .value.gas_before,
        .value.gas_after,
        .value.gas_delta,
        .value.description
      ])
    )

    # Flatten the array and join array elements with semicolons to create each row
    | .[] | @csv
  ' "${json_file}" > "${csv_file}"
}

# Check for --diff parameter
if [[ "$1" == "--diff" ]]; then
  # Run measurements on current code
  json_file_new="${out_dir}/gas-measurement-new.json"
  csv_file_new="${out_dir}/gas-measurement-new.csv"
  echo "Running gas measurement on current code..."
  run_gas_measurement "${json_file_new}"
  generate_csv_from_gas_measurement_json "${json_file_new}" "${csv_file_new}"
  echo "   Gas measurement results for current code: ${csv_file_new}"
  echo ""

  # Compare to previous measurements
  json_file_old="${default_json_file}"
  json_file_diff="${out_dir}/gas-measurement-diff.json"
  csv_file_diff="${out_dir}/gas-measurement-diff.csv"
  echo "Comparing gas measurement results with previous code..."
  echo "   Using gas measurement results from previous code: ${json_file_old}"
  compare_gas_measurement_json "${json_file_old}" "${json_file_new}" "${json_file_diff}"
  generate_csv_from_diff_json "${json_file_diff}" "${csv_file_diff}"
  echo "   Gas measurement diff results: ${csv_file_diff}"
else
  json_file="${default_json_file}"
  csv_file="${out_dir}/gas-measurement.csv"

  run_gas_measurement "${json_file}"
  generate_csv_from_gas_measurement_json "${json_file}" "${csv_file}"

  echo "Gas measurement results: ${csv_file}"
fi

