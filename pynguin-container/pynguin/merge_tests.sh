#!/bin/bash

# === Config ===
TEST_DIR=$1
ITERATION=$2
OUTPUT_FILE_NAME=$3
MERGED_FILE="${TEST_DIR}/${OUTPUT_FILE_NAME}"

# === Find all test Python files ===
TEST_FILES=($(find "$TEST_DIR" -maxdepth 1 -type f -name "*.py" ! -name "$(basename "$MERGED_FILE")"))

if [ ${#TEST_FILES[@]} -eq 0 ]; then
    echo "❌ No .py test files found in $TEST_DIR"
    exit 1
fi

echo "🔍 Found ${#TEST_FILES[@]} test files to merge."

# === Begin merged file ===
echo "# Auto-merged test file for Pynguin" > "$MERGED_FILE"
echo "" >> "$MERGED_FILE"

# === Add functions with renamed test names to ensure uniqueness ===
test_counter=1
for file in "${TEST_FILES[@]}"; do
    prefix=$(basename "$file" .py | sed 's/[^a-zA-Z0-9_]/_/g')

    awk -v prefix="$prefix" -v iteration="$ITERATION" -v counter="$test_counter" '
        /^def test_/ && !/^def test_iter/ {
            sub(/^def test_/, "def test_iter" iteration "_" counter "_")
        }
        { print }
    ' "$file" >> "$MERGED_FILE"

    # Increment counter for next file
    test_counter=$((test_counter + 1))
    
    rm $file

    echo "" >> "$MERGED_FILE"
done

echo "✅ Merged test file created: $MERGED_FILE"
