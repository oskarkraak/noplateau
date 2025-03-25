#!/bin/bash

SECONDS=0

# constants
pynguin_time=5

base_dir=$(pwd)
echo ">>> $base_dir"

time_budget=$1

if [[ -z "$time_budget" ]]; then
    echo ">>> Usage: $0 <time_budget>"
    exit 1
fi

# Check if OPENAI_API_KEY is set
if [[ -z "$OPENAI_API_KEY" ]]; then
    echo ">>> Error: OPENAI_API_KEY is not set."
    exit 1
else
    echo ">>> OPENAI_API_KEY is set."
fi


# noplateau loop

TIME_USED=0

function pynguin {
    echo ">>> Pynguin"

    export PYNGUIN_DANGER_AWARE=true
    export PYTHONPATH=./src:$PYTHONPATH
    TIME_LEFT=$((time_budget - TIME_USED))
    if [$TIME_LEFT -lt $pynguin_time]; then
        pynguin_time=$TIME_LEFT
    fi

    python3.10 ./src/pynguin/__main__.py \
        --project-path targets \
        --module-name fun \
        --output-path outputs \
        --verbose \
        --initial-population-seeding True \
        --initial_population_data targets \
        --seed 0 \
        --assertion_generation=NONE \
        --maximum_search_time $pynguin_time
    TIME_USED=$((TIME_USED + pynguin_time))
}

function coverup {
    echo ">>> Coverup"
    cd coverup/src/
    time_before=$SECONDS

    # TODO: make coverup take time as input argument
    python3.10 -m coverup.__main__ --source-dir targetsshort --tests-dir tests --model gpt-4o-mini --no-isolate-tests
    
    time_after=$SECONDS
    TIME_USED=$((TIME_USED + time_after - time_before))
    cd ../..
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
