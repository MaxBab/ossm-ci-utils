#!/bin/bash
# Parse test configuration from YAML file
# Usage: ./parse-test-config.sh <config_file> <suite> <stream>
# Example: ./parse-test-config.sh test-config-full.yaml security midstream_sail

set -e

CONFIG_FILE=$1
SKIP_PARSER_SUITE=$2
STREAM=$3

if [ -z "$CONFIG_FILE" ] || [ -z "$SKIP_PARSER_SUITE" ] || [ -z "$STREAM" ]; then
    echo "Usage: $0 <config_file> <suite> <stream>" >&2
    echo "  config_file: path to YAML config" >&2
    echo "  suite: pilot, ambient, telemetry, security, or helm" >&2
    echo "  stream: midstream_sail, midstream_helm, or downstream - returns only tests with this value in skip_in" >&2
    exit 1
fi

# Validate stream parameter
if [ "$STREAM" != "midstream_sail" ] && [ "$STREAM" != "midstream_helm" ] && [ "$STREAM" != "downstream" ]; then
    echo "Error: stream must be 'midstream_sail', 'midstream_helm', or 'downstream', got: '$STREAM'" >&2
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file '$CONFIG_FILE' not found"
    exit 1
fi

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: 'yq' is required but not installed."
    echo "Install with: brew install yq (macOS) or snap install yq (Linux)"
    exit 1
fi

# Build yq filter to return tests that have the specified stream in their skip_in array
FILTER_SKIP_TESTS=".test_suites.$SKIP_PARSER_SUITE.skip_tests[] | select(.skip_in[] == \"$STREAM\") | .name"
FILTER_SKIP_SUBSUITES=".test_suites.$SKIP_PARSER_SUITE.skip_subsuites[] | select(.skip_in[] == \"$STREAM\") | .name"
FILTER_RUN_TESTS_ONLY=".test_suites.$SKIP_PARSER_SUITE.run_tests_only[] | select(.skip_in[] == \"$STREAM\") | .name"

# Extract tests
SKIP_PARSER_SKIP_TESTS=$(yq eval "$FILTER_SKIP_TESTS" "$CONFIG_FILE" 2>/dev/null | paste -sd '|' -)
SKIP_PARSER_SKIP_SUBSUITES=$(yq eval "$FILTER_SKIP_SUBSUITES" "$CONFIG_FILE" 2>/dev/null | paste -sd '|' -)
SKIP_PARSER_RUN_TESTS_ONLY=$(yq eval "$FILTER_RUN_TESTS_ONLY" "$CONFIG_FILE" 2>/dev/null | paste -sd '|' -)

# Handle null/empty values
[ "$SKIP_PARSER_SKIP_TESTS" = "null" ] && SKIP_PARSER_SKIP_TESTS=""
[ "$SKIP_PARSER_SKIP_SUBSUITES" = "null" ] && SKIP_PARSER_SKIP_SUBSUITES=""
[ "$SKIP_PARSER_RUN_TESTS_ONLY" = "null" ] && SKIP_PARSER_RUN_TESTS_ONLY=""

# Output as shell variables (to stdout for eval)
echo "SKIP_PARSER_SKIP_TESTS='$SKIP_PARSER_SKIP_TESTS'"
echo "SKIP_PARSER_SKIP_SUBSUITES='$SKIP_PARSER_SKIP_SUBSUITES'"
echo "SKIP_PARSER_RUN_TESTS_ONLY='$SKIP_PARSER_RUN_TESTS_ONLY'"
echo "SKIP_PARSER_SUITE='$SKIP_PARSER_SUITE'"

# Example usage in another script:
# Midstream Sail:
#   eval $(./parse-test-config.sh test-config-full.yaml security midstream_sail)
# Midstream Helm:
#   eval $(./parse-test-config.sh test-config-full.yaml security midstream_helm)
# Downstream:
#   eval $(./parse-test-config.sh test-config-full.yaml security downstream)
# Then run:
#   integ-suite-ocp.sh "$SKIP_PARSER_SUITE" "$SKIP_PARSER_SKIP_TESTS" "$SKIP_PARSER_SKIP_SUBSUITES" "$SKIP_PARSER_RUN_TESTS_ONLY"
