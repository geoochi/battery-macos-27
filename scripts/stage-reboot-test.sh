#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ $# -le 1 ]] || { echo 'Usage: stage-reboot-test.sh [TARGET]' >&2; exit 2; }
exec "$ROOT/build/battctl" hold-native "${1:-50}"
