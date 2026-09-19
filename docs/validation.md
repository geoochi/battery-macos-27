# Hardware validation

Results come from one device and are not a broad compatibility claim.
Personal paths, original timestamps, device serials, raw IORegistry dumps and
individual sleep schedules are omitted. Raw session logs are not distributed.

| Property | Value |
| --- | --- |
| Model | MacBookPro18,1 / Apple M1 Pro |
| macOS | 27.0, build 26A428 |
| Firmware observed | 20457.1.29 |
| Backend | Native PowerUI preference loading on normal restart |

## Observed native behavior

- At 50%, PowerUI and two active manual-charge-limit entries agreed after restart.
- With AC connected, battery charge declined to 50%, then reported net current
  settled at zero. Open-lid use, closed-lid use and reopening retained the target.
- Both open-lid and closed-lid sleep/wake tests retained 50%. Power-management events
  confirmed actual sleep, including some maintenance wakes. Samples after wake
  retained the native policy and reported zero net current.
- Changing to 70% required a normal restart in the observed test. The battery then
  charged to 70% and held there during awake use. This is not a complete repeat of
  the 50% sleep/wake validation at 70%.
- After returning to 50% and restarting, both effective manual-limit entries and
  PowerUI again reported 50%; the battery was observed discharging toward it with
  AC connected and the lid closed.

The native policy continued without a battery-control daemon. No SIP changes,
protected-service restarts or sleep-setting changes were needed.

## Not established

- Other models, chips, OS builds or firmware, or every configurable target.
- Exact lower replenishment thresholds, lifetime effects or indefinite exact percentage.
- Whether system calibration charging overrides an experimental target.
- Continuous current during deep sleep or recovery from every power-loss/update case.

Tests cover configuration parsing, saved intent, replacement of pending targets,
partial writes and rollback, native API failures, policy verification and CLI argument
rejection. They use fake clients for writes and do not alter charging settings.
