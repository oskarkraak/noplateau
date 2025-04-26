#!/bin/bash

SECONDS=0

# constants
time_budget=31
estimated_pynguin_overhead_time=30

target_module=$3
seed=$4
OPENAI_API_KEY=$5
target_dir=$6
output_dir=$7

test_dir="$output_dir/noplateautests/"
base_dir=$(pwd)


# Convert the module name (e.g., flutils.pathutils) to a relative path (e.g., flutils/pathutils)
module_relative_path=$(echo "$target_module" | tr . /)
# Construct the full target file path by joining the target directory and the relative path, adding the .py extension
original_target_file_path="$target_dir/$module_relative_path.py"

# Extract the filename from the original path
filename=$(basename "$original_target_file_path")

# Optional: Verify if the file exists
if [ -f "$original_target_file_path" ]; then
  echo "Original target file path: $original_target_file_path"
  echo "Target filename: $filename"
else
  echo "Warning: Calculated file path does not appear to exist: $original_target_file_path"
  # You might want to exit or handle this case differently if the file is expected to exist
  # exit 1
fi


export PYTHONPATH="$target_dir:$PYTHONPATH"
echo "PYTHONPATH=$PYTHONPATH"


echo "> Running NoPlateau:"
#echo ">>> $base_dir"
echo ">>> Time budget: $time_budget"
echo ">>> Test dir: $test_dir"
echo ">>> Target module: $target_module"
echo ">>> Seed: $seed"
# echo ">>> API key: $OPENAI_API_KEY" # Avoid logging API keys
echo ">>> Target dir: $target_dir"
echo ">>> Output dir: $output_dir"

export OPENAI_API_KEY="$OPENAI_API_KEY"

mkdir -p "$test_dir"


### noplateau loop ###

TIME_USED=0

function run_pynguin {
    echo ">>> Pynguin"
    time_before=$SECONDS

    # Assuming merge_tests.sh and remove_failing_tests.sh handle paths correctly
    bash /pynguin/merge_tests.sh $test_dir
    export PYNGUIN_DANGER_AWARE=true
    TIME_LEFT=$((time_budget - TIME_USED))
    max_search_time=$((TIME_LEFT - estimated_pynguin_overhead_time))
    if [ $max_search_time -le 0 ]; then
        echo "Not enough time budget left for Pynguin search."
        return 1 # Use return code to indicate failure/skip
    fi

    echo "Running pynguin with max search time: $max_search_time seconds"
    pynguin \
        --project-path "$target_dir" \
        --module-name "$target_module" \
        --output-path "$test_dir" \
        --initial-population-seeding True \
        --initial_population_data "$test_dir" \
        --seed "$seed" \
        --coverage-metrics BRANCH \
        --maximum_search_time "$max_search_time" \
        --maximum_coverage_plateau 30 \
        --verbose

    local pynguin_exit_code=$? # Capture exit code
    if [ $pynguin_exit_code -ne 0 ]; then
        echo "Pynguin failed with exit code $pynguin_exit_code"
        # Decide how to handle Pynguin failure (e.g., exit, continue, retry?)
        # For now, let's just report and continue
    else
         echo "Pynguin completed successfully."
    fi

    time_after=$SECONDS
    TIME_USED=$((TIME_USED + time_after - time_before))
    return $pynguin_exit_code # Return Pynguin's exit code
}

function run_coverup {
    echo ">>> Coverup"
    time_before=$SECONDS

    echo "PYTHONPATH: $PYTHONPATH" # TODO debug

    # Check if the target file exists in the coverup dir before running
    if [ ! -f "$original_target_file_path" ]; then
        echo "ERROR: Target file '$original_target_file_path' not found in coverup directory before running CoverUp."
        return 1 # Indicate failure
    fi

    # TODO: make coverup quit if time budget is used up (take time as input argument)

    echo "Running CoverUp command:"
    echo "python3.10 -m coverup \"$original_target_file_path\" --package-dir \"$target_dir\" --tests-dir \"$test_dir\" --model gpt-4o-mini --no-isolate-tests --branch-coverage --no-add-to-pythonpath ......"

    python3.10 -m coverup \
        "$original_target_file_path" \
        --package-dir "$target_dir" \
        --tests-dir "$test_dir" \
        --model gpt-4o-mini \
        --no-isolate-tests \
        --no-add-to-pythonpath \
        -d

    local coverup_exit_code=$?
    if [ $coverup_exit_code -ne 0 ]; then
        echo "CoverUp failed with exit code $coverup_exit_code"
    else
        echo "CoverUp completed successfully."
    fi

    #cat coverup-log

    time_after=$SECONDS
    TIME_USED=$((TIME_USED + time_after - time_before))
    return $coverup_exit_code # Return CoverUp's exit code
}


function make_diverse_tests {
    echo ">>> Making more diverse tests (Mistral - currently placeholder)"
    time_before=$SECONDS

    # --- Placeholder for diversity generation logic ---
    # bash /pynguin/merge_tests.sh $test_dir
    # mistral_script=$test_dir/llm_tests.py
    # python3.10 /pynguin/mistral.py \
    #     --input "$original_target_file_path" \ # Use the correct path
    #     --target_module_name "$target_module" \
    #     --tests "${test_dir}/test_merged_${filename%.py}.py" \ # Adjust merged test name if needed
    #     --output $mistral_script \
    #     --diversity True
    # bash /pynguin/remove_failing_tests.sh $mistral_script
    #
    # echo ">>> Trimming markdown syntax from the generated file..."
    # sed -i '1{/^\s*```python\s*$/d}; ${/^\s*```\s*$/d}' $mistral_script
    # sed -i '/your_module/d' $mistral_script # Check if this is still needed
    echo "Diversity generation step needs to be implemented/reviewed."
    # --- End Placeholder ---

    time_after=$SECONDS
    # Estimate time used by this step if implemented
    # TIME_USED=$((TIME_USED + time_after - time_before))
    TIME_USED=$((TIME_USED + 15)) # Using the original estimated time for now
}

function measure_coverage {
    echo "▶️ Running tests with coverage..."
    
    echo "PYTHONPATH: $PYTHONPATH"
    local output
    output=$(python3.10 -m pytest --cov-branch --cov="$target_module" "$test_dir" --cov-report=term 2>&1)
    local pytest_exit_code=$?
    echo "$output"

    if [ $pytest_exit_code -ne 0 ] && [ $pytest_exit_code -ne 5 ]; then # 5 means no tests collected
        echo "WARNING: Pytest failed with exit code $pytest_exit_code during coverage measurement."
    fi

    # Extract total line and coverage percent using a more robust grep/awk
    # Look for the line starting with TOTAL, then extract the last field (coverage %)
    local total_line
    total_line=$(echo "$output" | grep -E '^TOTAL\s+')

    local coverage="-1" # Default to -1 if not found
    if [[ -n "$total_line" ]]; then
        coverage=$(echo "$total_line" | awk '{print $NF}' | tr -d '%')
        # Validate if coverage is a number
        if ! [[ "$coverage" =~ ^[0-9]+$ ]]; then
            echo "WARNING: Could not parse coverage percentage from pytest output."
            coverage="0"
        fi
    else
        echo "WARNING: Could not find TOTAL coverage line in pytest output."
    fi

    echo "📊 Extracted total coverage: ${coverage}%"
    echo "$coverage"
}

# --- NoPlateau Loop ---
cov=0
toggle=0
max_iterations=10 # Safety break
iterations=0

while [ $TIME_USED -lt $time_budget ] && [ $iterations -lt $max_iterations ]; do
    iterations=$((iterations + 1))
    echo "--- Iteration $iterations ---"

    echo "Time budget used so far: $TIME_USED / $time_budget seconds"
    remaining_time=$((time_budget - TIME_USED))
    echo "Remaining time budget: $remaining_time seconds"

    if [ $remaining_time -le 0 ]; then
        echo "Time budget exceeded."
        break
    fi
    if [ $toggle -eq 0 ]; then
        run_coverup
        toggle=1
    elif [ $toggle -eq 1 ]; then
        run_pynguin
        toggle=2
        # exit 1
    elif [ $toggle -eq 2 ]; then
        # TODO integrate diversity again
    #     make_diverse_tests
        toggle=0
    else
       echo "Error: Invalid toggle state: $toggle"
       break
    fi

    measure_coverage_output=$(measure_coverage)
    echo "$measure_coverage_output"
    cov=$(echo "$measure_coverage_output" | tail -n 1)
    echo "Current coverage: ${cov}%"
    if [ "$cov" -ge 100 ]; then
        echo "✅ Coverage is 100%! Done."
        break
    fi

    echo ">>> Iteration $iterations finished. Cumulative time used: $SECONDS seconds"
done

if [ $iterations -ge $max_iterations ]; then
    echo "WARNING: Reached maximum loop iterations ($max_iterations)."
fi

echo "--- Final Measurement ---"
measure_coverage_output=$(measure_coverage)
cov=$(echo "$measure_coverage_output" | tail -n 1)
echo ">>> Final coverage: ${cov}%"
echo ">>> Total script runtime: $SECONDS seconds"
echo ">>> Final time budget used by tools: $TIME_USED / $time_budget seconds"

echo ">>> Exiting."
