# License scope

Project-authored material in GBA by BitBird is licensed under the GNU General
Public License, **version 3 only** (`SPDX-License-Identifier: GPL-3.0-only`).
The complete license is in [LICENSE](LICENSE). No option to use later versions
is granted by this project's licensing declaration.

This grant applies to copyrightable contributions of the project authors,
including the GBA implementation under `src/rtl/`, project-authored scripts and
documentation, and original additions to the Pocket integration. Third-party
material remains subject to its applicable notices and terms. The grant does
not claim ownership of that material or replace its license.

## Third-party boundaries

- Analogue APF files in `src/fpga/apf/` and the template portions of
  `src/fpga/core/core_bridge_cmd.v`, `core_top.v`, project files and constraints
  retain the framework/template notices and applicable terms. The APF agreement
  contains its own MIT/GPL compatibility provision; preserve that agreement.
- Intel/Altera generated IP, wrappers, simulation support and reference scripts
  retain vendor notices and applicable terms, including the PLL, RAM/DDIO and
  build-ID files. They are not relicensed wholesale by the project declaration.
- For a file containing both project additions and upstream material, the GPL
  grant covers the project-authored additions; upstream terms still need to be
  respected for the combined file. This statement does not resolve every
  compatibility question by labeling the files an aggregate.
- Preserved candidate ZIPs and the FPGA image include combined components.
  They must not be described as wholly owned by BitBird or uniformly relicensed.
  The original archives remain unchanged historical candidates.

The [third-party notices](THIRD_PARTY_NOTICES.md) and
[file inventory](docs/source-attribution-inventory.json) identify these boundaries.
The inventory is provenance evidence, not a grant for third-party material.

The project is provided without warranty, as described in LICENSE. GPL permits
commercial use; distributing covered modifications entails the GPL's obligations.

## Before public binary distribution

Provide recipients with the license, notices and equivalent access to complete
corresponding source for the exact released image, including the scripts needed
to build and install it. See docs/build.md and docs/installation.md for build and installation details. General-purpose build tools are not bundled.

This license statement does not replace notices or rights held by third parties.
