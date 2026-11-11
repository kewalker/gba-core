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
