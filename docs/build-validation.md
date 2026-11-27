# 0.3.1 full-feature rebuild

Quartus Prime Lite 18.1 compiled the full-feature public FPGA source with
fitter seed 13. Minimum setup slack was +0.248 ns and minimum hold slack was
+0.082 ns. All 27 physical audits passed. The rebuilt bitstream matches the
hardware-tested development candidate byte for byte. See the
[0.3.1 build receipt](build-validation-0.3.1-receipt.json).

The only source change from 0.3.0 is the Play Cartridge playtime record. A
new simulation follows a wake: the game resumes, its playtime file arrives
while it plays, the saved total is kept and the time since waking is added,
and a late file for another game is still refused. The 52 cartridge
simulations, the RTC, persistence, overlay and data-table stages, the RTC and
playtime negative controls and the Memories machine roundtrip passed.

On Pocket, Dawn of Souls kept its saved playtime total across sleep/wake on
the identical image. Under 0.3.0 the same test reset the total to the time
played since waking.

# 0.3.0 full-feature rebuild

Quartus Prime Lite 18.1 compiled the full-feature public FPGA source, now
including Play Cartridge, with fitter seed 7. Minimum setup slack was
+0.387 ns and minimum hold slack was +0.078 ns. All 27 physical audits
passed: the 23 release audits plus the Game Pak header, boot-address, save
and EEPROM I/O audits. The rebuilt bitstream matches the hardware-tested
development candidate byte for byte. See the
[0.3.0 build receipt](build-validation-0.3.0-receipt.json).

Development simulation covered the cartridge profile, header, size probe,
save detection, writeback, backup ring and unsaved-session fallback paths
(53 cartridge simulations), the serial Memories sound registers, a state
load that arrives while the cartridge is still being copied, and mode-2 BG3
affine references rewritten every scanline. The graphics, affine, Memories
machine-roundtrip and PPU-resume suites passed with the BG3 change.

On Pocket, the development candidates wrote saves back to Pokémon FireRed
(128 KiB Flash), Golden Sun (64 KiB Flash), Final Fantasy I & II: Dawn of
Souls (SRAM) and The Legend of Zelda: The Minish Cap (EEPROM); Memories
resumed cleanly in cartridge and ROM games; a game kept running after its
cartridge was pulled, and a save made then went to `<CODE>-unsaved.sav` with
the cartridge untouched; and powering off shortly after a save loaded the
previous save without corruption. The final image adds sleep/wake for
cartridge games: Dawn of Souls resumed after waking, then slept and quit again
without errors. On the final image, the Final Fantasy I airship view drew
correctly at normal speed, and the cartridge regression games still worked.

# 0.2.1 full-feature rebuild

Quartus Prime Lite 18.1 compiled the full-feature public FPGA source with
fitter seed 31. Minimum setup slack was +0.590 ns and minimum hold slack was
+0.111 ns. All 23 physical audits passed, including the reset clock-domain
audit. The rebuilt bitstream matches the development candidate byte for byte.
See the [0.2.1 build receipt](build-validation-0.2.1-receipt.json).

Development simulation covered the ARM and Thumb CPU benches, including a new
check of word, halfword and signed loads at every byte offset (104 cases),
five real-BIOS service runs (IRQ wait, division, unpack, header copy and
header validation), and a cartridge that reads the BIOS and unmapped memory
after the real BIOS hands over. That test fails with BIOS read protection
removed.

On Pocket, The Minish Cap got past the New Game opening cutscene, Link rolled
with R while walking, and a previously working game still booted.

# 0.2.0 full-feature rebuild

Quartus Prime Lite 18.1 compiled the full-feature public FPGA source with
fitter seed 31. Minimum setup slack was +0.612 ns and minimum hold slack was
+0.132 ns; recovery and removal checks now cover the reset synchronizers.
All 23 physical audits passed, including the Soft Colors setting crossing and
a reset clock-domain audit that found no reset crossing a clock domain outside
a synchronizer. The rebuilt bitstream matches the hardware-tested 0.2.0
candidate byte for byte. See the [0.2.0 build receipt](build-validation-0.2.0-receipt.json).

Development simulation covered the CPU, graphics, RTC, startup and save-boot,
overlay, serial and save-state stages, the Soft Colors filter and the link
multiplayer peer model. Save-state CPU timing was compared against the same
CPU built without save-state support.

On Pocket, the candidate with the reset fix booted Pokemon Emerald in 20+
launches without the black-screen hang seen in about 1 of 10 launches before.
The release package then linked Pokemon Emerald with a GBA SP in every cable
orientation and start order tested, and passed Emerald launches, a Memory
capture and load, sleep/wake, Soft Colors and fast-forward. The link port
needs cart power, so core.json keeps the cartridge slot powered.

# 0.1.2 full-feature rebuild

Quartus Prime Lite 18.1 compiled the full-feature public FPGA source.
Minimum setup slack was +0.114 ns and minimum hold slack was
+0.089 ns. All 21 physical audits passed.
The rebuilt bitstream matches v0.1.1 byte for byte. Hardware test results below cover the earlier releases.
See the [0.1.2 build receipt](build-validation-0.1.2-receipt.json).

# Wario Land 4 compatibility update

The v0.1.1 image matches the candidate installed and smoke tested on Pocket.
Quartus Lite 18.1 passed setup and hold with margins of +0.114 ns and +0.089 ns.
All 21 physical timing audits passed. Fitter seed 13 uses the existing clock
frequencies and constraints.

The Wario ROM replays checked all 512 palette halfwords at save selection
and nonzero VRAM and palette transfers during room loading. Six focused
simulations covered palette and VRAM ownership, null-source DMA, HBlank
display writes, both audio FIFOs, DMA word reuse, and save-state resume.
Fast-forward controls and return to normal speed also passed simulation.
The Pocket smoke test covered entering and playing a Wario level with
fast-forward. See the [v0.1.1 validation receipt](build-validation-wario-receipt.json).

The public FPGA build inputs match the qualified candidate byte for byte.
The v0.1.1 public checkout did not have a separate standalone rebuild. The checks above
cover the reported Wario failure and the exercised DMA paths.

# Accepted playtime update — November 6, 2026

The shipped image and every exported FPGA build input match the qualified
playtime candidate byte for byte. Its Quartus 18.1 build, all 18 physical
audits and three dedicated timing-cone checks pass. Setup is +0.023 ns,
hold +0.085 ns, with 18,074 ALMs used. Clock frequencies and timing limits
are unchanged. Formatting uses spare block RAM to reduce logic pressure.

The user accepted the visible formatting. Hardware day rollover was explicitly
not tested; day/minute/hour boundaries and the preserved 9999-hour display
limit are covered by independent simulation. Six playtime tests include
2,060 duration vectors, 737,280 paired decimal ROM conversions, 97 complete
pixel frames, accounting and both host byte orders. Run them with
`python scripts/test-playtime.py --run build/playtime-tests-01`.

Image SHA-256:
`96ff681ddfc88d984b2a8a9453411776d69d4cf61a2329a7f4a82932b8c951b5`.

See the [0.1.0 export/qualification receipt](build-validation-receipt.json).
The v0.1.0 standalone checkout did not have a separate recompile. The earlier
November 4 baseline was independently rebuilt byte for byte; its
[historical receipt](build-validation-20261104-receipt.json) is preserved.

Windows tool discovery is tested; Linux remains untested. This is not an
exhaustive game-compatibility claim. Custom color desaturation is not included.
