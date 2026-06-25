#!/usr/bin/env bash
# Static negative-test guard: DescribeStaleExecution must catch ONLY
# Sfn.ExecutionDoesNotExistException and route to TakeoverAcquireLock.
# Does not call AWS — safe for CI without credentials.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASL_FILE="${ASL_FILE:-${SCRIPT_DIR}/../fixtures/stepfunction_definition.json}"

if [[ ! -f "${ASL_FILE}" ]]; then
  echo "FATAL: ASL not found at ${ASL_FILE}" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FATAL: jq is required" >&2
  exit 1
fi

python3 -m json.tool "${ASL_FILE}" >/dev/null

CATCH_JSON="$(jq -c '.States.DescribeStaleExecution.Catch' "${ASL_FILE}")"
FIRST_EQUALS="$(jq -r '.States.DescribeStaleExecution.Catch[0].ErrorEquals | join(",")' "${ASL_FILE}")"
FIRST_NEXT="$(jq -r '.States.DescribeStaleExecution.Catch[0].Next' "${ASL_FILE}")"
SECOND_EQUALS="$(jq -r '.States.DescribeStaleExecution.Catch[1].ErrorEquals | join(",")' "${ASL_FILE}")"
SECOND_NEXT="$(jq -r '.States.DescribeStaleExecution.Catch[1].Next' "${ASL_FILE}")"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "${FIRST_EQUALS}" == "Sfn.ExecutionDoesNotExistException" ]] \
  || fail "first Catch ErrorEquals must be exactly Sfn.ExecutionDoesNotExistException (got: ${FIRST_EQUALS})"

[[ "${FIRST_NEXT}" == "TakeoverAcquireLock" ]] \
  || fail "first Catch Next must be TakeoverAcquireLock (got: ${FIRST_NEXT})"

[[ "${SECOND_EQUALS}" == "States.ALL" ]] \
  || fail "second Catch ErrorEquals must be States.ALL alone (got: ${SECOND_EQUALS})"

[[ "${SECOND_NEXT}" == "LockFailed" ]] \
  || fail "second Catch Next must be LockFailed (got: ${SECOND_NEXT})"

# Reject unverified spellings in Catch ErrorEquals arrays only (not Comment prose).
for bad in \
  "StepFunctions.ExecutionDoesNotExistException" \
  "ExecutionDoesNotExist" \
  "StepFunctions.ExecutionDoesNotExist" \
  "Sfn.ExecutionDoesNotExist"
do
  if jq -e --arg bad "${bad}" '
    .States.DescribeStaleExecution.Catch[]?.ErrorEquals[]? | select(. == $bad)
  ' "${ASL_FILE}" >/dev/null 2>&1; then
    fail "forbidden unverified ErrorEquals variant in DescribeStaleExecution.Catch: ${bad}"
  fi
done

HARNESS_FILE="${SCRIPT_DIR}/fixtures/describe_stale_execution_negative.asl.json"
PROD_CATCH="$(jq -c '.States.DescribeStaleExecution.Catch' "${ASL_FILE}")"
HARNESS_CATCH="$(jq -c '.States.DescribeStaleExecution.Catch' "${HARNESS_FILE}")"
[[ "${PROD_CATCH}" == "${HARNESS_CATCH}" ]] \
  || fail "test harness Catch block drifted from production ASL — sync ${HARNESS_FILE}"

echo "PASS: DescribeStaleExecution Catch wiring (${ASL_FILE})"
echo "      [0] ErrorEquals=[Sfn.ExecutionDoesNotExistException] -> TakeoverAcquireLock"
echo "      [1] ErrorEquals=[States.ALL] -> LockFailed"