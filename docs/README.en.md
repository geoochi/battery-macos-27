# No-reboot adapter mode (0.3.0-dev source)

```sh
make test
sudo ./build/battctl hold 60
./build/battctl verify
sudo ./build/battctl adapter-stop
```

Open the lid and connect AC before starting. A root-owned launchd service continues
when the terminal closes. Users supply only a target. The internal band starts at
5 percentage points below it. After each complete cycle, a cycle under one hour
widens the band by one point; a cycle over three hours narrows it. Width is bounded
at 5–10 points. This cycles the battery; it does not park battery current at zero.
An already verified matching native ceiling is used instead of cycling.

Closing the lid or sleeping restores adapter power and pauses software control;
the existing native ceiling takes over and can be higher than the requested target.
Control resumes on open-lid wake. Native preferences and system sleep settings are
unchanged. The requested target cannot exceed the readable native ceiling.
Telemetry may lag and thresholds may overshoot slightly. While the adapter is cut,
both connection flags report disconnected; a real unplug cannot immediately be
distinguished. The guard restores adapter power after controller death or a lost
heartbeat; launchd restarts abnormal exits and loads the selected target at boot.

`verify` follows the active adapter controller; `verify-native` inspects the native
policy separately. `hold-native TARGET` retains the old reboot-based workflow.
`restore` stops adapter control before restoring the original native preference.
Updating the CLI alone does not replace a running controller: run `hold TARGET`
again after upgrading. Complete cycles, adaptation, and real sleep/lid recovery in
adapter mode still require hardware validation. Native sleep validation below does
not establish those properties for adapter mode.

**Published v0.2.0 has no adapter mode. Its `hold` command corresponds to the current
source's `hold-native`. Build current source for no-reboot control.**

---

# battery-macos-27 · battctl

[中文](../README.md) · [Releases](https://github.com/geoochi/battery-macos-27/releases)

An experimental native CLI with integer targets from 20 to 99%, using macOS to
apply the charge limit. Only 50% has completed hardware validation, including
discharge to target and retention across normal use and sleep. Objective-C/C, Foundation
and IOKit; no third-party runtime or continuously running charge controller.

## Compatibility comes first

**Target staging is restricted to MacBookPro18,1 (M1 Pro), macOS 27.0 build 26A428.**
Firmware 20457.1.29 was observed on the tested device. Other model/build pairs are
rejected for new target preference writes; there is no force flag. Read-only commands
may work on other versions, but private APIs can be unavailable or change.

This is an experimental prerelease, not an Apple-supported charging API. One Mac
passed reboot loading, discharge to 50%, open/closed-lid operation, and both
open-lid and closed-lid sleep/wake tests. Multi-day stability, the recharge threshold
and calibration charging remain unverified. See [validation](validation.md).

## Install from source (recommended)

Install Apple's Command Line Tools first if needed: `xcode-select --install`.

```sh
git clone https://github.com/geoochi/battery-macos-27.git
cd battery-macos-27
make test
sudo ./scripts/install.sh
battctl --version
```

Alternatively, download `battctl-v0.2.0-macos-arm64.tar.gz` and `SHA256SUMS` from
[Releases](https://github.com/geoochi/battery-macos-27/releases), then:

```sh
shasum -a 256 -c SHA256SUMS
tar -xzf battctl-v0.2.0-macos-arm64.tar.gz
cd battctl-v0.2.0-macos-arm64
./build/battctl --version
sudo ./scripts/install.sh
```

The binary targets Apple silicon/macOS 27. It is not Developer ID signed or
notarized. If macOS blocks it, build from source; do not disable Gatekeeper or SIP.
The installer puts the CLI in `/Library/Application Support/battctl/battctl` and
links `/usr/local/bin/battctl`. Use that full path if it is outside your PATH.
Installation and upgrades do not change battery settings or install a charge daemon.

## Enable 50%

1. Stop other battery controllers. Enable Apple's Charge Limit in System Settings,
   select 80%, and finish any temporary “charge to full” override.
2. Connect power. Check `sysctl -n hw.model`, `sw_vers -buildVersion`, and
   `battctl native-limit` against the supported configuration above.
3. Run `sudo battctl hold-native 50`. The original supported limit is backed up before
   the experimental preference is written. Matching saved, requested and active 50% values are a no-op.
4. When instructed, save your work and restart the Mac normally. The CLI never
   initiates a reboot or forcibly restarts a protected system service.
5. Run `battctl verify` and optionally `battctl monitor`. Normal use discharges the
   battery naturally; no CPU stress workload is necessary.

`policy=active` requires the PowerUI selection and effective `pmset` manual-limit
entries to agree on the requested target. A successful preference write alone is not verification.
`monitor` runs every 30 seconds; Ctrl-C stops observation without removing the limit.
`near_target` describes a sample, not proof of sustained holding.

## Change the target, for example to 70%

```sh
sudo battctl hold-native 70
# Save work and restart normally when prompted, then:
battctl verify       # follows the requested target saved by battctl
battctl verify 70    # explicitly verifies 70, not just any active limit
battctl monitor     # follows saved target changes on each sample
```

Accepted targets are integers 20–99. Use `native-limit 100` to allow full charging;
`hold 100` is rejected. `hold-native` always requires sudo to inspect the saved system preference as well as
active policy. New targets usually need a normal restart. If saved preference,
requested intent and active policy already agree, it does not write or need a restart. A saved 70 with an active 50 is
reported as unverified, with a nonzero `verify` exit status.

The original-limit backup is never replaced when switching targets. You may replace
a pending request before reboot or cancel it with `sudo battctl hold-native 50`.
Only 50 has completed hardware testing; 70 and other values remain unverified,
including whether increasing the target immediately charges to the new value.

Requested intent is stored in the root-owned, world-readable
`/Library/Preferences/com.geoochi.battctl.plist`. Legacy installations without this
file default to checking 50, not whatever value the system currently happens to use.
Successful `restore` clears this file; use `native-limit` to inspect the restored value.
After upgrading, run `./scripts/record-test.sh start` again to update an existing recorder.

## Commands

| Command | Purpose |
| --- | --- |
| `status [--json]`, `watch [--json]` | Battery telemetry, once or every five seconds |
| `verify [TARGET] [--json]`, `monitor [TARGET] [--json]` | Requested or explicit target policy and battery flow, once or every 30 seconds |
| `doctor` | Native policy and legacy diagnostic information |
| `native-limit [80]` | Query or set an ordinary supported native limit |
| `hold-native TARGET` | Stage an integer target from 20 to 99; sudo required |
| `restore` | Restore the original backed-up limit; sudo required |

Prefix each with `battctl`. `verify` exits nonzero when the requested policy cannot be
verified. The current ordinary setter offers 80/85/90/95/100; `native-limit 50` is
rejected. Use `hold-native TARGET` for the separate preference-loading path. Legacy `run` and
`reset` are retained for research compatibility and are not the supported workflow
on the tested firmware.

## Restore or uninstall

```sh
sudo battctl restore
# From the cloned or extracted project:
./scripts/record-test.sh stop  # if the optional recorder was enabled
sudo ./scripts/uninstall.sh
```

The first original limit is preserved in
`/Library/Application Support/battctl-reboot-test/previous-limit`. Do not delete it.
Uninstall restores first if a backup exists; a failed restoration retains the CLI
and backup. If never configured, uninstall removes the CLI without touching charge
settings. System Settings can also select an ordinary supported limit to exit the
experiment. If instructed after a restore failure, restart normally and recheck.

## Limits and privacy

- Stay connected to an adequate power supply. Unplugging, insufficient adapter
  power and battery estimates affect the observed percentage.
- System updates, “charge to full,” changed system limits and other controllers
  may override the policy. Check again with `verify` after changes.
- The program does not change SIP, system binaries, sleep settings or require the
  display to remain on. Native discharge may continue with the lid closed.
- No fixed 48–50% recharge band or permanent suppression of calibration charging
  is promised. Observe the first discharge and a sleep/wake cycle yourself.
- Optional `./scripts/record-test.sh start|status|stop` installs a per-user read-only
  sampling job that follows the saved target. It can sample during background wake, does not prevent sleep and
  does not control charging. Logs append in `~/Library/Logs/battctl/`; stop and
  clean them up when finished. Stopping recording does not remove the limit.
- The CLI has no network requests or telemetry uploads. Logs can reveal timestamps,
  paths and usage patterns; redact them before sharing. Do not upload full system
  logs or IORegistry dumps. Private session data is excluded from the repository.

See [technical notes](macos-27-battery.md), [contributing](../CONTRIBUTING.md),
[third-party attribution](../THIRD_PARTY.md), and [GPL-2.0](../LICENSE).
