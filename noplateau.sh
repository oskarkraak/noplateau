#!/bin/bash

SECONDS=0

# constants
time_budget=60
pynguin_time=15
coverup_dir="coverup/src"
target_dir="noplateautargets"
target_module="noplateautargets.funcode"
test_dir="noplateautests"


base_dir=$(pwd)
echo ">>> $base_dir"

# Check if OPENAI_API_KEY is set
if [[ -z "$OPENAI_API_KEY" ]]; then
    echo ">>> Error: OPENAI_API_KEY is not set."
    exit 1
else
    echo ">>> OPENAI_API_KEY is set."
fi

rm -r $coverup_dir/$target_dir
rm -r $coverup_dir/$test_dir
mkdir $test_dir
touch $target_dir/__init__.py
cp -r $target_dir $coverup_dir/$target_dir
cp -r $test_dir $coverup_dir/$test_dir

# noplateau loop

TIME_USED=0

function pynguin {
    echo ">>> Pynguin"

    export PYNGUIN_DANGER_AWARE=true
    export PYTHONPATH=./src:$PYTHONPATH
    TIME_LEFT=$((time_budget - TIME_USED))
    if [ $TIME_LEFT -lt $pynguin_time ]; then
        pynguin_time=$TIME_LEFT
    fi

    # TODO: make pynguin quit when plateau
    python3.10 ./src/pynguin/__main__.py \
        --project-path $target_dir \
        --module-name $target_module \
        --output-path $test_dir \
        --verbose \
        --initial-population-seeding True \
        --initial_population_data outputs \
        --seed 0 \
        --maximum_search_time $pynguin_time
        #--assertion_generation=NONE
    TIME_USED=$((TIME_USED + pynguin_time))

    rm -r $coverup_dir/$test_dir
    cp -r $test_dir $coverup_dir/$test_dir
}

function coverup {
    echo ">>> Coverup"
    cd coverup/src/
    time_before=$SECONDS

    # TODO: make coverup quit if time budget is used up (take time as input argument)
    python3.10 -m coverup.__main__ \
    --source-dir $target_dir \
    --tests-dir $test_dir \
    --model gpt-4o-mini \
    --no-isolate-tests
    
    time_after=$SECONDS
    TIME_USED=$((TIME_USED + time_after - time_before))
    cd ../..

    rm -r $test_dir
    cp -r $coverup_dir/$test_dir $test_dir
}

# Alternating loop
toggle=0
while [ $TIME_USED -lt $time_budget ]; do
    if [ $toggle -eq 0 ]; then
        coverup
        toggle=1
    else
        pynguin
        toggle=0
    fi    
    echo ">>> Total runtime: $SECONDS"
    echo ">>> Time budget used so far: $TIME_USED / $time_budget"
done

echo ">>> Time budget exhausted. Exiting."
