# Changelog

## 0.2.0 — 2026-11-20

Fix an intermittent black screen at startup, before the BIOS logo. The core's
reset now reaches each internal clock domain through a synchronizer, so every
part of the emulated system leaves reset together; a new build audit checks
that no reset crosses a clock domain without one. Development testing saw this
hang in about 1 of 10 launches before the fix and none in 20+ launches after.

Add **Soft Colors**, an optional mild desaturation in the core menu. It is off
by default, persists, and switches at a frame boundary.

Improve physical link-cable multiplayer: the serial port keeps a fixed cable
clock while the CPU runs fast, handles delayed, missing and noisy peers and
early hand-offs, and the link lines use weak pull-ups. Cable multiplayer
remains experimental.

Run CPU-heavy scenes faster, which also helps fast-forward, by overlapping
instruction fetches. Fix ARM data-processing instructions that write the PC,
and tag instruction fetches with the correct width. Pause playtime while a
Memory is captured or loaded. Save states store only the defined window-control
bits. Shorten several graphics timing paths for build headroom.

Saves, settings, Memories and playtime/RTC sidecars (`.gbkstat`) carry over
from 0.1.x unchanged.

## 0.1.2 — 2026-11-11

Use **Game Boy Advance** as the shared platform display name (PR #1,
thanks to @davewongillies). Rebuild the full-feature FPGA image with Quartus
Prime Lite 18.1 and verify timing and all 21 physical audits.

## 0.1.1 — 2026-11-09

Fix black screens in Wario Land 4 at save selection and after the level entry
swirl. DMA now waits for palette RAM reads, acknowledges invalid reads from
the BIOS and unmapped range, and writes destinations on transfer completion.
The Pocket smoke test covered gameplay and fast-forward together.

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
