# battery-macos-27 · battctl

[中文](../README.md) · [Releases](https://github.com/geoochi/battery-macos-27/releases)

An experimental native CLI that lets macOS discharge a plugged-in MacBook to 50%
and retain the charge limit across normal use and sleep. Objective-C/C, Foundation
and IOKit; no third-party runtime or continuously running charge controller.

## Compatibility comes first

**50% staging is restricted to MacBookPro18,1 (M1 Pro), macOS 27.0 build 26A428.**
Firmware 20457.1.29 was observed on the tested device. Other model/build pairs are
rejected for new 50% preference writes; there is no force flag. Read-only commands
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

Alternatively, download `battctl-v0.1.0-macos-arm64.tar.gz` and `SHA256SUMS` from
[Releases](https://github.com/geoochi/battery-macos-27/releases), then:

```sh
shasum -a 256 -c SHA256SUMS
tar -xzf battctl-v0.1.0-macos-arm64.tar.gz
cd battctl-v0.1.0-macos-arm64
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
3. Run `sudo battctl hold 50`. The original supported limit is backed up before
   the experimental preference is written. An already active 50% policy is a no-op.
4. When instructed, save your work and restart the Mac normally. The CLI never
   initiates a reboot or forcibly restarts a protected system service.
5. Run `battctl verify` and optionally `battctl monitor`. Normal use discharges the
   battery naturally; no CPU stress workload is necessary.

`policy=active` requires the PowerUI selection and effective `pmset` manual-limit
entries to agree on 50%. A successful preference write alone is not verification.
`monitor` runs every 30 seconds; Ctrl-C stops observation without removing the limit.
`near_target` describes a sample, not proof of sustained holding.

## Commands

| Command | Purpose |
| --- | --- |
| `status [--json]`, `watch [--json]` | Battery telemetry, once or every five seconds |
| `verify [--json]`, `monitor [--json]` | Effective 50% policy and battery flow, once or every 30 seconds |
| `doctor` | Native policy and legacy diagnostic information |
| `native-limit [80]` | Query or set an ordinary supported native limit |
| `hold 50` | Stage the experimental persistent limit; sudo required for writing |
| `restore` | Restore the original backed-up limit; sudo required |

Prefix each with `battctl`. `verify` exits nonzero when the 50% policy cannot be
verified. The current ordinary setter offers 80/85/90/95/100; `native-limit 50` is
rejected. Use `hold 50` for the separate preference-loading path. Legacy `run` and
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
  sampling job. It can sample during background wake, does not prevent sleep and
  does not control charging. Logs append in `~/Library/Logs/battctl/`; stop and
  clean them up when finished. Stopping recording does not remove the limit.
- The CLI has no network requests or telemetry uploads. Logs can reveal timestamps,
  paths and usage patterns; redact them before sharing. Do not upload full system
  logs or IORegistry dumps. Private session data is excluded from the repository.

See [technical notes](macos-27-battery.md), [contributing](../CONTRIBUTING.md),
[third-party attribution](../THIRD_PARTY.md), and [GPL-2.0](../LICENSE).
