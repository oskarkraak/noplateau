#!/bin/bash

SECONDS=0

# constants
time_budget=31
estimated_pynguin_overhead_time=30
#coverup_dir="coverup/src"
#target_dir="noplateautargets"
#target_module="noplateautargets.funcode"

target_module=$3
seed=$4
OPENAI_API_KEY=$5
target_dir=$6
output_dir=$7

test_dir="$output_dir/noplateautests/"
coverup_target_dir="$output_dir/target/"
base_dir=$(pwd)


# Convert the module name (e.g., flutils.pathutils) to a relative path (e.g., flutils/pathutils)
module_relative_path=$(echo "$target_module" | tr . /)
# Construct the full target file path by joining the target directory and the relative path, adding the .py extension
original_target_file_path="$target_dir/$module_relative_path.py"
#target_file_path="$output_dir/target/$module_relative_path.py"
#coverup_target_dir=$(dirname "$target_file_path")
# Optional: Verify if the file exists
if [ -f "$original_target_file_path" ]; then
  echo "Calculated file path: $original_target_file_path"
else
  echo "Warning: Calculated file path does not appear to exist: $original_target_file_path"
  # You might want to exit or handle this case differently if the file is expected to exist
  # exit 1
fi


export PYTHONPATH="$output_dir:$PYTHONPATH"
echo "PYTHONPATH=$PYTHONPATH"


echo "> Running NoPlateau:"
#echo ">>> $base_dir"
echo ">>> Time budget: $time_budget"
echo ">>> Test dir: $test_dir"
echo ">>> Target module: $target_module"
echo ">>> Seed: $seed"
echo ">>> API key: $OPENAI_API_KEY"
echo ">>> Target dir: $target_dir"
echo ">>> Output dir: $output_dir"
echo ">>> Coverup target dir: $coverup_target_dir"

export OPENAI_API_KEY="$OPENAI_API_KEY"

#rm -r $coverup_dir/$target_dir
#rm -r $coverup_dir/$test_dir
mkdir $test_dir
#touch $target_dir/__init__.py
#cp -r $target_dir $coverup_dir/$target_dir
#cp -r $test_dir $coverup_dir/$test_dir
mkdir $coverup_target_dir
touch $coverup_target_dir/__init__.py
# Copy the target file to the coverup target directory
cp "$original_target_file_path" "$coverup_target_dir/"
echo "Successfully copied $original_target_file_path to $coverup_target_dir/"
echo "$coverup_target_dir:"
ls $coverup_target_dir

pynguin_original_import=$target_module
filename=$(basename "$original_target_file_path")
filename_without_ending="${filename%.py}"
pynguin_replacement_import="target.$filename_without_ending"


### noplateau loop ###

TIME_USED=0

function run_pynguin {
    echo ">>> Pynguin"
    time_before=$SECONDS

    bash /pynguin/merge_tests.sh $test_dir
    sed -i "s#$pynguin_replacement_import#$pynguin_original_import#g" $test_dir/test_merged.py
    export PYNGUIN_DANGER_AWARE=true
    export PYTHONPATH=./src:$PYTHONPATH
    TIME_LEFT=$((time_budget - TIME_USED))
    max_search_time=$((TIME_LEFT - estimated_pynguin_overhead_time))
    if [ $max_search_time -le 0 ]; then
        return 1
    fi

    echo "run pynguin" # TODO debug
    pynguin \
        --project-path $target_dir \
        --module-name $target_module \
        --output-path $test_dir \
        --initial-population-seeding True \
        --initial_population_data $test_dir \
        --seed $seed \
        --coverage-metrics BRANCH \
        --maximum_search_time $max_search_time \
        --maximum_coverage_plateau 30 \
        --verbose
    echo "ran pynguin!"

    sed -i "s#$pynguin_original_import#$pynguin_replacement_import#g" $test_dir/*.py
    cat $test_dir/*.py
    time_after=$SECONDS
    TIME_USED=$((TIME_USED + time_after - time_before))
}

function run_coverup {
    echo ">>> Coverup"
    time_before=$SECONDS

    echo "target dir: $coverup_target_dir"
    ls $coverup_target_dir

    # TODO: make coverup quit if time budget is used up (take time as input argument)
    python3.10 -m coverup \
    --package $coverup_target_dir \
    --tests-dir $test_dir \
    --model gpt-4o-mini \
    --no-isolate-tests

    #cat coverup-log
    
    time_after=$SECONDS
    TIME_USED=$((TIME_USED + time_after - time_before))
}

function make_diverse_tests {
    echo ">>> Making more diverse tests"

    bash /pynguin/merge_tests.sh $test_dir
    mistral_script=$test_dir/llm_tests.py
    python3.10 /pynguin/mistral.py \
        --input "noplateautargets/funcode.py" \
        --target_module_name "$target_module" \
        --tests "${test_dir}/test_merged_funcode.py" \
        --output $mistral_script \
        --diversity True
    bash /pynguin/remove_failing_tests.sh $mistral_script

    echo ">>> Trimming markdown syntax from the generated file..."
    sed -i '1{/^\s*```python\s*$/d}; ${/^\s*```\s*$/d}' $mistral_script
    sed -i '/your_module/d' $mistral_script
}

function measure_coverage {
    echo "▶️ Running tests with coverage..."

    # Run pytest and capture both stdout and stderr
    local output
    output=$(python3.10 -m pytest --cov-branch --cov=$coverup_target_dir $test_dir --cov-report=term 2>&1)

    # Extract total line and coverage percent
    local total_line
    total_line=$(echo "$output" | grep -E 'TOTAL\s+[0-9]+')

    local coverage
    coverage=$(echo "$total_line" | awk '{print $(NF)}' | tr -d '%')

    echo "📊 Extracted total coverage: ${coverage}%"

    # Echo the coverage so the caller can capture it
    echo "$coverage"
}

# Alternating loop
cov=0
toggle=0
while [ $TIME_USED -lt $time_budget ]; do
    echo "test dir: $test_dir"
    cat $test_dir*

    

    echo "--- Verifying CoverUp environment imports ---"
    python3.10 <<EOF
import sys
import os
print("Current working directory:", os.getcwd())
print("sys.path:", sys.path)

try:
    import target.decorators as td
    print(f"Successfully imported target.decorators: {td}")
    from target.decorators import cached_property
    print("Successfully imported cached_property")
except (ImportError, AttributeError) as e:
    print(f"Error during target.decorators import or attribute access: {e}")

try:
    import flutils.decorators as fd
    print(f"Successfully imported flutils.decorators: {fd}")
except ImportError as e:
    print(f"ImportError importing flutils.decorators: {e}")
EOF
    echo "---------------------------------------------"
    
    python3.10 -m pytest --cov-branch --cov=$coverup_target_dir $test_dir --cov-report=term

    cov=$(measure_coverage | tail -n 1)
    if [ $cov -eq 100 ]; then
        echo "✅ Coverage is 100%! Done."
        break
    else
        echo ">>> Coverage: ${cov}%"
    fi

    if [ $toggle -eq 0 ]; then
        run_pynguin
        toggle=1
    elif [ $toggle -eq 1 ]; then
        run_coverup
        #toggle=2
        # TODO integrate diversity again
        exit 1

        toggle=0
    else
        make_diverse_tests
        TIME_USED=$((TIME_USED + 15))
        toggle=0
    fi    
    echo ">>> Total runtime: $SECONDS"
    echo ">>> Time budget used so far: $TIME_USED / $time_budget"
done
cov=$(measure_coverage | tail -n 1)
echo ">>> Final coverage: ${cov}%"

cp -r $test_dir $output_dir

echo ">>> Exiting."
