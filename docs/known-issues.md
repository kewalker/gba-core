# Known limitations — 0.2.1

- Compatibility is supported by the reported hardware tests and development
  regressions, not an exhaustive all-games claim. CPU, video, audio and unusual
  save-device edge cases remain possible.
- Fast-forward speed depends on workload. Max uses adaptive pacing and is not
  a fixed multiplier or a promise to beat 2x in every game or scene. In
  CPU-saturated scenes the fixed 1.5x and 2x speeds can show little gain,
  because the game drops to every other frame; Max adapts instead.
- Save states and sleep/wake have positive user test reports. Cross-core and
  cross-identity Memories are unverified. Preserve normal game saves.
- Cartridge RTC has positive reports, but rare cartridge peripherals and all
  calendar/offline edge cases have not been exhaustively checked.
- Pocket display-mode availability depends on firmware. The added menu was
  reported working; every effect's visual behavior, blending control and
  sleep/power persistence has not been separately established.
- Dock support is enabled in metadata. Broad controller/peripheral acceptance
  is not established by the handheld tests.
- The portable build has been tested on Windows with Quartus Lite 18.1. Linux
  builds and a complete portable functional regression suite remain unverified.

- Play Cartridge (0.3.0, draft): Atmel 64 KiB Flash cartridges are played but
  not written; their saves go to `<CODE>-unsaved.sav`. Cartridges with a clock
  use BitBird's clock rather than the cartridge's, so in-game time can differ
  from the Pocket's own cartridge mode.

See [validation](build-validation.md) for the build, simulation and hardware test scope.
