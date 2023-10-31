#!/bin/bash

out_dir="out"
default_json_file="${out_dir}/gas-measurement.json"

function run_gas_measurement() {
  local json_file=$1
  local tmp_file="$1.tmp"
  forge test --mp "$GAS_MATCH_PATH" -vv --silent --json > "${json_file}"
  # Forge is very verbose, so we filter the json to keep only the gas information
  jq '
    to_entries |
    map(
      {fileAndContract: .key} + 
      (
        .value.test_results |
        to_entries |
        map(
          {
            test: .key,
            gas: (.value.decoded_logs[] | select(startswith("Gas used: ")) | sub("Gas used: "; "")) | tonumber,
            description: (.value.decoded_logs[] | select(startswith("Description: ")) | sub("Description: "; ""))
          }
        )
      )[]
    ) |
    flatten' "${json_file}" > "${tmp_file}"
  mv "${tmp_file}" "${json_file}"
}

function compare_gas_measurement_json() {
  local json_file_old=$1
  local json_file_new=$2
  local json_file_diff=$3

  jq -s 'flatten | group_by(.fileAndContract + .test) | map({fileAndContract: .[0].fileAndContract, test: .[0].test, description: .[0].description, gas_before: .[0].gas, gas_after: .[1].gas, gas_delta: (if .[0].gas != null and .[1].gas != null then .[1].gas - .[0].gas else null end)})' \
    <(jq '. | map({fileAndContract: .fileAndContract, test: .test, gas: .gas, description: .description, source: "before"})' "${json_file_old}") \
    <(jq '. | map({fileAndContract: .fileAndContract, test: .test, gas: .gas, description: .description, source: "after"})' "${json_file_new}") \
    > "${json_file_diff}"
}

function generate_csv_from_gas_measurement_json() {
  local json_file=$1
  local csv_file=$2

  jq -r '
    # Add the header row to the CSV
    ["file:class:test", "file:class", "test", "gas", "description"],

    # Transform each object in the JSON array
    (
      map({
        # Create a new field that concatenates "fileAndContract" and "test" with a colon
        fileClassTest: (.fileAndContract + ":" + .test),

        # Copy the other fields as-is
        fileAndContract: .fileAndContract,
        test: .test,
        gas: .gas,
        description: .description
      })

      # Map each transformed object to an array of values
      | map([.fileClassTest, .fileAndContract, .test, .gas, .description])
    )[]

    # Format the array as a CSV row
    | @csv
  ' "${json_file}" > "${csv_file}"
}

function generate_csv_from_diff_json() {
  local json_file=$1
  local csv_file=$2
  jq -r '
    # Add the header row to the CSV
    ["file:class:test", "file:class", "test", "gas before", "gas after", "gas delta", "description"],

    # Transform each object in the JSON array
    (
      map([
        .fileAndContract + ":" + .test,
        .fileAndContract,
        .test,
        .gas_before,
        .gas_after,
        .gas_delta,
        .description
      ])
    )[]

    # Format the array as a CSV row
    | @csv
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

  echo "Running gas measurement..."
  run_gas_measurement "${json_file}"
  echo "Generating CSV report..."
  generate_csv_from_gas_measurement_json "${json_file}" "${csv_file}"

  echo "   Gas measurement results: ${csv_file}"
fi

