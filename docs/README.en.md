# battctl v0.2.1 — native macOS charge limit

Save one target, restart normally if prompted, and let macOS charge or discharge
toward it and maintain it. No battery-control daemon, adapter switching or interval
cycling is included. Small normal fluctuations remain possible.

Experimental: writes are restricted to MacBookPro18,1 / macOS 27.0 build 26A428.
50% completed open-lid, closed-lid and sleep/wake validation. 70% has observed
charging-to-target and holding results. Other configurable values remain unverified.

## Install and use

```sh
git clone https://github.com/geoochi/battery-macos-27.git
cd battery-macos-27
make test
sudo ./scripts/install.sh
sudo battctl hold 50
# Save work and restart normally if the requested policy is not active.
battctl verify
```

For first use, stop other battery tools, enable native Charge Limit in Battery
settings, select 80%, and finish temporary charging overrides. The first supported
limit is backed up before changes. Installation alone does not change that limit.

**A saved target is not necessarily active. Until restart, macOS still uses the old
limit and may continue charging to it.** No reboot is performed automatically.
Keep AC connected and use the Mac normally; no CLI process or stress load is needed.
An unchanged saved/requested/active target needs no further restart.

## Commands

| Command | Purpose |
| --- | --- |
| `sudo battctl hold TARGET` | Save integer target 20–99 and report whether restart is needed |
| `battctl status [--json]` | Read battery percentage, current, power, AC and lid state |
| `battctl verify [TARGET] [--json]` | Verify saved or explicit native target; nonzero on failure |
| `battctl monitor [TARGET] [--json]` | Verify every 30 seconds; Ctrl-C does not affect the policy |
| `battctl doctor [--json]` | Native selection, effective limits, supported values and conflicts |
| `sudo battctl restore` | Restore the original backed-up limit and verify recovery |
| `battctl --help` / `battctl --version` | Help / version |

Use macOS Battery settings for temporary full charging. `near_target` describes
one sample, not proof of continuous holding. Unplugging allows normal battery use.

## Downloads and upgrades

[Releases](https://github.com/geoochi/battery-macos-27/releases) provide
`battctl-v0.2.1-macos-arm64.tar.gz` and `SHA256SUMS`:

```sh
shasum -a 256 -c SHA256SUMS
tar -xzf battctl-v0.2.1-macos-arm64.tar.gz
cd battctl-v0.2.1-macos-arm64
sudo ./scripts/install.sh
```

The binary is not Developer ID signed or notarized. Build from source if blocked;
do not disable Gatekeeper or SIP. Installation provides `/usr/local/bin/battctl`.
v0.2.0 targets and original backups are preserved. The installer also removes the
experimental controller from the abandoned development version, using its existing
recovery executable before deleting files. Restoring AC can resume charging under
the old native ceiling. Native preferences remain unchanged during cleanup.

Commands are now `hold` and `verify`; `hold-native` and `verify-native` only report
the new names. `watch`, `native-limit`, `run`, `reset` and adapter commands are removed.
Run `battctl doctor` after upgrading. No restart is required merely to upgrade the CLI.

## Restore, recording and uninstall

```sh
sudo battctl restore
./scripts/record-test.sh stop   # if enabled
sudo ./scripts/uninstall.sh
```

Keep the original backup at
`/Library/Application Support/battctl-reboot-test/previous-limit` for recovery.
The requested target is stored in `/Library/Preferences/com.geoochi.battctl.plist`.
Uninstall restores first; failure preserves the executable and recovery information.

Optional `./scripts/record-test.sh start|status|stop` provides read-only local
samples each minute while awake after login. It never controls charging or sleep.
Run `start` again after upgrading to update its binary. Logs remain in
`~/Library/Logs/battctl/`; remove private details before sharing them. No telemetry
is uploaded.

See [hardware validation](validation.md) and [technical notes](macos-27-battery.md).
Calibration, power supply limits, temporary charging overrides, OS updates and
other tools can change behavior. GPL-2.0; see [attribution](../THIRD_PARTY.md).
