# Hardware validation summary

This is a sanitized summary from **one device**, not a broad compatibility claim.
Personal usernames, local project paths, original event timestamps, unrelated
process activity, raw IORegistry data and individual sleep schedules are omitted.
Raw session logs are not distributed.

| Property | Tested value |
| --- | --- |
| Model identifier | MacBookPro18,1 |
| Chip | Apple M1 Pro |
| macOS | 27.0, build 26A428 |
| Firmware observed | 20457.1.29 |
| Target | 50% |
| Backend | PowerUI preference loading on normal restart |

## Observed results

1. After saving the backed-up preference and restarting, the enabled PowerUI
   selection and two effective manual charge-limit entries both reported 50.
2. With AC connected and the lid open, the battery naturally discharged from above
   target to 50. Subsequently its reported net current settled at zero.
3. At 50, open-lid use, closed-lid operation and reopening the lid retained 50,
   with AC present and no reported charging in the sampled interval.
4. Actual system sleep was confirmed independently in power-management events.
   Both open-lid and closed-lid sleep/wake scenarios retained 50 on wake, with the
   effective policy still active and reported net battery current zero.
5. Sleep windows included maintenance/background wakes; event records continued to
   report AC power and 50. These were not uninterrupted no-wake experiments.

The native policy continued independently of the read-only CLI recorder. No SIP,
system binary, forced service restart or sleep-setting changes were needed.

## Not established

- Compatibility with another model, chip, OS build or firmware.
- Long-term/multi-day holding and overnight behavior after reaching the target.
- The exact lower threshold at which charging resumes.
- Whether periodic system calibration charging overrides the experimental value.
- Continuous current or percentage during deep sleep; observations are sampled.
- Recovery from every power-loss, system-update or third-party-controller scenario.

Restoration was implemented with readback verification; this summary does not claim
that every new recovery branch has been exercised against live hardware. Unit tests
use synthetic/fake clients and do not change charging settings.

Contribute sanitized results via the compatibility issue template. Do not bypass
write restrictions merely to obtain a compatibility report; read-only reports are useful.
