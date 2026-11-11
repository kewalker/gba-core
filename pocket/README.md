# GBA by BitBird — 0.1.2

Game Boy Advance compatible openFPGA core for Analogue Pocket.

Merge the supplied Cores, Platforms and Assets folders into your Pocket card.
Back up first; do not replace entire card folders or erase existing saves.
Place your own 16 KiB BIOS at Assets/gba/common/gba_bios.bin and uncompressed
GBA games under Assets/gba/common. BIOS, games and saves are not included.

See [installation and controls](docs/installation.md), [known limitations](docs/known-issues.md). Core identity is BitBird.GBA; logo EZ.
Pocket OS 2.0+ is needed for the advertised LCD/CRT display-mode features.

Hold X for fast-forward or use the persistent menu checkbox. Choose speed and
optional mute in core settings. Use the game's normal saves and keep backups;
Pocket Memories and sleep/wake serve a different purpose.

[LICENSE](LICENSE) contains GPL version 3. It applies to project-authored material
as described in [license scope](LICENSE-SCOPE.md). Analogue and Intel/Altera
files retain their existing terms; see [credits/notices](THIRD_PARTY_NOTICES.md).
See [SOURCE.md](SOURCE.md) for the matching source commit and companion archive.
The package is provided without warranty. Cable multiplayer remains experimental.
