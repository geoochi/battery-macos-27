#!/bin/bash
# Argument checks must fail before any power-setting write, even on root CI.
set -euo pipefail
CLI=./build/battctl
"$CLI" --help
[[ $("$CLI" --version) == 'battctl 0.2.1' ]]
expect_usage() {
 local result=0
 "$CLI" "$@" >/dev/null 2>&1 || result=$?
 [[ $result == 2 ]] || { echo "Expected usage error: $* (got $result)" >&2; exit 1; }
}
for target in 19 100 70oops ''; do expect_usage hold "$target"; done
expect_usage hold
expect_usage hold 50 60
expect_usage restore extra
expect_usage verify 50 60
expect_usage monitor --json --json
expect_usage status 50
expect_usage doctor unknown
for command in hold-native verify-native native-limit watch run reset adapter-stop adapter-daemon adapter-guard; do
 expect_usage "$command"
done
echo 'CLI validation and removed-command rejection passed'
