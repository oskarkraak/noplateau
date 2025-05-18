#!/bin/bash

TEST_FILE=$1
ITERATION=$2

# 1. Run pytest and capture output
PYTEST_OUTPUT=$(pytest "$TEST_FILE" -v --tb=short -q --disable-warnings)

# Extract test function names from lines like "FAILED generated-tests/test_merged.py::test_llm_tests_test_timer_multiple_starts"
FAILED_TESTS=$(echo "$PYTEST_OUTPUT" | grep "FAILED" | sed -E 's/.*::(test_[a-zA-Z0-9_]+).*/\1/' | sort | uniq)

echo "Debug: Pytest output contains $(echo "$PYTEST_OUTPUT" | grep -c "FAILED") FAILED lines"
echo "Debug: Extracted $(echo "$FAILED_TESTS" | wc -l) failing test names"

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
