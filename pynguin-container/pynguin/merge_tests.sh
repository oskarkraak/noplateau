#!/bin/bash

# === Config ===
TEST_DIR=$1
MERGED_FILE="${TEST_DIR}/test_merged.py"

# === Find all test Python files ===
TEST_FILES=($(find "$TEST_DIR" -maxdepth 1 -type f -name "*.py" ! -name "$(basename "$MERGED_FILE")"))

if [ ${#TEST_FILES[@]} -eq 0 ]; then
    echo "❌ No .py test files found in $TEST_DIR"
    exit 1
fi

echo "🔍 Found ${#TEST_FILES[@]} test files to merge."

# === Rename originals ===
for file in "${TEST_FILES[@]}"; do
    mv "$file" "$file.bak"
    echo "🔁 Renamed $file → $file.bak"
done

# === Begin merged file ===
echo "# Auto-merged test file for Pynguin" > "$MERGED_FILE"
echo "" >> "$MERGED_FILE"

# === Add functions with renamed test names ===
for file in "${TEST_FILES[@]}"; do
    prefix=$(basename "$file" .py | sed 's/[^a-zA-Z0-9_]/_/g')

    awk -v prefix="$prefix" '
        BEGIN { in_func = 0 }
        /^def test_/ {
            sub(/^def test_/, "def test_" prefix "_test_")
            in_func = 1
        }
        in_func {
            print
            if (/^$/) in_func = 0
            next
        }
        { print }
    ' "$file.bak" >> "$MERGED_FILE"

    echo "" >> "$MERGED_FILE"
done

echo "✅ Merged test file created: $MERGED_FILE"
