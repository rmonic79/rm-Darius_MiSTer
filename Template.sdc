# This file is part of Darius_MiSTer.
#
# Darius_MiSTer is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details: LICENSE in the root of the repository, or <https://www.gnu.org/licenses/>.
#
# Author: Umberto Parisi (rmonic79); the first two lines come from the MiSTer core template by
# Sorgelig (MiSTer-devel).
#
derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# ============================================================
# Multicycle SOLO sulle istanze chip cen-paced (schema BoogieWings:
# "NO multicycle globale"). Il resto di darius_audio_z80 (adapter DDR3,
# req/ack, ce_cnt, mixer, adaptor savestate) gira su clk PURO a 48MHz
# = single-cycle: la STA deve vederlo e il fitter deve chiuderlo.
# Budget (02/11, clk 48 MHz): Z80/YM a 4 MHz fisso (z80_clk_sel = 0 in Template.sv)
# = ce ogni 12 clk -> 12/11. Se si esponesse l'opzione 8 MHz (ce_div 6) andrebbe 6/5.
# ============================================================
set_multicycle_path -setup -from [get_registers {*z80_audio*}] -to [get_registers {*z80_audio*}] 12
set_multicycle_path -hold  -from [get_registers {*z80_audio*}] -to [get_registers {*z80_audio*}] 11
set_multicycle_path -setup -from [get_registers {*z80_adpcm*}] -to [get_registers {*z80_adpcm*}] 12
set_multicycle_path -hold  -from [get_registers {*z80_adpcm*}] -to [get_registers {*z80_adpcm*}] 11
set_multicycle_path -setup -from [get_registers {*u_ym1*}] -to [get_registers {*u_ym1*}] 12
set_multicycle_path -hold  -from [get_registers {*u_ym1*}] -to [get_registers {*u_ym1*}] 11
set_multicycle_path -setup -from [get_registers {*u_ym2*}] -to [get_registers {*u_ym2*}] 12
set_multicycle_path -hold  -from [get_registers {*u_ym2*}] -to [get_registers {*u_ym2*}] 11
set_multicycle_path -setup -from [get_registers {*u_msm5205*}] -to [get_registers {*u_msm5205*}] 12
set_multicycle_path -hold  -from [get_registers {*u_msm5205*}] -to [get_registers {*u_msm5205*}] 11
