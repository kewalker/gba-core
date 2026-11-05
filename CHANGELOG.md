# Changelog

## 0.1.0

Initial public release of GBA by BitBird, based on the hardware-tested candidate.
Includes persistent fast-forward enable/speed/mute settings, adaptive Max pacing,
game saves and RTC, Memories and sleep/wake, and clock/playtime overlays. Adds
the requested Pocket display-mode menu through metadata. Preserves the tested
FPGA image; standalone compilation reproduces it byte for byte.

Source, build/install instructions, credits and licenses accompany the release. Known limitations are documented, including experimental cable
support and incomplete all-game/device coverage. No beta suffix is used.

Playtime uses explicit day/hour/minute units, with decimal digit lookup in
spare block RAM. Day rollover is simulation-covered but was not waited out
on hardware; the user accepted the visible format.
