/*  This file is part of Darius_MiSTer.

    Darius_MiSTer is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Darius_MiSTer is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Darius_MiSTer.  If not, see <http://www.gnu.org/licenses/>.
*/

//============================================================================
//  crt_adjust.sv  —  "CRT Adjust"
//
//  Core-side analog CRT geometry module for MiSTer FPGA arcade cores.
//  Author: rmonic79 (with help from Andrea Bogazzi / @asturur).
//
//  This is the evolution of the earlier core-side "Analog H-Size" module:
//  the same content-shift line-buffer idea, now grown into a full CRT
//  alignment tool exposed in the OSD as "CRT Adjust". One always-on line
//  buffer provides THREE controls:
//
//      - H-Size     : horizontal stretch / squeeze (bidirectional, integer)
//      - H-Position : horizontal content shift (does NOT move the sync)
//      - V-Shift    : vertical line shift
//
//  ─── Why it never desyncs the CRT ──────────────────────────────────────────
//  The picture CONTENT is shifted/resized through the line buffer while the
//  horizontal/vertical SYNC signals stay NATIVE. The CRT keeps its lock at
//  all times, so you can slide and resize the image live without the screen
//  rolling or losing hold — unlike moving the blanking/sync windows.
//
//  Every source pixel is emitted for an integer-uniform number of pixel-clock
//  periods (no fractional ratio, no per-pixel nearest-neighbor), so there is:
//      - NO shimmering on moving content
//      - NO blending / blur (output = source pixel, byte-exact)
//      - NO line buffer mismatch (1-line ping-pong, deterministic phase)
//
//  In this core the module is inserted CORE-SIDE: instantiated inside the
//  core's emu wrapper (Template.sv) at the video-output boundary, with zero
//  sys_top.v changes (MiSTer-devel compliant — the sys/ framework is never
//  modified). The trade-off: the adjust reaches the analog DAC AND HDMI
//  follows it too. Leave CRT Adjust Off for an untouched HDMI image.
//
//  ─── Resource cost ─────────────────────────────────────────────────────────
//  ~1 M10K (24-bit linebuffer with ping-pong banks), ~50 ALM, 0 DSP.
//
//  ─── Required external signals ─────────────────────────────────────────────
//  pxl_cen   : the core's pixel clock enable (write rate, e.g. 6 MHz pulse
//              on a 96 MHz clk).
//  pxl2_cen  : the DAC read clock enable, SLOWER than pxl_cen by an integer
//              divisor (16+hsize) of clk, generated externally for phase
//              alignment with HSync (rd_ce in Template.sv).
//  hsize     : signed 4-bit, OSD-controlled stretch factor.
//              hsize = 0 → bypass (passthrough at pxl_cen rate)
//              hsize < 0 → progressively wider pixels (the typical use case;
//                          the OSD usually exposes 0..7 unsigned and the
//                          glue logic negates it before connecting).
//
//  ─── License ───────────────────────────────────────────────────────────────
//  Author: Umberto Parisi (rmonic79), 2026.
//  Distributed under GNU GPL v3 or later.
//============================================================================

// ----------------------------------------------------------------------------
//  HPOS_MODE — how the H-Position control moves the image horizontally.
//
//  Two independent mechanisms, pick one per core at compile time. Both are
//  driven by the same OSD "H-Position" value (`hoffset`); the difference is
//  WHAT gets moved.
//
//    HPOS_CONTENTSHIFT (1): shift the CONTENT inside the line buffer, keep the
//        sync native. Never desyncs the CRT, and it is the ONLY mechanism that
//        stays locked while H-Size shrinks the image (the read rate changes but
//        the read reset stays on the native HSync). Downside: on a NARROW game
//        whose active area is anchored to one side of the line (large asymmetric
//        blanking), pushing the content toward the short-margin side runs it out
//        of the buffer window and a black block appears.
//        USE FOR: wide / centered games (e.g. GundamSD, 320px active).
//
//    HPOS_SYNCSHIFT (0): shift the HSYNC out by N pixels (line shift register),
//        keep the content anchored natively and the read reset on the NATIVE
//        HSync. The picture slides on the CRT with no buffer window to fall out
//        of -> no black block on narrow anchored games. Because the read reset
//        stays native (unlike the old UPSTREAM h-shift that also fed the shifted
//        HSync into the read divisor), it does NOT reintroduce the shrink-desync
//        the upstream version had.
//        USE FOR: narrow / side-anchored games (e.g. Legionnaire, Heated Barrel,
//        256px active with wide asymmetric H back-porch).
// ----------------------------------------------------------------------------
`define HPOS_SYNCSHIFT    0
`define HPOS_CONTENTSHIFT 1

// ── Adattamenti Darius (unici delta vs Legionnaire/HeatedBarrel/Godzilla) ──
//  1. AW parametrico: la linea Darius e` 1527 slot (vs 384) -> AW=12
//     (2048 sample/banco). Default 10 = identico all'originale.
//  2. Storage xBGR555 (15 bit) invece di RGB888: LOSSLESS (l'RGB888 a monte
//     e` espansione 5->8 della palette xBGR555) e il buffer 4096x15 sta in
//     MLAB (M10K del core al 100%). Espansione 5->8 in lettura.
module crt_adjust #(
    parameter VTOTAL   = 263,
    parameter HTOTAL   = 384,               // line length in pixels (for the HSync shreg)
    parameter HPOS_MODE = `HPOS_CONTENTSHIFT, // see HPOS_MODE block above
    parameter integer AW = 10               // 2^AW samples totali (2 banchi da 2^(AW-1))
)
(
    input              clk,
    input              pxl_cen,      // write clock enable (core pixel rate)
    input              pxl2_cen,     // read clock enable  (DAC pixel rate, slower)

    input              active,       // ON/OFF: 0 = bypass puro (nativo), 1 = modulo
                                     // attivo (H-Size / H-Pos / V-Shift funzionano
                                     // anche se i loro valori sono 0).

    input  signed [4:0] hsize,       // 0 = nessuna scala, !=0 = enlarge/shrink
    input  signed [10:0] hoffset,    // H-Position value from the OSD, in native screen pixels (06/11: 11 bit).
    input        [7:0] hbase,        // read period base of the glue's generator, in quarter-cycles of clk (06/11):
                                     //   read period = hbase + hsize (min 8). Used to keep the picture CENTRE fixed
                                     //   while H-Size stretches or squeezes (CONTENTSHIFT).
                                     // HPOS_CONTENTSHIFT: shifts the CONTENT in the
                                     //   line buffer (>0 right, <0 left), sync native.
                                     // HPOS_SYNCSHIFT: delays HSync by N pixels, content
                                     //   stays native (>0 right, <0 left). See HPOS_MODE.
    input  signed [5:0] voffset,     // V-Shift: sposta il VSync di N righe (signed).
                                     // >0 = giu`, <0 = su. Verticale non desincronizza.

    input        [7:0] r_in,
    input        [7:0] g_in,
    input        [7:0] b_in,
    input              hs_in,
    input              vs_in,
    input              hb_in,
    input              vb_in,

    output reg   [7:0] r_out,
    output reg   [7:0] g_out,
    output reg   [7:0] b_out,
    output reg         hs_out,
    output reg         vs_out,
    output reg         hb_out,
    output reg         vb_out,
    // Shifted HSync reference (HPOS_SYNCSHIFT): the glue must reset its read-rate
    // generator (pxl2_cen) on the RISE of this signal so the read-rate and the
    // module's read counter restart on the same edge (like the upstream scheme).
    // In HPOS_CONTENTSHIFT it equals the native HSync.
    output wire        hs_ref_out
);

    // AW ora parametro di modulo (vedi header adattamenti Darius)

    // ------------------------------------------------------------------
    //  Input pipeline @ pxl_cen (for latency matching in bypass mode)
    // ------------------------------------------------------------------
    reg [7:0] r_in_q, g_in_q, b_in_q;
    reg       hs_in_q, hb_in_q, vs_in_q, vb_in_q;
    reg       hs_in_d;
    initial begin
        r_in_q = 0; g_in_q = 0; b_in_q = 0;
        hs_in_q = 0; hb_in_q = 1; vs_in_q = 0; vb_in_q = 0;
        hs_in_d = 0;
    end

    always @(posedge clk) if (pxl_cen) begin
        r_in_q   <= r_in;
        g_in_q   <= g_in;
        b_in_q   <= b_in;
        hs_in_q  <= hs_in;
        hb_in_q  <= hb_in;
        vs_in_q  <= vs_in;
        vb_in_q  <= vb_in;
        hs_in_d  <= hs_in;
    end

    // Native HSync rise (used only for the shift register that produces the
    // shifted reference below).
    wire hs_rise_native = pxl_cen && (hs_in & ~hs_in_d);

    // ------------------------------------------------------------------
    //  H-Shift shift register (HPOS_SYNCSHIFT). Delays HSync by N pixels
    //  (hoffset signed). Declared BEFORE the read side because in
    //  HPOS_SYNCSHIFT the read counter (rdcnt) resets on this SHIFTED HSync,
    //  exactly like the reference upstream scheme (analog_hsize + h-shift):
    //  there the read divisor and the read counter both restart on the shifted
    //  HSync, so the enlarged content stays aligned with the read window and
    //  never runs off into the right-edge black. Clocked @ pxl_cen (native px).
    //  hoffset >0 = right (delay HSync), <0 = left (advance = HTOTAL-|N| tap).
    // ------------------------------------------------------------------
    wire [11:0] hshift_tap = hoffset[10]
        ? (12'(HTOTAL) + {hoffset[10], hoffset})      // negativo -> HTOTAL - |N|
        : {1'd0, hoffset};                            // positivo -> N
    reg [HTOTAL-1:0] hsync_pix_shreg;
    initial hsync_pix_shreg = 0;
    always @(posedge clk) if (pxl_cen)
        hsync_pix_shreg <= {hsync_pix_shreg[HTOTAL-2:0], hs_in};
    reg hs_shifted;
    initial hs_shifted = 0;
    always @(posedge clk) if (pxl_cen)
        hs_shifted <= (hshift_tap == 12'd0) ? hs_in : hsync_pix_shreg[hshift_tap - 12'd1];

    // HSync reference for the WHOLE line-buffer engine: the shifted HSync in
    // HPOS_SYNCSHIFT, the native HSync otherwise. Like the reference upstream
    // scheme (analog_hsize fed the already-shifted HSync), BOTH the write side
    // (wrp/bank/hb0/hb1 capture) and the read side restart on this same edge, so
    // write and read stay on the same bank/phase and the enlarged content is not
    // disaligned at the right edge.
    wire hs_read_ref = (HPOS_MODE == `HPOS_SYNCSHIFT) ? hs_shifted : hs_in;
    assign hs_ref_out = hs_read_ref;   // exposed so the glue aligns pxl2_cen to it
    reg  hs_ref_d1;
    initial hs_ref_d1 = 0;
    always @(posedge clk) if (pxl_cen) hs_ref_d1 <= hs_read_ref;
    wire hs_rise_in = pxl_cen && (hs_read_ref & ~hs_ref_d1);

    // ------------------------------------------------------------------
    //  Linebuffer ping-pong (24-bit RGB, single M10K, two banks).
    //  Written @ pxl_cen by the core, read @ pxl2_cen by the DAC.
    //  Two banks (selected by `bank` flipped on each HSync rise) avoid
    //  read/write collisions: write current line into `bank`, read the
    //  previous line (`~bank`) which is already complete.
    // ------------------------------------------------------------------
    // xBGR555 lossless, M10K (rework: BRAM abbondante post-audio-DDR3,
    // ALM da liberare — era MLAB quando gli M10K erano al 100%)
    (* ramstyle = "no_rw_check, M10K" *) reg [14:0] mem [0:(1<<AW)-1];
    integer ii;
    initial for (ii = 0; ii < (1<<AW); ii = ii + 1) mem[ii] = 15'd0;

    // ------------------------------------------------------------------
    //  WRITE side @ pxl_cen
    // ------------------------------------------------------------------
    reg [AW-1:0] wrp;
    reg [AW-1:0] hmax;
    reg [AW-1:0] hb0, hb1;
    reg          lhb_l;
    reg          bank;
    initial begin
        wrp = 0; hmax = 0;
        hb0 = 0; hb1 = 0;
        lhb_l = 0;
        bank = 0;
    end

    wire lhb = ~hb_in;

    always @(posedge clk) if (pxl_cen) begin
        lhb_l <= lhb;
        mem[{bank, wrp[AW-2:0]}] <= {r_in[7:3], g_in[7:3], b_in[7:3]};
        if (hs_rise_in) begin
            wrp  <= {AW{1'b0}};
            hmax <= wrp;
            bank <= ~bank;
        end else begin
            wrp <= wrp + 1'b1;
        end
        if (lhb   & ~lhb_l) hb1 <= wrp;  // start of active region (wrp value)
        if (~lhb  &  lhb_l) hb0 <= wrp;  // end of active region   (wrp value)
    end

    // ------------------------------------------------------------------
    //  READ side @ pxl2_cen.
    //  rdcnt increments by 1 at each pxl2_cen pulse -> exactly one source
    //  pixel is emitted to the DAC per read tick. Reset is triggered by
    //  the rising edge of HSync, detected at FULL clk rate to avoid
    //  missing edges when pxl2_cen is slow.
    // ------------------------------------------------------------------
    reg [AW-1:0] rdcnt;
    reg          hs_in_d2;
    reg          hs_rise_pending;
    initial begin
        rdcnt = 0;
        hs_in_d2 = 0;
        hs_rise_pending = 0;
    end

    always @(posedge clk) begin
        hs_in_d2 <= hs_read_ref;
        if (hs_read_ref & ~hs_in_d2)  hs_rise_pending <= 1'b1;
        else if (pxl2_cen)            hs_rise_pending <= 1'b0;
    end

    always @(posedge clk) if (pxl2_cen) begin
        if (hs_rise_pending) begin
            rdcnt <= {AW{1'b0}};
        end else begin
            rdcnt <= rdcnt + 1'b1;
        end
    end

    // ------------------------------------------------------------------
    //  Read from the linebuffer @ pxl2_cen, on the OPPOSITE bank to the
    //  one currently being written (so the previous fully-written line).
    //  pass_q gates active video against blanking, in linebuffer units.
    // ------------------------------------------------------------------
    reg [14:0] rd_data;
    reg        pass_q;
    initial begin
        rd_data = 0;
        pass_q = 0;
    end
    // Espansione xBGR555 -> RGB888 (replica MSB, identica al compositor)
    wire [7:0] rd_r8 = {rd_data[14:10], rd_data[14:12]};
    wire [7:0] rd_g8 = {rd_data[9:5],   rd_data[9:7]};
    wire [7:0] rd_b8 = {rd_data[4:0],   rd_data[4:2]};

    // vb_active: VBlank verticale vero, allineato al READ side.
    // Serve a spegnere pass_q durante le righe di VBlank -> VGA_DE torna basso
    // nel VBlank -> l'OSD trova il confine verticale del frame e resta visibile.
    // NON tocca hb0/hb1 (bordi orizzontali) -> nessun re-clamp del "gotcha".
    //
    // FIX pixel tagliati in basso: il read side emette la riga PRECEDENTE
    // (~bank), quindi e` in ritardo di 1 riga rispetto al write/vb_in nativo.
    // Se vb_active seguisse vb_in al write rate, spegnerebbe pass_q mentre il
    // read sta ancora emettendo l'ultima riga attiva -> ultima riga mangiata.
    // Campiono vb_in una volta per riga (hs_rise) e lo ritardo di 1 riga cosi`
    // vb_active si allinea a cio` che il read sta effettivamente emettendo.
    reg vb_line, vb_active;
    initial begin vb_line = 0; vb_active = 0; end
    always @(posedge clk) if (hs_rise_in) begin
        vb_line   <= vb_in;
        vb_active <= vb_line;
    end

    // hoffset (signed) sposta la finestra attiva: >0 = contenuto a DESTRA, <0 a
    // SINISTRA. rd_addr compensa per leggere il pixel sorgente giusto. hs_out NON
    // e' toccato -> HSync intatto -> no desync, qualunque sia l'entita' del shift.
    //
    // In HPOS_SYNCSHIFT the horizontal offset is applied to HSync out (see below),
    // NOT to the read window: the content stays anchored natively, so the read
    // offset is forced to 0 here and hb1/hb0 keep gating the native active area.
    // ------------------------------------------------------------------
    //  H-Size compensato (06/11, CONTENTSHIFT). La lettura parte dalla salita di HSync e con H-Size va a p/hbase del
    //  ritmo nativo (p = hbase + hsize, minimo 8, come il generatore del glue): l'immagine si allungava verso destra e
    //  si accorciava verso sinistra. Lo spostamento della finestra (in unita' di lettura) tiene fermo il CENTRO
    //  dell'immagine (hcen, misurato sul lato scrittura): centro in tempo = (hcen + off) * p / hbase = hcen + hoffset
    //      ->  off = (hcen + hoffset) * hbase / p - hcen
    //  hoffset e' quindi in pixel nativi di schermo, qualunque sia H-Size; con H-Size 0 off = hoffset esatto.
    //  1/p da tabella (65536/p arrotondato); valori fermi a ogni riga, calcolo registrato in 4 passi.
    //  (Il segno di hoffset e' esteso a mano: con `? $signed(hoffset) : {..{1'b0}}` il ?: era senza segno.)
    // ------------------------------------------------------------------
    function automatic [14:0] hrecip(input [5:0] pq);
        case (pq)
            6'd8: hrecip = 15'd8192;
            6'd9: hrecip = 15'd7282;
            6'd10: hrecip = 15'd6554;
            6'd11: hrecip = 15'd5958;
            6'd12: hrecip = 15'd5461;
            6'd13: hrecip = 15'd5041;
            6'd14: hrecip = 15'd4681;
            6'd15: hrecip = 15'd4369;
            6'd16: hrecip = 15'd4096;
            6'd17: hrecip = 15'd3855;
            6'd18: hrecip = 15'd3641;
            6'd19: hrecip = 15'd3449;
            6'd20: hrecip = 15'd3277;
            6'd21: hrecip = 15'd3121;
            6'd22: hrecip = 15'd2979;
            6'd23: hrecip = 15'd2849;
            6'd24: hrecip = 15'd2731;
            6'd25: hrecip = 15'd2621;
            6'd26: hrecip = 15'd2521;
            6'd27: hrecip = 15'd2427;
            6'd28: hrecip = 15'd2341;
            6'd29: hrecip = 15'd2260;
            6'd30: hrecip = 15'd2185;
            6'd31: hrecip = 15'd2114;
            6'd32: hrecip = 15'd2048;
            6'd33: hrecip = 15'd1986;
            6'd34: hrecip = 15'd1928;
            6'd35: hrecip = 15'd1872;
            6'd36: hrecip = 15'd1820;
            6'd37: hrecip = 15'd1771;
            6'd38: hrecip = 15'd1725;
            6'd39: hrecip = 15'd1680;
            6'd40: hrecip = 15'd1638;
            6'd41: hrecip = 15'd1598;
            6'd42: hrecip = 15'd1560;
            6'd43: hrecip = 15'd1524;
            6'd44: hrecip = 15'd1489;
            6'd45: hrecip = 15'd1456;
            6'd46: hrecip = 15'd1425;
            6'd47: hrecip = 15'd1394;
            6'd48: hrecip = 15'd1365;
            6'd49: hrecip = 15'd1337;
            6'd50: hrecip = 15'd1311;
            6'd51: hrecip = 15'd1285;
            6'd52: hrecip = 15'd1260;
            6'd53: hrecip = 15'd1237;
            6'd54: hrecip = 15'd1214;
            6'd55: hrecip = 15'd1192;
            6'd56: hrecip = 15'd1170;
            6'd57: hrecip = 15'd1150;
            6'd58: hrecip = 15'd1130;
            6'd59: hrecip = 15'd1111;
            6'd60: hrecip = 15'd1092;
            6'd61: hrecip = 15'd1074;
            6'd62: hrecip = 15'd1057;
            6'd63: hrecip = 15'd1040;
            default: hrecip = 15'd8192;
        endcase
    endfunction
    wire signed [9:0] hp_sum = $signed({2'b0, hbase}) + $signed({{5{hsize[4]}}, hsize});
    wire        [5:0] hp_eff = (hp_sum < 10'sd8) ? 6'd8 : (hp_sum > 10'sd63) ? 6'd63 : hp_sum[5:0];
    reg  [AW-1:0]        hcen_r;  initial hcen_r = 0;
    reg  signed [AW+2:0] hx_r;    initial hx_r = 0;
    reg  signed [AW+11:0] hy_r;   initial hy_r = 0;
    reg  [14:0]          hrc_r;   initial hrc_r = 0;
    reg  signed [AW+27:0] hz_r;   initial hz_r = 0;
    reg  signed [AW+1:0] hoff_c;  initial hoff_c = 0;
    always @(posedge clk) begin
        hcen_r <= ({1'b0, hb1} + {1'b0, hb0}) >> 1;
        hx_r   <= $signed({3'b0, hcen_r}) + $signed({{(AW+3-11){hoffset[10]}}, hoffset});
        hy_r   <= hx_r * $signed({1'b0, hbase});
        hrc_r  <= hrecip(hp_eff);
        hz_r   <= hy_r * $signed({1'b0, hrc_r});
        hoff_c <= (hz_r >>> 16) - $signed({2'b0, hcen_r});
    end
    wire signed [AW+1:0] hoff_s  = (HPOS_MODE == `HPOS_CONTENTSHIFT) ? hoff_c : {(AW+2){1'b0}};
    wire signed [AW+1:0] rdcnt_s = $signed({2'b0, rdcnt});
    wire signed [AW+1:0] hb1_s   = $signed({2'b0, hb1});
    wire signed [AW+1:0] hb0_s   = $signed({2'b0, hb0});
    wire [AW-1:0] rd_addr = (rdcnt_s - hoff_s);
    always @(posedge clk) if (pxl2_cen) begin
        rd_data <= mem[{~bank, rd_addr[AW-2:0]}];
        pass_q  <= (rdcnt_s >= (hb1_s + hoff_s)) && (rdcnt_s < (hb0_s + hoff_s)) && ~vb_active;
    end

    // ------------------------------------------------------------------
    //  V-Shift INTERNO: ritarda il VSync di N righe (voffset signed; negativo =
    //  VTOTAL - |N| righe). Sposta il VSync, non il contenuto: verticalmente
    //  il CRT ha ampia tolleranza -> nessun desync. hs_rise_in = fine riga.
    //  06/11, CRT Shrink interlacciato: il VSync conserva la sua POSIZIONE DENTRO
    //  LA RIGA. Il campo che segue un VSync a meta' riga deve uscire mezza riga
    //  piu' in basso; agganciato alla salita di HSync (com'era) i VSync dei due
    //  campi cadevano nello stesso punto della riga e il campo dispari usciva una
    //  riga intera sotto il pari invece di mezza (righe sorgente 2p e 2p-1 nella
    //  stessa posizione: i "semiquadri invertiti").
    //  - N = 0: il VSync passa com'e' (vs_in_q, come in bypass).
    //  - N >= 1: il registro di riga dice IN QUALE riga cade il fronte ritardato
    //    (q(m-N+1), una riga prima di quella in cui lo vedeva agganciato), la fase
    //    dice DOVE: fronte d'ingresso a P clk dalla salita di HSync della riga k ->
    //    fronte d'uscita a P clk dalla salita di HSync della riga k+N. Le fasi dei
    //    fronti stanno in una coda di 4, nell'ordine dei fronti (dentro N <= VTOTAL-1
    //    righe al massimo 2 campi x 2 fronti).
    // ------------------------------------------------------------------
    wire signed [8:0] vshift_tap = voffset[5]
        ? (9'(VTOTAL) + {{3{voffset[5]}}, voffset})   // negativo -> VTOTAL - |N|
        : {3'd0, voffset};                            // positivo -> N
    wire [8:0] vtap    = vshift_tap;                  // stessi bit, letti senza segno (fino a VTOTAL-1)
    wire [8:0] vtap_m2 = (vtap >= 9'd2) ? (vtap - 9'd2) : 9'd0;
    reg [VTOTAL-1:0] vsync_line_shreg;
    initial vsync_line_shreg = 0;
    always @(posedge clk) if (hs_rise_in)
        vsync_line_shreg <= {vsync_line_shreg[VTOTAL-2:0], vs_in};

    // fase del fronte d'ingresso: clk dalla salita di HSync
    reg [12:0] vph_cnt;  initial vph_cnt = 0;
    reg        vs_in_p;  initial vs_in_p = 0;
    always @(posedge clk) begin
        if (hs_rise_in)     vph_cnt <= 13'd0;
        else if (~&vph_cnt) vph_cnt <= vph_cnt + 13'd1;
        if (pxl_cen)        vs_in_p <= vs_in;
    end
    wire vs_edge_in = pxl_cen && (vs_in != vs_in_p);

    // livello agganciato alla riga, una riga prima del vecchio agganciato: q(m-N+1)
    wire vs_line_n1 = (vtap == 9'd1) ? vs_in : vsync_line_shreg[vtap_m2];

    reg [12:0] vph_q [0:3];
    integer    vph_i;
    initial for (vph_i = 0; vph_i < 4; vph_i = vph_i + 1) vph_q[vph_i] = 13'd0;
    reg  [1:0] vph_wp, vph_rp;   initial begin vph_wp = 2'd0; vph_rp = 2'd0; end
    reg  [2:0] vph_n;            initial vph_n = 3'd0;      // fasi in coda
    reg [12:0] vph_cd;           initial vph_cd = 13'd0;    // conto alla rovescia verso il fronte d'uscita
    reg        vph_run, vph_lvl; initial begin vph_run = 1'b0; vph_lvl = 1'b0; end
    reg        vs_line_p;        initial vs_line_p = 1'b0;
    reg        vs_t, vs_t_q;     initial begin vs_t = 1'b0; vs_t_q = 1'b0; end
    reg  [8:0] vtap_q;           initial vtap_q = 9'd0;
    reg        vresync;          initial vresync = 1'b1;   // riaggancio del livello alla riga (accensione, V-Shift cambiato)
    wire vpush = vs_edge_in;
    wire vpop  = hs_rise_in && ~vresync && (vs_line_n1 != vs_line_p);
    always @(posedge clk) begin
        vtap_q <= vtap;
        if (vtap != vtap_q) begin
            vph_wp <= 2'd0; vph_rp <= 2'd0; vph_n <= 3'd0; vph_run <= 1'b0; vresync <= 1'b1;
        end else begin
            if (vpush) begin
                vph_q[vph_wp] <= vph_cnt;
                vph_wp <= vph_wp + 2'd1;
            end
            if (vpop) vph_rp <= vph_rp + 2'd1;
            vph_n <= vph_n + {2'd0, vpush && (vph_n != 3'd4)} - {2'd0, vpop && (vph_n != 3'd0)};
            if (hs_rise_in) begin
                vs_line_p <= vs_line_n1;
                if (vresync) begin vs_t <= vs_line_n1; vresync <= 1'b0; end
            end
            if (vpop) begin
                // il fronte d'uscita cade P clk dopo la salita di HSync, come quello d'ingresso (P = 0: su questo clk)
                if (vph_n == 3'd0 || vph_q[vph_rp] == 13'd0) begin
                    vs_t    <= vs_line_n1;
                    vph_run <= 1'b0;
                end else begin
                    vph_cd  <= vph_q[vph_rp] - 13'd1;
                    vph_lvl <= vs_line_n1;
                    vph_run <= 1'b1;
                end
            end else if (vph_run) begin
                if (vph_cd == 13'd0) begin vs_t <= vph_lvl; vph_run <= 1'b0; end
                else vph_cd <= vph_cd - 13'd1;
            end
        end
        if (pxl_cen) vs_t_q <= vs_t;
    end
    // VSync del modulo: com'e' con V-Shift 0, ritardato alla fase giusta altrimenti (registrato al pxl_cen come hs_in_q)
    wire vs_shifted = (vtap == 9'd0) ? vs_in_q : vs_t_q;

    // HSync emitted by the module: shifted only in HPOS_SYNCSHIFT, else native.
    // (hsync_pix_shreg / hs_shifted are computed above, before the read side.)
    wire hs_pos_out = (HPOS_MODE == `HPOS_SYNCSHIFT) ? hs_shifted : hs_in_q;

    // ------------------------------------------------------------------
    //  Output mux. CRITICAL: when stretch is active, outputs MUST be
    //  registered @ pxl2_cen (the DAC rate), NOT @ pxl_cen (the write
    //  rate). Otherwise the fast write clock would re-sample the slow
    //  read data at write rate, breaking the "every pixel lasts exactly
    //  (16+hsize) clk cycles" property and re-introducing shimmering.
    //  In bypass mode, registers run at pxl_cen for full passthrough.
    // ------------------------------------------------------------------
    // Bypass controllato dall'ON/OFF: OFF -> passthrough nativo puro.
    // ON -> modulo sempre attivo (anche con hsize=0/hoffset=0), cosi` H-Position
    // e V-Shift funzionano anche senza scala.
    wire bypass = ~active;

    initial begin
        r_out = 0; g_out = 0; b_out = 0;
        hs_out = 0; vs_out = 0; hb_out = 1; vb_out = 0;
    end

    always @(posedge clk) begin
        if (bypass) begin
            if (pxl_cen) begin
                r_out  <= r_in_q;
                g_out  <= g_in_q;
                b_out  <= b_in_q;
                hb_out <= hb_in_q;
                hs_out <= hs_in_q;
                vs_out <= vs_in_q;
                vb_out <= vb_in_q;
            end
        end else begin
            if (pxl2_cen) begin
                if (pass_q) begin
                    r_out <= rd_r8;
                    g_out <= rd_g8;
                    b_out <= rd_b8;
                end else begin
                    r_out <= 8'd0;
                    g_out <= 8'd0;
                    b_out <= 8'd0;
                end
                hb_out <= ~pass_q;
                hs_out <= hs_pos_out;   // HPOS_SYNCSHIFT -> shifted HSync, else native
                vs_out <= vs_shifted;   // V-Shift interno (VSync shiftato)
                vb_out <= vb_in_q;
            end
        end
    end

endmodule
