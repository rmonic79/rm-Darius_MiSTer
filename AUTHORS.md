# Authors and Credits

## Darius_MiSTer core

**Author**: Umberto Parisi ([rmonic79](https://github.com/rmonic79))

The original RTL source files for the Darius-specific logic (under
`rtl/darius/`, except the third-party files listed below) are copyright
Umberto Parisi and distributed under GNU GPL v3 or later. The project wrapper
`Template.sv` is by Umberto Parisi, derived from the MiSTer core template by
Sorgelig (MiSTer-devel).

## Own components

The two processors and the SDRAM controller are separate projects by the same
author. Each one has its own repository, with its documentation and test
benches.

| Component | Folder | Repository |
|-----------|--------|------------|
| **rm68000** — MC68000 core, DTACK generator, external savestate | `rtl/rm68000/` | [rmonic79/rm68000](https://github.com/rmonic79/rm68000) |
| **rmZ80** — Z80 core | `rtl/rmZ80/` | [rmonic79/rmZ80](https://github.com/rmonic79/rmZ80) |
| **rmSdram** — SDRAM controller | `rtl/rmSdram/` | [rmonic79/rmSdram_MiSTer](https://github.com/rmonic79/rmSdram_MiSTer) |

## Third-party components

This core builds on top of excellent open-source projects. All third-party
sources retain their original copyright and license. The core as a whole
is distributed under **GNU GPL v3 or later** to stay compatible with the
most restrictive upstream (JT12 / JT5205 / JTFRAME).

| Component | Author | Project | License |
|-----------|--------|---------|---------|
| **JT12** — YM2203 FM synthesizer, with the JT49 PSG | Jose Tejada ([@topapate](https://twitter.com/topapate)) | [jotego/jt12](https://github.com/jotego/jt12) | GPL-3 |
| **JT5205** — MSM5205 ADPCM decoder | Jose Tejada | [jotego/jt5205](https://github.com/jotego/jt5205) | GPL-3 |
| **JTFRAME** — audio DC-removal filter (`jtframe_dcrm`) | Jose Tejada | [jotego/jtframe](https://github.com/jotego/jtframe) | GPL-3 |
| **Savestate infrastructure** — ssbus, memory_stream, save state adaptors (`rtl/darius/ss/savestate.sv`, `savestate_ddr.sv`, `savestate_ram.sv`, `savestate_ui.sv`, `memory_stream.sv`; adapted by Umberto Parisi) | Martin Donlon ([wickerwaka](https://github.com/wickerwaka)) | [wickerwaka/Arcade-TaitoF2_MiSTer](https://github.com/wickerwaka/Arcade-TaitoF2_MiSTer) | GPL-3 |
| **DDR3 adapter** — `rtl/darius/darius_ddram.sv` | Sorgelig | [MiSTer-devel](https://github.com/MiSTer-devel) | GPL-3 |
| **sys/ framework** — MiSTer HPS/IO, OSD, video scaler, audio | Sorgelig (Alexey Melnikov) / MiSTer-devel, with files by Till Harbaum, Ludvig Strigeus, TEMLIB (`ascal.vhd`), Ultra-Embedded (`spdif.v`), bellwood420, Kitrinx, Grabulosaure, Mike Simone; Intel/Altera generated PLL files | [MiSTer-devel/Main_MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) | per file: GPL-2.0-or-later, GPL-3.0-or-later, LGPL-3.0-or-later (`sd_card.sv`), TEMLIB free-use notice (`ascal.vhd`), Intel license (`pll_cfg/`) |

## Contributors

- **Andrea Bogazzi** ([@asturur](https://github.com/asturur)) — help with the CRT
  Adjust implementation (`rtl/darius/crt_adjust.sv`).

## Reference

- **Darius arcade hardware** — Taito Corporation, 1986. This FPGA core is a
  reimplementation from hardware documentation, MAME source code, and
  observation of real hardware behavior. ROMs are **not** included and must
  be provided by the user.
- **MAME project** — invaluable reference for memory maps, timing,
  and driver behavior. [mamedev/mame](https://github.com/mamedev/mame)
