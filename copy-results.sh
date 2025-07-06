#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Usage: $0 <number> <folder>"
    echo "Example: $0 30 coverup"
    exit 1
fi

number=$1
folder=$2

rm -r scratch
tar -xzf experiment_data.tar.gz

for dir in scratch/experiment-results/*/; do
    if [ -d "$dir" ]; then
        echo "Processing directory: $dir"
        cd "$dir"
        for i in {30..0}; do
            if [ -d "$i" ]; then
                mv "$i" "$((i + $number))";
                echo "Renamed $i to $((i + $number))";
            fi;
        done
        cd - > /dev/null
    fi
done

cp -r scratch data/$folder/
