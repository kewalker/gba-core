# Known limitations — 0.1.2

- Compatibility is supported by the reported hardware tests and development
  regressions, not an exhaustive all-games claim. CPU, video, audio and unusual
  save-device edge cases remain possible.
- Fast-forward speed depends on workload. Max uses adaptive pacing and is not
  a fixed multiplier or a promise to beat 2x in every game or scene.
- Link-port/multiplayer logic is experimental. Real cable/game interoperability
  is not release-qualified; enabling the port does not establish compatibility.
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

The v0.1.1 image matches the candidate smoke tested on Pocket with Wario Land 4.
See [validation](build-validation.md) for the tested scenes and DMA paths.
