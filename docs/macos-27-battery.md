# Technical notes: configurable native charge limits on macOS 27

## Two separate interfaces

The tested PowerUI framework exposes `PowerUISmartChargeClient`. Its ordinary
manual charge-limit setter accepts the provided 80/85/90/95/100 values and rejects
50 on the tested build. `native-limit` deliberately follows that supported list.

The successful experiment instead backed up the root preference
`com.apple.smartcharging.topoffprotection / mclLimitValue`, saved integer 50, and
restarted normally. After restart, both PowerUI and the system's effective
`manualChargeLimit` entries reported 50. Charge Limit must already be enabled
(`MCLFeatureState=1`). A preference-change notification alone did not reload 50.

`hold-native TARGET` implements this preference path for integers 20–99 only on the model/build pair tested.
It does not alter system binaries, private entitlements or SIP, kill system
services, or reboot automatically. The root-owned original-limit backup is retained
for restoration and retries. The internal backup directory keeps its original
`battctl-reboot-test` name for compatibility with early local versions.

This is a private implementation detail, not a stable public Apple API. Changes
in PowerUI, preference semantics or firmware can invalidate it.

## What verification means

`verify` reads battery telemetry from AppleSmartBattery/IOPMrootDomain, queries
PowerUI and parses `pmset -g battlimit`. It requires an enabled selection of the requested target and
at least one effective manual limit at that target, with no conflicting active manual entry.
It does not equate a saved preference with an active limit, or an active limit with
long-term measured stability. A single near-target sample is labeled `near_target`.

IORegistry may encode negative current as an unsigned 64-bit number; telemetry
converts it back to signed current. Negative battery power indicates discharge;
zero is the reported net-current sample, not a direct measurement of adapter output.
Other monitoring apps' bus sensor names are not assumed equivalent to these fields.

A user-space monitor does not run continuously in deep sleep. System sleep/wake
logs and before/after telemetry establish retention over tested cycles, not the
absence of every transient change while asleep.

## Requested intent and target changes

The root-owned `/Library/Preferences/com.geoochi.battctl.plist` stores the requested
integer target, separately from PowerUI's active selection and the original-limit
backup. Default verification reads this file on every sample. An explicit CLI target
overrides it for that read only; absence preserves the legacy default of 50. Invalid
or unsafe metadata fails verification instead of silently accepting the active value.

Changing from an experimental 50 to 70 is allowed with a valid original backup.
A target change can replace a pending request before restarting. The transaction
writes and verifies the system preference, then atomically saves and reads back the
requested-target file. Failure attempts to restore both the immediately previous
saved preference and previous requested intent, retaining the original backup.
A process or system crash between the two files is not an atomic cross-file operation;
verification can report a mismatch, and re-running the intended hold-native command repairs
saved intent. Successful restore clears requested intent after verifying recovery.

Only 50 has completed hardware validation. Configurable-target unit tests establish
software behavior, not that every value is accepted and held by the firmware.

## Earlier SMC and IOPS attempts

The known `bfF0` / `bfD0` / `bfE0` firmware-limit path and private IOPS registration
returned `kIOReturnNotPrivileged` even as root on the tested firmware. Legacy
`CH0B`/`CH0C`/`CHTE` were unavailable. Readable adapter-control keys alone are not
sufficient to safely discharge and hold a target.

The legacy SMC code remains attributed and isolated behind explicit `run`/`reset`
commands. It is not installed as a daemon and is not the recommended public release
workflow. No claim is made that it works on this macOS 27 firmware.

## Primary references

- [Apple: Charge Limit and Optimized Battery Charging](https://support.apple.com/en-au/102338)
  — official native behavior; the documented UI does not offer 50%.
- [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
  — official release changes, not an API contract for this private path.
- [IOPowerSources.h](https://developer.apple.com/documentation/iokit/iopowersources_h)
  — public power-source status APIs.
- [Apple sleep/wake notifications](https://developer.apple.com/library/archive/qa/qa1340/_index.html)
  — system power notifications and sleep behavior.
- [batt issue #152](https://github.com/charlie0129/batt/issues/152)
  — upstream reports of charge-control permission restrictions on newer firmware.
- [batt compatibility](https://github.com/charlie0129/batt#compatibility)
  — upstream compatibility information; older beta support is not proof for later builds.

[Sanitized device validation](validation.md) · [attribution](../THIRD_PARTY.md)

## Adapter control (0.3.0-dev)

The opt-in adapter idea in [upstream PR #154](https://github.com/charlie0129/batt/pull/154)
(head `5b15f980e2678270c9e78862c0c2018c024fff07`) was tested separately on the
listed device: CHIE=8 read back successfully, the battery supplied approximately
12 W during a bounded pulse, and CHIE=0 restored AC with reported net current
returning to zero after telemetry refreshed. This does not unlock the gated charge
inhibit or firmware threshold keys. Both service names AppleSMC and
AppleSMCKeysEndpoint resolve to the same entry on this device.

`hold` now installs a root-owned controller and configuration in
`/Library/Application Support/battctl-adapter`; `hold-native` retains the reboot
path. The controller restores CHIE on lid closure, sleep, errors and exit. A separate
heartbeat guard holds a duplicate of the controller flock, so replacement cannot
race recovery. It restores on pipe EOF or heartbeat loss, and registers its own
sleep callback. Launchd abandons the controller process group on termination so
recovery can finish independently; abnormal controller exits restart with throttling.
The guard retries restoration failures while retaining the lock. This cannot promise
recovery from every kernel/firmware failure or simultaneous termination of both
processes. No protected services are restarted or patched.

Polling occurs approximately every two seconds, but SMC writes are skipped when the
value already matches. Band adaptation occurs only after complete cycles, bounded
at 5–10 percentage points below the requested ceiling. Sleep/unplug pauses reset
cycle timing. Native limits and the user's original backup are not rewritten.
Status distinguishes controller health from sampled battery behavior; an active
software policy does not establish continuous exact holding or sleep retention.
