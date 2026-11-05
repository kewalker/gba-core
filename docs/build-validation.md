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

See the [current export/qualification receipt](build-validation-receipt.json).
The updated standalone checkout has not been independently recompiled;
`python scripts/build.py` remains available for that check. The earlier
November 4 baseline was independently rebuilt byte for byte; its
[historical receipt](build-validation-20261104-receipt.json) is preserved.

Windows tool discovery is tested; Linux remains untested. This is not an
exhaustive game-compatibility claim. Custom color desaturation is not included.
