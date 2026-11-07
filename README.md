# GBA by BitBird

A Game Boy Advance compatible openFPGA core for Analogue Pocket. Version
**0.1.0**, package identity **BitBird.GBA**, logo **EZ**.

## Features

- Game saving and RTC persistence.
- Pocket Memories/save states and sleep/wake, supported in reported tests.
- Hold-X or menu-controlled fast-forward: 1.5x, 2x and workload-dependent Max.
- Persistent fast-forward enable, speed and optional mute settings.
- Optional clock, session-time and total-playtime overlays with six positions;
  playtime uses days/hours/minutes, hiding days below 24 hours.
- Pocket LCD/CRT display modes for the native 240x160, 3:2 picture.

Cable multiplayer is experimental. See [known limitations](docs/known-issues.md)
for support boundaries; compatibility is not an exhaustive all-games claim.

## Installation

Use the versioned install ZIP from [Releases](https://github.com/kewalker/gba-core/releases)
when available. GitHub's generic source ZIP is for development. Supply your own
16 KiB GBA BIOS and uncompressed games; neither is included.
Follow [installation and controls](docs/installation.md).

Hold X for fast-forward or use the core-menu checkbox. Speed and optional mute
have separate persistent settings. Keep ordinary game saves and card backups.

## Building

Use Python 3.10+ and Quartus Prime Lite 18.1 with Cyclone V support.
The [build guide](docs/build.md) covers isolated builds and timing checks.
The exported build inputs exactly match the accepted image with all 21
timing/physical checks passing; see [validation](docs/build-validation.md).

`python scripts/package-release.py --output build/package-01 --repository-url https://github.com/kewalker/gba-core`

The packager requires a clean source commit and creates an install ZIP, matching
source export, checksums and a receipt in a fresh directory. It never installs,
uploads or publishes anything. Generated files remain under ignored build/.

## Credits and acknowledgements



GBA by BitBird was developed with help from the following framework, tools,
hardware documentation and reference projects:

- **Analogue** — [openFPGA framework and core template](https://github.com/open-fpga/core-template), including the Pocket APF shell and host/target bridge used in this project.
- **Intel / Altera** — Quartus tooling, generated FPGA IP and reference/support files included with the project.
- **Martin Korth and GBATEK contributors** — [GBA hardware documentation](https://mgba-emu.github.io/gbatek/) used throughout implementation and compatibility work; thanks also to the maintainers of its Markdown edition.
- **Arm** — ARM7TDMI technical documentation used for instruction behavior and timing research.
- **Jeffrey Pfau and mGBA contributors** — [mGBA](https://github.com/mgba-emu/mgba), consulted for memory, DMA, save-device and power-management behavior.
- **MiSTer GBA contributors, mincer-ray and wolfshow** — [MiSTer GBA](https://github.com/MiSTer-devel/GBA_MiSTer), [mincer-ray's Pocket port](https://github.com/mincer-ray/openfpga-GBA), and [wolfshow's Pocket fork](https://github.com/wolfshow/openfpga-GBA), inspected for architecture, cycle accounting, cache behavior and Pocket integration comparisons.
- **Stephen Stair** — [GBA communication hardware notes](https://www.akkit.org/info/gba_comms.html), consulted for experimental multiplayer work.
- **gbadev / gbadoc contributors** — [sound hardware documentation](https://gbadev.net/gbadoc/audio/sound4.html), consulted for PSG noise behavior.
- **pret and zeldaret contributors** — [pokeemerald](https://github.com/pret/pokeemerald), [pokefirered](https://github.com/pret/pokefirered) and [The Minish Cap reconstruction](https://github.com/zeldaret/tmc), consulted while investigating palette and save compatibility.
- **Alliance Memory** — device data sheets used in Pocket memory-interface timing work.

**AI disclosure:** I used LLMs to help with research and development.
All playtesting on the Analogue Pocket was done by people.

Included framework/IP files retain their original notices. The other projects
above are credited for documented reference use; this does not represent an
endorsement or establish a license for this repository. See
[third-party notices](THIRD_PARTY_NOTICES.md) for component scope and provenance.

## License

Project-authored material is **GPL-3.0-only**. See [LICENSE](LICENSE) and
[license scope](LICENSE-SCOPE.md). Analogue APF and Intel/Altera files retain
their applicable notices and terms. No warranty is provided.
