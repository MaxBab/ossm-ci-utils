# Testing Documentation

This directory contains unit tests for the `parse-test-config.sh` script.

## Quick Start

### Simple Test Runner (No Dependencies)

The simplest way to run tests without installing anything:

```bash
cd skip_tests
./run_tests.sh
```

This uses a standalone test runner that doesn't require any external frameworks.

## What's Tested

### Stream Validation
- ✅ Accepts `midstream_sail` as valid stream
- ✅ Accepts `midstream_helm` as valid stream
- ✅ Accepts `downstream` as valid stream
- ✅ Rejects invalid stream values

### Filtering Logic
- ✅ Filters tests by `midstream_sail` stream
- ✅ Filters tests by `midstream_helm` stream
- ✅ Filters tests by `downstream` stream
- ✅ Correctly handles multiple streams in `skip_in` arrays

### Subsuite Handling
- ✅ Filters subsuites correctly for midstream_sail
- ✅ Filters subsuites correctly for midstream_helm

### Output Format
- ✅ All required environment variables present
- ✅ Multiple tests are pipe-separated
- ✅ Output is compatible with `eval`

### Edge Cases
- ✅ Empty test suites return empty results
- ✅ Non-existent config file error handling
- ✅ run_tests_only filtering

## Test Results

Current status: ✅ **All 13 tests passing**

```
✓ test_invalid_stream_parameter
✓ test_accepts_midstream_sail
✓ test_accepts_midstream_helm
✓ test_accepts_downstream
✓ test_filter_midstream_sail
✓ test_filter_midstream_helm
✓ test_filter_downstream
✓ test_subsuite_filtering_midstream_sail
✓ test_subsuite_filtering_midstream_helm
✓ test_run_tests_only_filtering
✓ test_empty_suite
✓ test_output_format
✓ test_eval_compatibility
```

## Adding New Tests

### Using run_tests.sh (Simple)

Add a function starting with `test_` to `run_tests.sh`:

```bash
function test_my_new_feature() {
    local output
    output=$("$SCRIPT_PATH" "$TEST_CONFIG_FILE" pilot midstream_sail 2>&1)
    assert_contains "$output" "expected_value"
}
```

Then add it to the main execution section:

```bash
run_test test_my_new_feature
```
