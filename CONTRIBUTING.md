# Contributing

Build with Apple's Command Line Tools on macOS:

```sh
make test
```

Tests must not write battery settings or require root. A CI pass confirms compilation
and software checks; it does not validate a new hardware/OS combination.

For changes to charging behavior, explain the trigger, before/after behavior,
readback checks and recovery path. Preserve the original backup. Keep preference
staging, active-policy verification and measured holding separate. Do not add an
unverified model/build to the write allowlist solely because a read-only API succeeds.
Do not introduce SIP changes, system-process injection or automatic reboots.

## Compatibility reports

Use the GitHub issue template. Include only the model identifier (not serial number),
macOS version/build, CLI version, command and redacted result. Describe lid, adapter
and sleep state without precise personal schedules. Do not post full IORegistry,
`pmset -g log`, user-directory paths, credentials or raw recorder files.

Repository history must not include local `research/`, logs, private configuration
or compiled artifacts. Use your GitHub noreply address if you want your personal
email excluded from commits. Changes are distributed under the project GPL-2.0
license; preserve third-party attribution.

## Release preparation

Maintainers update `Sources/version.h`, run `make test`, commit, then run
`./scripts/package-release.sh` on Apple silicon/macOS 27. It packages the committed
source, CLI, license, documentation and a SHA-256 checksum. Tag that exact commit;
publish as a prerelease until compatibility is established more broadly.
