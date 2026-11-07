# Changelog

## 0.1.0 — 2026-11-07

Initial public release of GBA by BitBird, based on the hardware-tested candidate.
Includes persistent fast-forward enable/speed/mute settings, adaptive Max pacing,
game saves and RTC, Memories and sleep/wake, and clock/playtime overlays. Adds
the requested Pocket display-mode menu through metadata. Preserves the tested
FPGA image from the accepted playtime candidate. Exported FPGA build inputs
match that qualified candidate byte for byte. The updated standalone checkout
has not been independently recompiled; the November 4 baseline had that separate
rebuild check. See docs/build-validation.md for the current qualification scope.

Source, build/install instructions, credits and licenses accompany the release. Known limitations are documented, including experimental cable
support and incomplete all-game/device coverage. No beta suffix is used.

Playtime uses explicit day/hour/minute units, with decimal digit lookup in
spare block RAM. Day rollover is simulation-covered but was not waited out
on hardware; the user accepted the visible format.
