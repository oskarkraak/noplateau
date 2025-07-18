#!/bin/bash

# constants
estimated_pynguin_overhead_time=30
coverup_dir="/pynguin/coverup/src"
# parameters
time_budget=600
pynguin_max_plateau=300
coverup_max_plateau=3


SECONDS=0

target_module=$3
seed=$4
OPENAI_API_KEY=$5
target_dir=$6
output_dir=$7

# ─── LOGGING ───
logging_dir="$output_dir/logs/"
run_id=$8
mkdir -p "$logging_dir"
coverage_log_file="$logging_dir/coverage_${run_id}.csv"
# Create CSV header if file doesn't exist
if [ ! -f "$coverage_log_file" ]; then
    echo "iteration,finish_timestamp,finish_total_time_used,iteration_type,best_coverage,coverage" > "$coverage_log_file"
fi
# ─────────────────

echo "iter types"
echo $9
echo ${10}
echo ${11}

# Parse iteration types
iteration_type_coverup=$9
iteration_type_diversity=${10}
iteration_type_pynguin=${11}
if [ "$iteration_type_coverup" != "true" ] && [ "$iteration_type_diversity" != "true" ]; then
    pynguin_max_plateau=-1 # Run Pynguin only
fi
enabled_types=()
[ "$iteration_type_coverup" == "true" ] && enabled_types+=("coverup")
[ "$iteration_type_diversity" == "true" ] && enabled_types+=("diversity")
[ "$iteration_type_pynguin" == "true" ] && enabled_types+=("pynguin")
if [ ${#enabled_types[@]} -eq 0 ]; then
    echo "Error: No enabled iteration types."
    exit 2
else
    echo "Enabled iteration types: ${enabled_types[*]}"
fi

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



# Extract the file part (everything after the last dot)
# Remove the longest prefix ending in '.' (${string##*.})
target_module_file="${target_module##*.}"
# Extract the folder part (everything before the last dot)
# Remove the shortest suffix starting with '.' (${string%.*})
target_module_folder="${target_module%.*}"
target_module_folder="${target_module_folder//./\/}" # Replace dots with slashes for folder structure
# Extract the root folder (the first component before any dot)
target_module_root_folder="${target_module%%.*}"

mkdir $test_dir
coverup_test_dir=$coverup_dir/generated-tests/
mkdir $coverup_test_dir
cp -r $target_dir/$target_module_root_folder $coverup_dir
touch $coverup_dir/$target_module_folder/__init__.py

echo ">>> target_module_folder: $target_module_folder"
echo ">>> target_module_file: $target_module_file"
echo ">>> coverup_test_dir: $coverup_test_dir"


echo "> Running NoPlateau:"
echo ">>> Time budget: $time_budget"
echo ">>> Test dir: $test_dir"
echo ">>> Target module: $target_module"
echo ">>> Seed: $seed"
echo ">>> Target dir: $target_dir"
echo ">>> Output dir: $output_dir"

export OPENAI_API_KEY="$OPENAI_API_KEY"

export PYTHONPATH=/pynguin/src:$PYTHONPATH # Pynguin
export PYTHONPATH="$target_dir:$PYTHONPATH" # Pytest & CoverUp
echo "PYTHONPATH=$PYTHONPATH"

python3.10 -c "import $target_module"
if [ $? -ne 0 ]; then
  echo "Error: Failed to import Python module '$target_module'." >&2
  #exit 1
fi


### noplateau loop ###

TIME_USED=0

function run_pynguin {
    echo ">>> Pynguin"
    time_before=$SECONDS

    export PYNGUIN_DANGER_AWARE=true
    TIME_LEFT=$((time_budget - TIME_USED))
    max_search_time=$((TIME_LEFT - estimated_pynguin_overhead_time))
    if [ $max_search_time -le 0 ]; then
        echo "Not enough time budget left for Pynguin search."
        return 1 # Use return code to indicate failure/skip
    fi

    bash /pynguin/merge_tests.sh $test_dir $iterations "test_merged.py"

    ls $test_dir

    echo "Running pynguin with max search time: $max_search_time seconds"
    python3.10 /pynguin/src/pynguin/__main__.py \
        --project-path "$target_dir" \
        --module-name "$target_module" \
        --output-path "$test_dir" \
        --initial-population-seeding True \
        --initial_population_data "$test_dir" \
        --seed "$seed" \
        --coverage-metrics BRANCH \
        --maximum_search_time "$max_search_time" \
        --maximum_coverage_plateau $pynguin_max_plateau \
        --verbose \
        --report-dir "$logging_dir/pynguin-report_${run_id}_iteration_${iterations}" \
        --timeline_interval=5000000000 \
        --output_variables Coverage AlgorithmIterations TotalTime CoverageTimeline

    local pynguin_exit_code=$? # Capture exit code
    if [ $pynguin_exit_code -ne 0 ]; then
        echo "Pynguin failed with exit code $pynguin_exit_code"
        # Decide how to handle Pynguin failure (e.g., exit, continue, retry?)
        # For now, let's just report and continue
    else
         echo "Pynguin completed successfully."
    fi

    rm -f $test_dir/test_merged.py

    rm -r $coverup_test_dir
    cp -r $test_dir $coverup_test_dir

    time_after=$SECONDS
    TIME_USED=$((TIME_USED + time_after - time_before))

    return $pynguin_exit_code # Return Pynguin's exit code
}

function run_coverup {
    echo ">>> Coverup"
    cd $coverup_dir
    time_before=$SECONDS

    echo "PYTHONPATH: $PYTHONPATH"

    # Check if the target file exists in the coverup dir before running
    if [ ! -f "$original_target_file_path" ]; then
        echo "ERROR: Target file '$original_target_file_path' not found in coverup directory before running CoverUp."
        return 1 # Indicate failure
    fi

    # TODO: make coverup quit if time budget is used up (take time as input argument)
    python3.10 -m coverup \
        "$target_module_folder/$target_module_file.py" \
        --source-dir $target_module_folder \
        --tests-dir $coverup_test_dir \
        --model gpt-4o-mini \
        --no-isolate-tests \
        --log-file "$coverup_test_dir/coverup-log_${run_id}_iteration_${iterations}.txt" \
        --max-attempts $coverup_max_plateau \
        --iteration $iterations

    local coverup_exit_code=$?
    if [ $coverup_exit_code -ne 0 ]; then
        echo "CoverUp failed with exit code $coverup_exit_code"
    else
        echo "CoverUp completed successfully."
    fi

    cd $base_dir

    rm -r $test_dir
    cp -r $coverup_test_dir $test_dir

    time_after=$SECONDS
    TIME_USED=$((TIME_USED + time_after - time_before))
    return $coverup_exit_code # Return CoverUp's exit code
}

function make_diverse_tests {
    echo ">>> Making more diverse tests"
    time_before=$SECONDS

    bash /pynguin/merge_tests.sh $test_dir $iterations "test_merged.py"
    llm_tests=$test_dir/test_llm_diversity.py
    python3.10 /pynguin/mistral.py \
         --input "$original_target_file_path" \
         --target_module_name "$target_module" \
         --tests "$test_dir/test_merged.py" \
         --output $llm_tests \
         --diversity True
    
    rm -f $test_dir/test_merged.py

    echo ">>> Trimming markdown syntax from the generated file \"$llm_tests\"..."
    sed -i '1{/^\s*```python\s*$/d}; ${/^\s*```\s*$/d}' $llm_tests
    sed -i '/your_module/d' $llm_tests

    bash /pynguin/remove_failing_tests.sh $llm_tests $iterations

    time_after=$SECONDS
    TIME_USED=$((TIME_USED + time_after - time_before))
}

function measure_coverage {
    echo "▶️ Running tests with coverage..."
    
    echo "PYTHONPATH: $PYTHONPATH"
    
    # Create coverage report filename based on iteration and run_id
    local cov_report_file="$logging_dir/coverage_report_${run_id}_iteration_${iterations}.xml"
    
    local output
    output=$(python3.10 -m pytest --cov-branch --cov="$target_module" "$test_dir" --cov-report=term --cov-report=xml:"$cov_report_file" 2>&1)
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
    echo "📝 Full coverage report saved to: $cov_report_file"
    echo "$coverage"
}

function remove_all_failing_tests {
    for py_file in "$test_dir"/*.py; do
        bash /pynguin/remove_failing_tests.sh "$py_file" $iterations
    done
}

function backup_test_files {
    local backup_dir="$output_dir/test_backups/iteration_${iterations}"
    echo ">>> Creating backup of test files in $backup_dir"
    mkdir -p "$backup_dir"
    cp "$test_dir"/*.py "$backup_dir"/ 2>/dev/null || echo "No .py files to backup"
}

# --- NoPlateau Loop ---
cov=0
toggle=0
max_iterations=100 # Safety break
iterations=0
best_coverage=0

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

    current_type="${enabled_types[$toggle]}"
    iteration_type="$current_type"
    case "$current_type" in
        "coverup")
            run_coverup
            ;;
        "diversity")
            make_diverse_tests
            ;;
        "pynguin")
            run_pynguin
            ;;
        *)
            echo "Error: Unknown iteration type '$current_type'"
            iteration_type="unknown"
            break
            ;;
    esac
    toggle=$(( (toggle + 1) % ${#enabled_types[@]} ))

    measure_coverage_output=$(measure_coverage)
    echo "$measure_coverage_output"
    cov=$(echo "$measure_coverage_output" | tail -n 1)
    echo "Current coverage: ${cov}%"

    if [ "$cov" -gt "$best_coverage" ]; then
        best_coverage=$cov
    fi

    # ─── LOGGING ───
    echo "$iterations,$SECONDS,$TIME_USED,$iteration_type,$best_coverage,$cov" >> $coverage_log_file
    # ─────────────────

    backup_test_files

    if [ "$cov" -ge 100 ]; then
        echo "✅ Coverage is 100%! Done."
        break
    fi

    echo ">>> Iteration $iterations finished. Cumulative time used: $TIME_USED seconds"
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
