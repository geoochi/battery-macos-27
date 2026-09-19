# References and attribution

This project is distributed under GPL-2.0; see [LICENSE](LICENSE).
The native preference backend, verification, telemetry and CLI were written for
this project. Foundation, IOKit and the private PowerUI framework are loaded from
the user's installed macOS. No Apple or commercial battery-app binaries,
disassemblies or proprietary source are redistributed.

Historical experimental revisions used the AppleSMC transport from
[charlie0129/gosmc](https://github.com/charlie0129/gosmc) and charge-control approaches
from [charlie0129/batt](https://github.com/charlie0129/batt), under GPL-2.0.
Those contributors retain their copyrights in the historical revisions. The current
native-only source no longer includes the SMC transport or adapter controller.
