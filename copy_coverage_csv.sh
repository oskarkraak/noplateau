#!/bin/bash

TARGET_DIR="./coverage_csv_files"
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

BASE_DIR="./scratch/experiment-results"

echo "Kopiere Coverage-CSV-Dateien..."

find "$BASE_DIR" -type f -path "*/results-*/logs/*coverage*.csv" | while read -r file; do
    result_num=$(echo "$file" | sed -r 's|.*/results-([0-9]+)/logs/.*|\1|')
    filename=$(basename "$file")

    new_filename="result${result_num}_${filename}"
    cp "$file" "$TARGET_DIR/$new_filename"
    echo "Kopiert: $file -> $TARGET_DIR/$new_filename"
done

echo "Finished copying coverage CSV files to $TARGET_DIR"
