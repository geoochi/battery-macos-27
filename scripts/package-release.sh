#!/bin/bash
# Run after committing: package only Git-tracked public source plus a fresh binary.
set -euo pipefail
[[ $# == 0 ]] || { echo 'Usage: package-release.sh' >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ $(uname -s) == Darwin && $(uname -m) == arm64 && $(sw_vers -productVersion) == 27.* ]] || { echo 'Build release binaries on Apple silicon / macOS 27.' >&2; exit 1; }
[[ -z $(git status --porcelain --untracked-files=no) ]] || { echo 'Commit tracked changes before packaging.' >&2; exit 1; }
make all
VERSION=$(./build/battctl --version)
VERSION=${VERSION#battctl }
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version.' >&2; exit 1; }
NAME="battctl-v$VERSION-macos-arm64"
mkdir -p dist
[[ ! -e "dist/$NAME" ]] || { echo 'Release staging directory already exists; inspect/remove it before rebuilding.' >&2; exit 1; }
mkdir "dist/$NAME"
git archive HEAD | tar -xf - -C "dist/$NAME"
mkdir -p "dist/$NAME/build"
install -m 755 build/battctl "dist/$NAME/build/battctl"
git rev-parse HEAD > "dist/$NAME/SOURCE_COMMIT"
COPYFILE_DISABLE=1 tar -czf "dist/$NAME.tar.gz" -C dist "$NAME"
(cd dist && shasum -a 256 "$NAME.tar.gz" > SHA256SUMS)
printf 'Release archive: dist/%s.tar.gz\nChecksum: dist/SHA256SUMS\n' "$NAME"
