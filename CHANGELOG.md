# Changelog

## 0.3.0 — unreleased (draft)

Play GBA cartridges directly. Insert a Game Boy Advance Game Pak and choose
**Play Cartridge** in the Pocket's file browser: the core reads the game from
the cartridge and plays it with BitBird's features, including Memories,
fast-forward and the playtime overlays.

- **Any cartridge**: the core reads the header, measures the ROM size and
  detects the save type from the cartridge itself, so it needs no game list.
  ROMs up to 32 MiB are supported.
- **Saves go back to the cartridge automatically** about 10 seconds after the
  game saves, and before you quit. Supported save types: SRAM, 64 KiB Flash
  (Macronix, SST, Panasonic), 128 KiB Flash (Macronix, Sanyo) and EEPROM
  (512 B and 8 KiB).
- **Backups on the SD card**: before the first write of each session, the
  cartridge's save is copied to `Saves/gba/BitBird.GBA/<CODE>-NN.sav` and read
  back. The last eight are kept.
- **Nothing is lost**: if a cartridge can't take a save (an unsupported Flash
  chip, or a contact problem the core detects), the session is saved to
  `Saves/gba/BitBird.GBA/<CODE>-unsaved.sav` instead.
- **Loading screen**: a "Loading..." progress bar is shown while the cartridge
  is copied.

Tested with Pokémon FireRed (128 KiB Flash), Golden Sun (64 KiB Flash), Final
Fantasy I & II: Dawn of Souls (SRAM) and The Legend of Zelda: The Minish Cap
(EEPROM), including Memories in cartridge games.

Sound state in Memories is now saved bit-serially, which frees FPGA space;
Memories from 0.2.x still load. Saves, settings, Memories and playtime/RTC
sidecars from 0.2.x carry over unchanged.

## 0.2.1 — 2026-11-20

Fix The Legend of Zelda: The Minish Cap: Link can Roll with R while walking,
and a New Game no longer goes to a black screen after the opening cutscene.

- **BIOS read protection**: code running outside the BIOS now reads the last
  opcode the BIOS fetched, not the BIOS contents, as on a GBA. The Minish Cap
  relies on this to offer Roll.
- **Open bus**: reads of unmapped memory return the most recently fetched
  opcode instead of zero. After its New Game cutscene The Minish Cap reads
  animation data from such an address, and zeros made it loop forever.
- **ARM halfword loads**: LDRH from an odd address returns the aligned
  halfword rotated by 8 bits, and LDRSH from an odd address loads the
  addressed byte sign-extended, as on an ARM7TDMI.

Saves, settings, Memories and playtime/RTC sidecars from 0.2.0 carry over
unchanged.

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
early hand-offs, and the link lines use weak pull-ups. Tested by trading in
Pokémon Emerald between an Analogue Pocket and a Game Boy Advance SP.

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
