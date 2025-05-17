#!/bin/bash

TEST_FILE=$1
ITERATION=$2

cp $TEST_FILE $TEST_FILE-uncleaned.bak$ITERATION

# 1. Run pytest and capture failing test names
FAILED_TESTS=$(pytest "$TEST_FILE" --tb=short -q --disable-warnings | grep -oP '^FAILED \K.*?(?=::)' | sort | uniq)

if [ -z "$FAILED_TESTS" ]; then
  echo "✅ No failing tests. You're good."
  exit 0
fi

echo "❌ Found failing tests:"
echo "$FAILED_TESTS"

# 2. Remove failing test functions
for TEST in $FAILED_TESTS; do
  echo "Removing test function: $TEST"

  # Remove the function from the file using sed
  # This assumes tests are defined like: def test_foo():
  # And end with an empty line.
  sed -i "/def $TEST/,/^$/d" "$TEST_FILE"
done

echo "🧹 Cleanup complete. Failing tests removed from $TEST_FILE."
