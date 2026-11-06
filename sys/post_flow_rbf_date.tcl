# This file is part of Darius_MiSTer.
#
# Darius_MiSTer is free software: you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details: LICENSE in the root of the repository, or <https://www.gnu.org/licenses/>.
#
# Author: Umberto Parisi (rmonic79)
#
# Post-flow: copia il RBF generato da Quartus in una copia datata.
#   output_files/rmDarius.rbf -> output_files/rmDarius_yyyymmdd.rbf
# Se il nome esiste gia' (piu' build nello stesso giorno): _yyyymmdd_1, _2, ...
# Gira dentro `quartus_sh --flow compile` (POST_FLOW_SCRIPT_FILE). Non tocca
# il rmDarius.rbf base (quello resta per l'upload MiSTer).

set out_dir "output_files"
set base    "rmDarius"
set src     "$out_dir/$base.rbf"

if {![file exists $src]} {
    puts "post_flow_rbf_date: $src non trovato, skip"
    return
}

set stamp [clock format [clock seconds] -format %Y%m%d]
set dst   "$out_dir/${base}_${stamp}.rbf"

if {[file exists $dst]} {
    set n 1
    while {[file exists "$out_dir/${base}_${stamp}_${n}.rbf"]} { incr n }
    set dst "$out_dir/${base}_${stamp}_${n}.rbf"
}

file copy -force $src $dst
puts "post_flow_rbf_date: creato $dst"
