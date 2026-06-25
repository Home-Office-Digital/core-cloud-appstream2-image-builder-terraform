#!/usr/bin/env bash
# AWS integration negative test: call DescribeStaleExecution against a
# deliberately non-existent execution ARN and assert the Catch routes to
# TakeoverAcquireLock with error Sfn.ExecutionDoesNotExistException.
#
# Requires:
#   - aws CLI v2 with stepfunctions test-state
#   - credentials for the target account
#   - STEP_FUNCTION_TEST_ROLE_ARN: role with states:DescribeExecution on
#     execution ARNs in this account (the deployed step-function role works)
#
# Optional env:
#   AWS_REGION          (default: eu-west-2)
#   AWS_ACCOUNT_ID      (default: from sts get-caller-identity)
#   ASL_HARNESS_FILE    (default: tests/fixtures/describe_stale_execution_negative.asl.json)
#
# Skips gracefully when STEP_FUNCTION_TEST_ROLE_ARN is unset (local/CI without AWS).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_FILE="${ASL_HARNESS_FILE:-${SCRIPT_DIR}/fixtures/describe_stale_execution_negative.asl.json}"
AWS_REGION="${AWS_REGION:-eu-west-2}"

if [[ -z "${STEP_FUNCTION_TEST_ROLE_ARN:-}" ]]; then
  echo "SKIP: STEP_FUNCTION_TEST_ROLE_ARN not set — AWS integration negative test not run."
  echo "      Export the Step Functions role ARN and re-run to verify the live error name."
  exit 0
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "SKIP: aws CLI not found" >&2
  exit 0
fi

if ! aws stepfunctions test-state help >/dev/null 2>&1; then
  echo "SKIP: aws stepfunctions test-state not available in this AWS CLI build" >&2
  exit 0
fi

ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

# Guaranteed non-existent execution: valid ARN shape, fake name + UUID.
FAKE_EXECUTION_ARN="arn:aws:states:${AWS_REGION}:${ACCOUNT_ID}:execution:ccpam-negative-test-nonexistent-sm:00000000-0000-0000-0000-000000000000"

TEST_INPUT="$(jq -nc --arg arn "${FAKE_EXECUTION_ARN}" '{lockExecutionArn: $arn}')"
DEFINITION="$(jq -c . "${HARNESS_FILE}")"

echo ">>> test-state: DescribeStaleExecution with non-existent execution ARN"
echo "    ARN: ${FAKE_EXECUTION_ARN}"

RESPONSE="$(aws stepfunctions test-state \
  --region "${AWS_REGION}" \
  --definition "${DEFINITION}" \
  --role-arn "${STEP_FUNCTION_TEST_ROLE_ARN}" \
  --input "${TEST_INPUT}" \
  --output json)"

echo "${RESPONSE}" | jq .

NEXT_STATE="$(echo "${RESPONSE}" | jq -r '.nextState // empty')"
ERROR_NAME="$(echo "${RESPONSE}" | jq -r '.error // empty')"
STATUS="$(echo "${RESPONSE}" | jq -r '.status // empty')"

fail() {
  echo "FAIL: $*" >&2
  echo "Full response:" >&2
  echo "${RESPONSE}" | jq . >&2
  exit 1
}

# When Catch handles the SDK error, test-state reports the Catch target as nextState.
[[ "${NEXT_STATE}" == "TakeoverAcquireLock" ]] \
  || fail "expected nextState=TakeoverAcquireLock after ExecutionDoesNotExist (got: '${NEXT_STATE}', status=${STATUS})"

# Confirm the caught error name matches our single verified ErrorEquals string.
[[ "${ERROR_NAME}" == "Sfn.ExecutionDoesNotExistException" ]] \
  || fail "expected error=Sfn.ExecutionDoesNotExistException (got: '${ERROR_NAME}')"

echo "PASS: non-existent execution ARN caught as Sfn.ExecutionDoesNotExistException -> TakeoverAcquireLock"
