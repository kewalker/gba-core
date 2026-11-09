# Build GBA by BitBird

Requirements: Python 3.10 or newer (standard library only), Quartus Prime Lite
18.1 with Cyclone V device support, and enough disk space for a fresh fit.
No ROM, BIOS, save or old development checkout is needed to compile this source.
Quartus itself is installed separately under its vendor terms.

## Check and stage the project

From the repository root:

```text
python scripts/build.py --run build/preflight-01 --prepare-only
```

This verifies preserved candidate hashes and audit-script hashes, copies source
to a fresh directory, and checks QSF/QIP source references recursively. It does
not invoke a compiler. A successful receipt has status PREPARED, not PASS.

## Build and audit

```text
python scripts/build.py --run build/local-01 --quartus-bin "C:/intelFPGA_lite/18.1/quartus/bin64"
```

Use your own Quartus path. Alternatively set QUARTUS_BIN or put the Quartus
executables on PATH and omit --quartus-bin. The runner resolves tools before
building, checks the reported version, and requires a new run directory each
time. Python and Quartus paths are not embedded in the runner. On Linux use
the appropriate installed Quartus executable directory; this workflow still
requires validation there and has only been exercised on Windows.

The runner invokes synthesis, placement/routing and timing analysis separately.
It preserves the sealed seed, feature defines, device, build-ID bytes, clocks
and constraints. It intentionally does not invoke the timestamp-generating
pre-flow hook. Opening the project and using an ordinary full-flow command may
regenerate build-ID files and is a different input policy.

All original fitted clock/corner summary rows must exist with nonnegative slack
and zero total negative slack. The 18 preserved physical audits and three extra
CPU/retained-ROM/validator timing-cone checks use their existing limits. SDRAM
output-enable register packing and EWRAM cache M10K placement are also checked.
Only then does assembly run and produce a bit-reversed bitstream.rbf_r in the
run directory. The runner checks the output conversion and rechecks source hashes.

## Results and scope

Each stage has its own log. receipt.json records the active stage, exit codes,
durations and final PASS/FAILED status; quiet output is not success. Each stage
has a timeout (default 3600 seconds for compilation; physical audits 240 seconds).
Change compilation timeout with --stage-timeout. Interrupted runs may leave a
RUNNING receipt, which is not success; use a new run prefix for a retry.

The resulting image is a local build artifact. It never overwrites pocket/,
historical ZIPs, the accepted image or the Pocket card. The receipt explicitly
keeps release_qualified and hardware_accepted false: build/timing checks do not
replace functional simulations or hardware acceptance. A rebuilt image may
differ from the historical image; its hash comparison is recorded, not assumed.

The historical tested build passed setup +0.218 ns, hold +0.121 ns and 18
physical audits. Those numbers belong to that build, not automatically to a
new fit. The current build uses its own reports and receipts.

## Validation scope

The portable functional regression suite is not yet complete. Build and timing
checks do not establish new gameplay compatibility. The current exported build
inputs match the qualified Wario candidate; the updated checkout has not been
independently recompiled. Future RTL changes require appropriate
functional and hardware validation. Source edits must be intentionally reflected
in the source manifest before using this frozen-baseline build runner.

## Qualification history

The November 4 Windows baseline was independently rebuilt byte for byte. The
Wario update has its own passing fit and 21 timing/physical checks;
the exported FPGA inputs and image match that qualified candidate exactly, but
this updated checkout has not had a separate standalone recompile. See
[current validation](build-validation.md) for the source and hardware scope.
