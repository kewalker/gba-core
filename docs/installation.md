# Installation and use — GBA by BitBird 0.2.1

Install the versioned package from the repository Releases page when available.
BIOS and game files are not included. You need an Analogue Pocket, an SD card and your own GBA files.

## Firmware

Use current official Pocket firmware. The core declares a base minimum of 1.1;
the advertised original LCD/CRT display modes need OS 2.0 or later. The declared
minimum is not a claim that every feature was tested on every old firmware.
See [Analogue's OS 2.0 notes](https://www.analogue.co/support/pocket/firmware/2.0).

## Install

1. Back up the card, including Cores, Assets, Saves, Settings and Memories.
2. Extract `BitBird.GBA_0.2.1.zip` to a temporary directory on your computer.
3. Merge its `Cores`, `Platforms` and `Assets` folders into the card root. Merge
   matching folders; do not replace or erase whole card directories. Keep other
   cores and existing game/save data. The README, source information and license
   files in the ZIP are documentation, not extra files to put in the core folder.
4. Put your 16,384-byte BIOS at `Assets/gba/common/gba_bios.bin`.
5. Put uncompressed `.gba` or `.bin` games under `Assets/gba/common/`. Games up
   to 32 MiB are accepted. ZIP-compressed games and GB/GBC games are not supported
   by this GBA package.
6. Safely eject the card, start Pocket, open openFPGA, select GBA by BitBird and
   choose a game. The core folder is `Cores/BitBird.GBA`.

Example card layout:

```text
Cores/BitBird.GBA/core.json
Cores/BitBird.GBA/bitstream.rbf_r
Cores/BitBird.GBA/icon.bin
Platforms/gba.json
Assets/gba/common/gba_bios.bin
Assets/gba/common/My Game.gba
```

The common BIOS path follows the package's slot flags: its BIOS slot is not
core-specific. Folder rules are documented by Analogue in
[SD folder structure](https://www.analogue.co/developer/docs/openfpga/directories-and-sd-folder-structure)
and [data slots](https://www.analogue.co/developer/docs/openfpga/core-definition-files/data-json).

## Playing cartridges

From 0.3.0 the core can play a Game Boy Advance Game Pak inserted in the
Pocket. Open GBA by BitBird and choose **Play Cartridge** in the file browser.
A "Loading..." bar shows while the game is copied from the cartridge; the GBA
BIOS logo follows. The BIOS is still needed at `Assets/gba/common/gba_bios.bin`.

The game runs with BitBird's features, including Memories, fast-forward and
the overlays.

**Saves.** Save in the game as usual. About 10 seconds after the game saves,
and again before you quit, the core writes the change back to the cartridge,
so the same save also works in the Pocket's own cartridge mode and on a GBA.
Quitting waits for a write in progress. Loading a Memory does not change the
cartridge until the game saves again.

Supported cartridge save types: SRAM, 64 KiB Flash (Macronix, SST, Panasonic),
128 KiB Flash (Macronix, Sanyo), and 512 B and 8 KiB EEPROM.

**Backups.** Before its first write in a session, the core copies the
cartridge's save to `Saves/gba/BitBird.GBA/<CODE>-NN.sav` (`<CODE>` is the
game's four-letter code, such as `BPRE`) and reads the copy back. It keeps the
last eight, `-00` to `-07`; `<CODE>-bk.idx` records which is next. To restore
one, write it to the cartridge with a cartridge save tool.

If a cartridge can't take a save, for example a Flash chip the core does not
write or a dirty contact it detects, the core leaves the cartridge untouched
and saves the session to `Saves/gba/BitBird.GBA/<CODE>-unsaved.sav`.

**Tips.** Clean the cartridge contacts if a game does not start. Carts with a
clock (such as Pokémon Ruby, Sapphire and Emerald) use BitBird's clock, which
is kept in the game's `.gbkstat` file like any other game.

## Controls and settings

Pocket A/B, L/R, Start, Select and the D-pad provide the corresponding GBA
controls. Hold X for fast-forward, or enable the Fast-forward checkbox in the
core settings. Select 1.5x, 2x or Max separately; Max is workload-dependent and
is not a guaranteed fixed game speed. Fast-forward mute is optional and defaults
off. The checkbox, selected speed and mute preference are persistent settings.

Clock, session time and total playtime overlays can be enabled independently,
with six positions. They are optional and are not substitutes for the cartridge
RTC. Pocket's Display Mode menu provides the enabled LCD/CRT effects; these do
not change the GBA core's native 240x160, 3:2 output. Frame-blending controls,
where offered, belong to Pocket's display mode rather than a core checkbox.

## Saving, Memories and sleep

Use each game's normal save function. Leave the core normally and allow saving
to finish before removing the card or powering off. The framework writes game
saves under `Saves/gba/common/`, mirroring the chosen game's subfolders/name.
Playtime/RTC sidecars use `.gbkstat`; keep them beside their corresponding saves.
Do not rename or discard them just because the core is called BitBird.GBA.

Pocket Memories/save states and sleep/wake are supported in reported tests.
They serve a different purpose from the game's own save file; keep ordinary
in-game saves and card backups. Do not assume Memories from another core or old
development identity will load correctly in this core.

## Updating

For a BitBird.GBA update, back up first and replace only the supplied package
files. Retain Assets, Saves, Settings and Memories. Updating from 0.1.x keeps
existing saves, settings, Memories and `.gbkstat` playtime/RTC sidecars.

## Troubleshooting and rollback

- Missing BIOS: check the common-folder path, exact filename and 16 KiB size.
- Missing game: use an uncompressed GBA file of a supported size/extension.
- Missing display choices: check firmware and that the supplied video.json was
  copied. The display menu was reported working during development; not every
  visual option or persistence edge case has been tested.
- Save problem: preserve your existing save before experimenting, and record
  whether the issue concerns an in-game save, Memory, or sleep/wake.
- Rollback: restore the backed-up core files and matching settings. Preserve
  newer saves separately before restoring any older save backup.

Report issues with version, firmware, game title/region, settings and clear
reproduction steps. Do not attach commercial ROMs, BIOS dumps or private saves.
See [known issues](known-issues.md) for the current scope of support.

Playtime overlays show days, hours and minutes, hiding days below 24 hours.
Wall time remains HH:MM. The displayed maximum remains 416d 15h 59m.
