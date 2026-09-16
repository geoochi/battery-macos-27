# Changelog

## 0.2.0 — configurable experimental targets

- `hold TARGET` accepts integers 20–99, including 70; 100 remains the ordinary
  `native-limit 100` full-charge operation.
- Save requested intent separately from active policy; `verify` and `monitor`
  follow it by default or accept an explicit target. Legacy default remains 50.
- Preserve the original backup while replacing targets, including pending requests;
  roll back the previous saved preference and requested intent on partial failures.
- Update existing optional recorders when their start script is run again.
- Only 50% has completed hardware testing; all other targets remain experimental.

## 0.1.0 — experimental prerelease

- Persistent 50% preference staging with an original-limit backup and manual restart.
- Native/effective policy verification, telemetry, monitoring and restoration.
- Verified on one MacBookPro18,1 / M1 Pro / macOS 27.0 build 26A428, including
  discharge to target and open/closed-lid sleep/wake retention.
- Model/build write guard, readback checks and fake-client regression tests.
- Chinese/English installation and recovery guides, sanitized validation summary,
  optional local recorder, macOS CI and source-inclusive arm64 release packaging.

Other models/builds, multi-day stability, recharge threshold and calibration
charging are not established. This release is not Developer ID signed or notarized.
