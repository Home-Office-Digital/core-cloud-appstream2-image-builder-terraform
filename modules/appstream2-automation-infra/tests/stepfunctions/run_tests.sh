#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Static: DescribeStaleExecution Catch wiring ==="
bash "${SCRIPT_DIR}/validate_describe_stale_execution_catch.sh"

echo
echo "=== AWS integration: ExecutionDoesNotExist negative test ==="
bash "${SCRIPT_DIR}/test_execution_not_found_catch.aws.sh"

echo
echo "All tests completed."