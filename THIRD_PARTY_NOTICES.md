# Third-party notices and reference acknowledgements

This inventory distinguishes included framework/IP material from projects
consulted during development. Original notices remain in their source files.
Project-authored material is GPL-3.0-only; see LICENSE and LICENSE-SCOPE.md. This does not replace third-party terms.

## Included framework and support material

| Material | Attribution and location | Recorded terms / status |
| --- | --- | --- |
| Pocket framework | Analogue Enterprises Limited; `src/fpga/apf/apf_top.v`, `common.v`, `io_bridge_peripheral.v`, `io_pad_controller.v` | Embedded APF Software License Agreement retained in full. See the referenced [Pocket EULA](https://assets.analogue.co/pdf/43478bf701eb4905172acbecc3babae9/Analogue%2BEULA%2BAugust%2B14%2B2022.pdf), including its MIT/GPL compatibility provision. |
| Host/target command bridge | Analogue, 2022; `src/fpga/core/core_bridge_cmd.v` | Attribution retained. Modified project integration; do not treat the entire file as newly authored BitBird code. |
| Core starter/project integration | [open-fpga/core-template](https://github.com/open-fpga/core-template); starter portions of `core_top.v`, project files, constraints and packaging structure | Local template lineage is recorded per file. A README legal statement is not a project-wide permissive license. Exact upstream snapshot commit remains unrecorded. |
| Generated megafunctions / IP | Intel / Altera; `mf_datatable.v`, `mf_ddio_bidir_12.v`, `pin_ddio_clk.v`, `mf_pllbase*`, and associated integration/simulation files | Existing Intel/Altera copyright and license notices retained. File-specific notices apply; no new MIT/GPL designation has been assigned to this material. |
| Build-ID generation reference script | Altera Corporation, 2011; `src/fpga/apf/build_id_gen.tcl` | Embedded Altera reference-design notice retained. The embedded reference-design terms remain applicable. |

The complete [source-file inventory](docs/source-attribution-inventory.json)
records hashes, notice locations and byte matches against the retained template
snapshot. Files without a recognizable header are included in the inventory;
absence of a header is not evidence of public-domain status.

## Documentation and implementation references

These are acknowledgements of documented research. Their source trees, manuals,
ROMs and BIOS images are not bundled in this repository. Reference use does not
automatically transfer an upstream license to this core. This audit does not
certify clean-room development or rule out all derivation.

- **Martin Korth / GBATEK contributors:** [GBATEK](https://mgba-emu.github.io/gbatek/), including the maintained Markdown edition. Register behavior, DMA, video, sound, saves and serial protocols.
- **Arm:** [ARM7TDMI technical reference manual, DDI0029G](https://ww1.microchip.com/downloads/en/DeviceDoc/DDI0029G_7TDMI_R3_trm.pdf). CPU behavior and instruction timing; document linked, not redistributed.
- **Jeffrey Pfau / mGBA contributors:** [mGBA](https://github.com/mgba-emu/mgba). Memory, DMA, I/O, save devices and HALT behavior. Consulted files include `src/gba/{memory,dma,io,savedata,gba}.c`; the consulted save implementation carries an MPL-2.0 notice. No mGBA C source is included in the staged source tree.
- **MiSTer GBA contributors:** [GBA_MiSTer](https://github.com/MiSTer-devel/GBA_MiSTer), historically inspected at `93790a023395bbd90e5eaf4dfb2cb5910afd55f5`. CPU staging, cache/memory structure, compositor and cycle accounting. Upstream carries GPL-2.0 terms; credit alone would not authorize copying or translating its implementation under another license.
- **mincer-ray:** [openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA), historically inspected at `8bd32b54323f2bd1221fd05d0e7b897142ec6344`. Pocket integration, cache, CPU and cycle-controller comparisons. Its MiSTer lineage is acknowledged; shared ancestry is not a separate independent implementation.
- **wolfshow:** [Pocket fork](https://github.com/wolfshow/openfpga-GBA/tree/8b01afe3bb93fd3f5ff6f1f5cb2be02db4e3a53f), historically inspected at that pinned revision as another integration reference. That old pinned page was unavailable through the web reader during this audit; the recorded source revision identifies the reference inspected during development.
- **Stephen Stair:** [GBA Communications Information](https://www.akkit.org/info/gba_comms.html), for multiplayer wiring and framing research.
- **gbadev / gbadoc contributors:** [Sound Channel 4](https://gbadev.net/gbadoc/audio/sound4.html), for PSG noise feedback research.
- **pret contributors:** [pokeemerald save.c](https://github.com/pret/pokeemerald/blob/master/src/save.c) and [palette.c](https://github.com/pret/pokeemerald/blob/master/src/palette.c); [pokefirered agb_flash_1m.c](https://github.com/pret/pokefirered/blob/master/src/agb_flash_1m.c) and [flash_internal.h](https://github.com/pret/pokefirered/blob/master/include/gba/flash_internal.h). Save layout, checksums, palette behavior and Flash-library identification research. These acknowledgements do not assert ownership of the reconstructed game material.
- **zeldaret contributors:** [tmc eeprom.c](https://github.com/zeldaret/tmc/blob/master/src/eeprom.c) and [save.c](https://github.com/zeldaret/tmc/blob/master/src/save.c), for Minish Cap EEPROM and save verification analysis. The dated investigation explicitly records independent RTL implementation and no copied reference source in its controller or fixture.
- **Alliance Memory:** AS1C8M16PL PSRAM, AS4C32M16MSA SDRAM and AS6C2016 SRAM device data sheets used for electrical/timing research. Data sheets are not bundled.

## Tools and development

Quartus Prime Lite and vendor tools were used to build and qualify the FPGA
image. Development also used Icarus Verilog, Python, PowerShell, Git and OpenAI
Codex. Tool acknowledgements do not imply that those tools are bundled, own the
core, or endorse it.

## License boundaries

Project-authored material is GPL-3.0-only as described in LICENSE-SCOPE.md.
Third-party source notices remain intact. The source inventory records the
retained framework/template lineage; its exact upstream template revision was
not recorded, so local file hashes provide the available provenance evidence.

Analogue's APF headers and EULA contain an MIT/GPL compatibility provision.
The [official developer changelog](https://www.analogue.co/developer/docs/changelog/1-1-beta-1)
records that clarification. Intel/Altera files retain the applicable vendor and
reference-design notices; this project does not assign those files a new blanket
license or claim that attribution alone creates distribution rights.
