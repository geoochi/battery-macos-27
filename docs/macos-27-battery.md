# Native charge-limit implementation

## One workflow

`hold TARGET` saves an integer target from 20 to 99 into the system's native
manual-charge-limit preference. When the running service has not loaded that target,
a normal user-initiated restart is required. Before that restart the old policy
remains in effect, including any charging it permits.

On the tested MacBookPro18,1 / 26A428, loading experimental sub-80 targets at boot
works even though the ordinary PowerUI setter advertises only 80/85/90/95/100.
This is a private preference path, not a supported Apple API contract. Writing a
preference alone is never considered proof that the policy is active.

The CLI does not control adapter power, access AppleSMC, install a charging daemon,
prevent sleep, restart protected services or require SIP changes. Once loaded,
macOS owns the policy independently of the CLI. Current source contains only the
native backend; the installer retains a cleanup path for an earlier development
controller and calls that old controller's recovery executable before removing it.

## Persistence and recovery

Root writes `mclLimitValue` in `com.apple.smartcharging.topoffprotection`.
The native feature must already be enabled and temporary overrides finished.
Writes are restricted to the tested model/build pair; unsupported systems fail closed.

The first supported original value is stored in the root-only file
`/Library/Application Support/battctl-reboot-test/previous-limit` and never replaced
by later experimental targets. Keep that historical path for existing installations.
The user-requested target is stored separately in
`/Library/Preferences/com.geoochi.battctl.plist`, root-owned and readable by ordinary
users. Absence preserves the v0.1.0 default target of 50; malformed metadata fails
verification instead of silently adopting the running native limit.

A preference lock serializes updates. A target change writes and verifies the system
preference, then atomically saves and reads back the requested-target metadata.
Failure attempts to restore both immediately previous values, not the original
backup. A system crash between the two files is not an atomic cross-file transaction;
re-running the intended `hold` request repairs saved intent. A pending target can
be replaced before restart, including cancellation back to the active target.

`restore` saves the original supported value and uses the native setter, then checks
actual policy readback before clearing requested-target metadata. The original
backup is retained for retries. Failed restoration leaves recovery information intact.

## Verification

PowerUI selection/enabled state and all active `pmset -g battlimit` manual-limit
entries must agree with the requested target. A saved setting, a matching percentage,
or one zero-current reading alone is insufficient. `No battery level limits set`
is a valid empty result and is reported as an unverified policy, not a parsing error.
Other malformed or unsupported output remains an error.

Telemetry reads IORegistry without dumping identifying battery data. Current is
interpreted as signed even when represented by an unsigned NSNumber. Power is
estimated from current × voltage, not measured directly at the adapter. Readings can
lag, and deep sleep suspends sampling. `near_target` describes a single observation.

## Primary references

- [Apple: Charge Limit and Optimized Battery Charging](https://support.apple.com/en-us/102338)
- [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
- [IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h)

[Sanitized validation](validation.md) · [Attribution](../THIRD_PARTY.md)
