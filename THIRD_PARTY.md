# References and attribution

This project is distributed under GPL-2.0; the complete license is in [LICENSE](LICENSE).

The AppleSMC packet layout and transport in `Sources/smc.h` were adapted from
[charlie0129/gosmc](https://github.com/charlie0129/gosmc), commit
`36c917295717bb50f098b591843eb23b4ca699dd` (GPL-2.0).

The legacy charge keys, little-endian firmware thresholds and activation sequence
follow [charlie0129/batt](https://github.com/charlie0129/batt), commit
`ee86539e977049d9f15d2641f4545c17eabf679f` (GPL-2.0).
These projects and their contributors retain their respective copyrights.

The native preference backend, policy verification, telemetry, lifecycle and CLI
integration were written for this project. No Apple or commercial battery-app
binaries, disassemblies or proprietary source are redistributed. Foundation, IOKit
and the private PowerUI framework are loaded from the user's installed macOS.

The adapter-switch approach references [batt PR #154](https://github.com/charlie0129/batt/pull/154),
head `5b15f980e2678270c9e78862c0c2018c024fff07`, by tr3mo and upstream contributors.
The adaptive policy and Objective-C controller/guard integration were implemented
for this project; the upstream Go daemon was not vendored.
