#!/bin/bash

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
    python3.10 ./src/pynguin/__main__.py --project-path targets --module-name fun --output-path outputs --verbose --maximum-iterations 50 --initial-population-seeding True --initial_population_data targets --seed 100

    TIME_USED=$((TIME_USED + 2))
}

function coverup {
    echo ">>> Coverup"
    cd coverup/src/
    python3.10 -m coverup.__main__ --source-dir targetsshort --tests-dir tests --model gpt-4o-mini --no-isolate-tests
    cd ..
    cd ..

    TIME_USED=$((TIME_USED + 2))
}

# Alternating loop
toggle=0
while [ $TIME_USED -lt $time_budget ]; do
    if [ $toggle -eq 0 ]; then
        pynguin
        toggle=1
    else
        coverup
        toggle=0
    fi    
    echo ">>> Time used so far: $TIME_USED"
done

echo ">>> Time budget exhausted. Exiting."
