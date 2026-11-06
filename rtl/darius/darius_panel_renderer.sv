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

    Author: Umberto Parisi (rmonic79)
    Version: 1.0
    Date: 2026

*/

// darius_panel_renderer — Tile renderer parametrico single-panel.
// Istanziato 3 volte in parallelo (L/C/R) per comporre lo schermo virtuale
// a 864 pixel tipico di Darius. Ogni instance renderizza H_PIXELS (288)
// pixel a partire da X_OFFSET. VRAM e palette replicate per instance
// (CPU writes fan out from parent).
//
// Double-width PC080SN layout:
//   VRAM $0000-$1FFF: attributes (color[8:0], flip[15:14])
//   VRAM $2000-$3FFF: tile codes ([13:0])
//   Tilemap: 128x64 tiles, 8x8 pixels each

module darius_panel_renderer
#(
	parameter [9:0] X_OFFSET = 10'd0,
	parameter [9:0] H_PIXELS = 10'd288,
	parameter       SS_IDX   = -1      // savestate: indice slave palette (pattern F2)
)
(
	input  wire        clk,
	input  wire        reset,

	// Savestate (pattern F2: ssbus dentro al chip) — palette locale
	ssbus_if.slave     ssbus,
	// Savestate: load registri scroll/ctrl al restore (da auto_save_adaptor nel top)
	input  wire        ss_regs_ld,
	input  wire [15:0] ss_xs0, ss_xs1, ss_ys0, ss_ys1, ss_c0, ss_c1,
	input  wire  [9:0] render_x,
	input  wire  [8:0] render_y,
	input  wire  [8:0] render_y_next,   // riga sorgente della riga di display dopo (CRT Shrink); spento = render_y+1
	input  wire  [8:0] render_y_first,  // prima riga del quadro dopo (CRT Shrink interlacciato); altrimenti 0

	// CPU bus sniff (scroll/ctrl registers only)
	input  wire [23:0] cpu_bus_addr,
	input  wire        cpu_bus_asn,
	input  wire        cpu_bus_rnw,
	input  wire  [1:0] cpu_bus_dsn,
	input  wire [15:0] cpu_bus_wdata,
	input  wire        cpu_bus_cs,
	// Sub CPU palette write (direct from subcpu_map)
	input  wire        sub_pal_wr,
	input  wire [10:0] sub_pal_addr,
	input  wire [15:0] sub_pal_wdata,
	input  wire  [1:0] sub_pal_be,

	// Shared VRAM read (via arbiter)
	output reg  [14:0] vram_rd_addr,
	output reg         vram_rd_req,     // pulse when new address set
	input  wire [15:0] vram_rd_data,
	input  wire        vram_rd_valid,

	// Tile ROM (porta propria di sdrc_darius)
	input  wire [31:0] tilerom_data,
	input  wire        tilerom_valid,
	output reg  [23:0] tilerom_addr,
	output reg         tilerom_req,

	// Scroll outputs (directly from registers, active on all instances)
	output wire [15:0] xscroll_l0, xscroll_l1,
	output wire [15:0] yscroll_l0, yscroll_l1,
	output wire [15:0] ctrl_l0, ctrl_l1,

	// Pixel output
	output wire [23:0] tile_rgb,
	output wire  [1:0] tile_prio,
	output wire        tile_opaque,

	// OSD adjustable offsets per layer
	input  wire signed [9:0] l0_xoff, l0_yoff,
	input  wire signed [9:0] l1_xoff, l1_yoff,

	// Debug: coordinate mapping probe (reuses existing outputs)
	output reg  [15:0] dbg_tile_code,
	output reg  [15:0] dbg_tile_attr,
	output reg  [31:0] dbg_tile_romdata
);

// =====================================================================
// CPU bus write detection
// =====================================================================
// VRAM writes handled externally (shared VRAM in dual68k_top)
wire yscroll_sel = (cpu_bus_addr >= 24'hD20000) && (cpu_bus_addr <= 24'hD20003);
wire xscroll_sel = (cpu_bus_addr >= 24'hD40000) && (cpu_bus_addr <= 24'hD40003);
wire ctrl_sel    = (cpu_bus_addr >= 24'hD50000) && (cpu_bus_addr <= 24'hD50003);
wire palette_sel = (cpu_bus_addr >= 24'hD80000) && (cpu_bus_addr <= 24'hD80FFF);

wire write_active = ~cpu_bus_asn && ~cpu_bus_rnw && cpu_bus_cs && (cpu_bus_dsn != 2'b11);
reg write_seen;
always @(posedge clk) begin
	if (reset) write_seen <= 1'b0;
	else if (!write_active) write_seen <= 1'b0;
	else write_seen <= 1'b1;
end
wire wr_pulse = write_active && !write_seen;

// =====================================================================
// Scroll / control registers
// =====================================================================
reg [15:0] xscroll [0:1];
reg [15:0] yscroll [0:1];
reg [15:0] ctrl    [0:1];
wire layer_sel = cpu_bus_addr[1];

always @(posedge clk) begin
	if (reset) begin
		xscroll[0] <= 0; xscroll[1] <= 0;
		yscroll[0] <= 0; yscroll[1] <= 0;
		ctrl[0]    <= 0; ctrl[1]    <= 0;
	end else if (ss_regs_ld) begin
		// restore savestate: ricarica i registri (CPU ferme)
		xscroll[0] <= ss_xs0; xscroll[1] <= ss_xs1;
		yscroll[0] <= ss_ys0; yscroll[1] <= ss_ys1;
		ctrl[0]    <= ss_c0;  ctrl[1]    <= ss_c1;
	end else if (wr_pulse) begin
		if (xscroll_sel) xscroll[layer_sel] <= cpu_bus_wdata;
		if (yscroll_sel) yscroll[layer_sel] <= cpu_bus_wdata;
		if (ctrl_sel)    ctrl[layer_sel]    <= cpu_bus_wdata;
	end
end
assign xscroll_l0 = xscroll[0]; assign xscroll_l1 = xscroll[1];
assign yscroll_l0 = yscroll[0]; assign yscroll_l1 = yscroll[1];
assign ctrl_l0 = ctrl[0]; assign ctrl_l1 = ctrl[1];

// =====================================================================
// VRAM — external shared (via arbiter), no local copy
// =====================================================================
// vram_rd_addr, vram_rd_data, vram_rd_valid come from ports above

// =====================================================================
// Palette RAM
// =====================================================================
wire pal_wr = wr_pulse && palette_sel;
wire [10:0] pal_cpu_addr = cpu_bus_addr[11:1];
wire  [1:0] pal_cpu_be = ~cpu_bus_dsn;

(* ramstyle = "M10K,no_rw_check", ram_init_file = "rtl/darius/pal_init_hi.mif" *) reg [7:0] pal_ram_hi [0:2047];
(* ramstyle = "M10K,no_rw_check", ram_init_file = "rtl/darius/pal_init_lo.mif" *) reg [7:0] pal_ram_lo [0:2047];
reg [15:0] pal_data;
wire [10:0] pal_lookup_addr;   // 48 MHz: combinatorio (assegnato sotto), il registro di pal_data resta

// Savestate: adaptor sulla gamba SUB (durante SS le CPU sono ferme, la gamba
// è libera); gather-read sull'indirizzo muxato della porta di scrittura
// (stessa porta fisica), lookup renderer sull'altra porta. 2 porte = M10K TDP.
wire        sspl_we_lo, sspl_we_hi;
wire [10:0] sspl_addr;
wire [15:0] sspl_wdata;
reg  [15:0] pal_ss_q;
ss_ram16_adaptor #(.WIDTHAD(11), .SS_IDX(SS_IDX)) u_ss_pal (
	.clk(clk),
	.we_lo_in(sub_pal_wr & sub_pal_be[0]),
	.we_hi_in(sub_pal_wr & sub_pal_be[1]),
	.addr_in(sub_pal_addr),
	.wdata_in(sub_pal_wdata),
	.we_lo_out(sspl_we_lo), .we_hi_out(sspl_we_hi),
	.addr_out(sspl_addr), .wdata_out(sspl_wdata),
	.q_in(pal_ss_q),
	.ssbus(ssbus)
);

wire [10:0] pal_b_addr  = pal_wr ? pal_cpu_addr   : sspl_addr;
wire [15:0] pal_b_wdata = pal_wr ? cpu_bus_wdata  : sspl_wdata;
wire        pal_b_we_hi = pal_wr ? pal_cpu_be[1]  : sspl_we_hi;
wire        pal_b_we_lo = pal_wr ? pal_cpu_be[0]  : sspl_we_lo;

always @(posedge clk) begin
	if (pal_b_we_hi) pal_ram_hi[pal_b_addr] <= pal_b_wdata[15:8];
	if (pal_b_we_lo) pal_ram_lo[pal_b_addr] <= pal_b_wdata[7:0];
	pal_ss_q <= {pal_ram_hi[pal_b_addr], pal_ram_lo[pal_b_addr]};
	pal_data <= {pal_ram_hi[pal_lookup_addr], pal_ram_lo[pal_lookup_addr]};
end

// =====================================================================
// Line buffer renderer (prefetch from SDRAM)
// =====================================================================
localparam [9:0] LAST_PIXEL = H_PIXELS - 10'd1;
localparam V_ACTIVE = 9'd224;

// Panel-local coordinates
wire [9:0] local_x = render_x - X_OFFSET;
wire in_my_panel = (render_x >= X_OFFSET) && (render_x < (X_OFFSET + H_PIXELS));
wire in_active_area = in_my_panel && (render_y < V_ACTIVE);

reg  in_active_area_r;
reg  [8:0] prev_render_y;
wire start_of_line = in_active_area && (render_y != prev_render_y);

// Double-buffered line buffers: 14-bit entries {prio[1:0], opaque, pal_bank[6:0], pixel[3:0]}
// 512 entries (next power-of-2 above 288)
(* ramstyle = "no_rw_check" *) reg [13:0] linebuf0 [0:511];
(* ramstyle = "no_rw_check" *) reg [13:0] linebuf1 [0:511];
(* ramstyle = "no_rw_check" *) reg [13:0] linebuf0_q, linebuf1_q;

reg        display_buf_sel;
reg        display_line_valid;
reg [13:0] display_word;
wire [8:0] display_rd_addr;    // 48 MHz: combinatorio, letto dal line buffer nel registro linebufX_q
// Prefetch next pixel; last pixel wraps to itself (already displayed)
wire [8:0] display_lookup_x = (local_x[8:0] < LAST_PIXEL[8:0]) ? (local_x[8:0] + 9'd1) : LAST_PIXEL[8:0];
// 02/11, 48 MHz: l'indirizzo non e' piu' registrato (era il registro per il timing a 96). Stesso gate di prima.
assign display_rd_addr = in_active_area ? display_lookup_x : 9'd0;

always @(posedge clk) begin
	linebuf0_q <= linebuf0[display_rd_addr];
	linebuf1_q <= linebuf1[display_rd_addr];
end

// (mux display_word: piu' sotto, dopo le dichiarazioni di prep_*)

// Prep state machine
reg        prep_buf_sel;
reg        prep_busy;
reg        prep_line_ready;
reg  [8:0] prep_line_y;
// 02/11, 48 MHz: nel clock di inizio riga lo scambio dei buffer (start_of_line) non e' ancora registrato, ma il
// primo pixel del pannello passa gia' dal mux: si usano i valori che lo scambio carica.
wire swap_now       = start_of_line && prep_line_ready && (prep_line_y == render_y);
wire disp_valid_eff = start_of_line ? swap_now : display_line_valid;
wire disp_sel_eff   = swap_now ? prep_buf_sel : display_buf_sel;
always @(*) begin
	if (!disp_valid_eff || !in_active_area)
		display_word = 14'd0;
	else if (disp_sel_eff)
		display_word = linebuf1_q;
	else
		display_word = linebuf0_q;
end
reg  [9:0] prep_out_x;
reg  [2:0] prep_pix_idx;
reg  [6:0] prep_pal_bank;
reg        prep_hflip;
reg [31:0] prep_tile_row;
reg        prep_linebuf_we;
reg  [8:0] prep_linebuf_addr;
reg [13:0] prep_linebuf_data;
reg        prep_layer;  // 0=Layer0 (background), 1=Layer1 (foreground)
// riga da preparare per la riga di display dopo: render_y_next (CRT Shrink), a 0 dopo l'ultima (224).
// Con shrink spento render_y_next = render_y+1: identico a ((render_y >= V_ACTIVE-1) ? 0 : render_y+1) di prima
// per ogni render_y < V_ACTIVE, l'unico caso in cui si prepara (start_of_line); sul ramo dello scambio
// prep_line_y == render_y, quindi anche il prep_next_line_y di prima era questo valore.
wire [8:0] prep_next_line_y = (render_y_next >= V_ACTIVE) ? render_y_first : render_y_next;   // 0 senza interlacciato

// Latched scroll + ctrl per layer — captured at start of each line prep (like HBlank latch in real PC080SN)
reg  [9:0] prep_xscroll_lat  [0:1];
reg  [8:0] prep_yscroll_lat  [0:1];
reg        prep_ctrl_bit0_lat [0:1];

// Source pixel coordinates with scroll + panel offset (selects by current layer)
// MAME set_offsets(-16, 8): L0 xoff=-16, L1 xoff=+8
// MAME Y: L0 +8, L1 0
wire signed [9:0] layer_xoff = 10'sd0;
wire signed [9:0] layer_yoff = 10'sd0;

// Tile pixel extraction (packed MSB: 2 pixels per byte, MSB first)
function automatic [3:0] get_pixel;
	input [31:0] row_data;
	input        hflip;
	input [2:0]  pix_idx;
	reg [4:0] shift;
	begin
		shift = hflip ? {pix_idx, 2'b00} : {(3'd7 - pix_idx), 2'b00};
		get_pixel = (row_data >> shift) & 4'hF;
	end
endfunction

// Catena di preparazione della riga (03/11, 48 MHz): tre stadi che lavorano insieme sui tile in fila.
//   V: legge dalla VRAM attributo e codice del tile (attraverso l'arbitro dei tre pannelli);
//   Q: un posto fra V e R, cosi' V legge il tile dopo mentre R aspetta la ROM;
//   R: chiede alla ROM grafica la riga del tile e ne tiene il dato;
//   D: scrive i pixel del tile nel line buffer, uno per clock (come P_WRITE_PIX della catena di prima).
// Stessi tile nello stesso ordine (layer 0 poi layer 1, da out_x 0 a LAST_PIXEL), stessi indirizzi, stessi pixel: cambia
// solo che V e R lavorano sui tile dopo mentre D disegna, e il costo di un tile e' il maggiore fra l'attesa della ROM, le
// due letture VRAM e il disegno invece della somma. Con la catena in fila la scena delle navi wireframe (attract) non
// finiva le righe del pannello centrale, a 48 e gia' a 96 MHz. Ogni stadio passa il tile al successivo quando e' libero;
// a inizio riga tutti ripartono e una lettura VRAM o ROM ancora in volo si aspetta e se ne scarta la risposta.
localparam [2:0] V_ATTR = 3'd0, V_WATTR = 3'd1, V_CODE = 3'd2, V_WCODE = 3'd3, V_DONE = 3'd4, V_END = 3'd5;
reg  [2:0] v_state;
reg  [9:0] v_out_x;       // primo pixel d'uscita del tile
reg        v_layer;
reg  [2:0] v_pix;         // primo pixel dentro il tile (scroll fine)
reg  [2:0] v_fine_y;
reg [12:0] v_index;
reg [15:0] v_attr;
reg [13:0] v_code;
reg        v_pend;        // lettura VRAM in volo
reg        v_drop;        // la risposta in volo e' di una riga abbandonata: si scarta
wire [9:0]  v_src_x      = v_out_x + X_OFFSET - prep_xscroll_lat[v_layer] + layer_xoff;
wire [8:0]  v_src_y      = prep_line_y - prep_yscroll_lat[v_layer] + layer_yoff[8:0];
wire [12:0] v_tile_index = {v_src_y[8:3], v_src_x[9:3]};
wire [10:0] v_next_x     = {1'b0, v_out_x} + 11'd8 - {8'd0, v_pix};   // primo pixel d'uscita del tile dopo

// Q: un tile letto da V in attesa di R (V lavora sul tile dopo mentre R aspetta la ROM)
reg        q_full;
reg  [9:0] q_out_x;
reg        q_layer;
reg  [2:0] q_pix;
reg  [2:0] q_fine_y;
reg [15:0] q_attr;
reg [13:0] q_code;

localparam [1:0] R_EMPTY = 2'd0, R_REQ = 2'd1, R_FULL = 2'd2;
reg  [1:0] r_state;
reg  [9:0] r_out_x;
reg        r_layer;
reg  [2:0] r_pix;
reg  [6:0] r_pal;
reg        r_hflip;
reg [31:0] r_row;
reg        r_pend;        // lettura ROM in volo
reg        r_drop;

// D disegna un tile con prep_out_x, prep_pix_idx, prep_tile_row, prep_hflip, prep_pal_bank, prep_layer
reg        d_active;
wire       d_last_pix = d_active && (prep_out_x == LAST_PIXEL || prep_pix_idx == 3'd7);   // ultimo pixel del tile
wire       d_line_end = d_active && (prep_out_x == LAST_PIXEL) && prep_layer;             // ultimo pixel della riga
wire       d_take     = (!d_active || d_last_pix) && !d_line_end && (r_state == R_FULL);

always @(posedge clk) begin
	prep_linebuf_we <= 1'b0;
	vram_rd_req <= 1'b0;  // default: pulse off

	if (reset) begin
		vram_rd_req       <= 0;
		in_active_area_r  <= 0;
		prev_render_y     <= 9'h1FF;
		display_buf_sel   <= 0;
		display_line_valid <= 0;
		prep_buf_sel      <= 1;
		prep_busy         <= 1;
		prep_line_ready   <= 0;
		prep_line_y       <= 0;
		prep_out_x        <= 0;
		v_state <= V_ATTR; v_out_x <= 10'd0; v_layer <= 1'b0; v_pend <= 1'b0; v_drop <= 1'b0;
		q_full <= 1'b0; r_state <= R_EMPTY; r_pend <= 1'b0; r_drop <= 1'b0; d_active <= 1'b0;
		tilerom_req       <= 0;
		tilerom_addr      <= 0;
		prep_tile_row     <= 0;
		prep_pal_bank     <= 0;
		prep_hflip        <= 0;
		prep_pix_idx      <= 0;
		prep_layer        <= 0;
		prep_xscroll_lat[0]  <= 0; prep_xscroll_lat[1]  <= 0;
		prep_yscroll_lat[0]  <= 0; prep_yscroll_lat[1]  <= 0;
		prep_ctrl_bit0_lat[0] <= 0; prep_ctrl_bit0_lat[1] <= 0;
	end else begin
		in_active_area_r <= in_active_area;
		if (start_of_line) prev_render_y <= render_y;

		// Start of visible line: swap buffers if prep matches display
		if (start_of_line) begin
			// Latch scroll + ctrl for both layers at line boundary (matches real PC080SN HBlank latch)
			prep_xscroll_lat[0]   <= xscroll[0][9:0]; prep_xscroll_lat[1]   <= xscroll[1][9:0];
			prep_yscroll_lat[0]   <= yscroll[0][8:0]; prep_yscroll_lat[1]   <= yscroll[1][8:0];
			prep_ctrl_bit0_lat[0] <= ctrl[0][0];      prep_ctrl_bit0_lat[1] <= ctrl[1][0];
			if (prep_line_ready && (prep_line_y == render_y)) begin
				display_buf_sel    <= prep_buf_sel;
				display_line_valid <= 1'b1;
				prep_buf_sel       <= ~prep_buf_sel;
				prep_line_y        <= prep_next_line_y;
				prep_out_x         <= 0;
				prep_busy          <= 1;
				prep_line_ready    <= 0;
				prep_layer         <= 0;
			end else begin
				display_line_valid <= 1'b0;
				prep_line_y        <= prep_next_line_y;
				prep_out_x         <= 0;
				prep_busy          <= 1;
				prep_line_ready    <= 0;
				prep_layer         <= 0;
			end
		end

		// Catena di preparazione: risposte in volo, inizio riga, poi i tre stadi
		if (vram_rd_valid) begin v_pend <= 1'b0; v_drop <= 1'b0; end
		if (tilerom_valid) begin r_pend <= 1'b0; r_drop <= 1'b0; end
		if (start_of_line) begin
			v_state  <= V_ATTR; v_out_x <= 10'd0; v_layer <= 1'b0;
			if (v_pend && !vram_rd_valid) v_drop <= 1'b1;
			q_full   <= 1'b0;
			r_state  <= R_EMPTY;
			if (r_pend && !tilerom_valid) r_drop <= 1'b1;
			tilerom_req <= 1'b0;
			d_active <= 1'b0;
		end else if (prep_busy) begin
			// ---- V: attributo e codice dalla VRAM
			case (v_state)
				V_ATTR: if (!v_pend) begin
					v_pix        <= v_src_x[2:0];
					v_fine_y     <= v_src_y[2:0];
					v_index      <= v_tile_index;
					vram_rd_addr <= {(v_layer ? 2'b10 : 2'b00), v_tile_index};   // attributo: L0 00, L1 10
					vram_rd_req  <= 1'b1;
					v_pend       <= 1'b1;
					v_state      <= V_WATTR;
				end
				V_WATTR: if (vram_rd_valid) begin v_attr <= vram_rd_data; v_state <= V_CODE; end
				V_CODE: begin
					vram_rd_addr <= {(v_layer ? 2'b11 : 2'b01), v_index};        // codice: L0 01, L1 11
					vram_rd_req  <= 1'b1;
					v_pend       <= 1'b1;
					v_state      <= V_WCODE;
				end
				V_WCODE: if (vram_rd_valid) begin v_code <= vram_rd_data[13:0]; v_state <= V_DONE; end
				default: ;   // V_DONE: aspetta che R prenda il tile; V_END: riga finita
			endcase

			// ---- Q -> R: R vuoto e nessuna lettura ROM in volo
			if (q_full && r_state == R_EMPTY && !r_pend) begin
				r_out_x <= q_out_x;
				r_layer <= q_layer;
				r_pix   <= q_pix;
				r_pal   <= q_attr[6:0];
				r_hflip <= q_attr[14] ^ prep_ctrl_bit0_lat[q_layer];
				if (q_code == 14'd0 || q_code >= 14'd12288) begin
					r_row   <= 32'd0;
					r_state <= R_FULL;
				end else begin
					tilerom_addr <= {5'd0, q_code, (q_fine_y ^ {3{q_attr[15] ^ prep_ctrl_bit0_lat[q_layer]}}), 2'b00};
					tilerom_req  <= 1'b1;
					r_pend       <= 1'b1;
					r_state      <= R_REQ;
				end
				q_full <= 1'b0;
			end

			// ---- V -> Q: Q vuoto, o si svuota in questo clock
			if (v_state == V_DONE && (!q_full || (r_state == R_EMPTY && !r_pend))) begin
				q_out_x  <= v_out_x;
				q_layer  <= v_layer;
				q_pix    <= v_pix;
				q_fine_y <= v_fine_y;
				q_attr   <= v_attr;
				q_code   <= v_code;
				q_full   <= 1'b1;
				// V passa al tile dopo: fine del layer 0 -> layer 1 da out_x 0; fine del layer 1 -> riga finita per V
				if (v_next_x > {1'b0, LAST_PIXEL}) begin
					if (!v_layer) begin v_layer <= 1'b1; v_out_x <= 10'd0; v_state <= V_ATTR; end
					else v_state <= V_END;
				end else begin
					v_out_x <= v_next_x[9:0];
					v_state <= V_ATTR;
				end
			end

			// ---- R: dato della ROM (la richiesta torna bassa: la porta parte sul fronte di salita)
			if (r_state == R_REQ && tilerom_valid && !r_drop) begin
				r_row       <= tilerom_data;
				tilerom_req <= 1'b0;
				r_state     <= R_FULL;
			end

			// ---- D: un pixel per clock (Layer 0: sempre; Layer 1: solo i pixel opachi, come prima)
			if (d_active) begin
				if (prep_layer == 1'b0 || get_pixel(prep_tile_row, prep_hflip, prep_pix_idx) != 4'd0) begin
					prep_linebuf_we <= 1'b1;
					prep_linebuf_addr <= prep_out_x[8:0];
					// prio: L0=01, L2=10 (matches MAME priority bitmap values)
					prep_linebuf_data <= {(prep_layer ? 2'b10 : 2'b01),
						(get_pixel(prep_tile_row, prep_hflip, prep_pix_idx) != 4'd0),
						prep_pal_bank,
						get_pixel(prep_tile_row, prep_hflip, prep_pix_idx)};
				end
				if (prep_out_x == LAST_PIXEL) begin
					d_active <= 1'b0;
					if (prep_layer) begin            // fine del layer 1: riga completa
						prep_layer      <= 1'b0;
						prep_busy       <= 1'b0;
						prep_line_ready <= 1'b1;
					end
				end else begin
					prep_out_x <= prep_out_x + 10'd1;
					if (prep_pix_idx == 3'd7) d_active <= 1'b0;
					else prep_pix_idx <= prep_pix_idx + 3'd1;
				end
			end

			// ---- R -> D: D libero o all'ultimo pixel del tile (nessun clock vuoto fra due tile)
			if (d_take) begin
				prep_tile_row <= r_row;
				prep_hflip    <= r_hflip;
				prep_pal_bank <= r_pal;
				prep_pix_idx  <= r_pix;
				prep_layer    <= r_layer;
				prep_out_x    <= r_out_x;
				d_active      <= 1'b1;
				r_state       <= R_EMPTY;
			end
		end

		// Write to line buffer
		if (prep_linebuf_we) begin
			if (prep_buf_sel)
				linebuf1[prep_linebuf_addr] <= prep_linebuf_data;
			else
				linebuf0[prep_linebuf_addr] <= prep_linebuf_data;
		end
	end
end

// =====================================================================
// Display output: line buffer -> palette -> RGB
// =====================================================================
wire [3:0] disp_pixel = display_word[3:0];
wire [6:0] disp_pal   = display_word[10:4];
wire       disp_opaque = display_word[11];
wire [1:0] disp_prio   = display_word[13:12];

// 02/11, 48 MHz: indirizzo della palette combinatorio (era registrato per il timing a 96)
assign pal_lookup_addr = {disp_pal, disp_pixel};

// Delay opaque/prio by 2 clocks to align with pal_data:
//   Cycle N:   display_word available (combinatorial from line buffer)
//   Cycle N+1: pal_lookup_addr registered
//   Cycle N+2: pal_data registered (BRAM read)
// So opaque/prio need 2 stages to match.
reg        disp_opaque_d, disp_opaque_dd;
reg  [1:0] disp_prio_d,   disp_prio_dd;
always @(posedge clk) begin
	disp_opaque_d  <= disp_opaque;
	disp_prio_d    <= disp_prio;
	disp_opaque_dd <= disp_opaque_d;
	disp_prio_dd   <= disp_prio_d;
end

// xBGR555 -> RGB888
wire [7:0] out_r = {pal_data[4:0],  pal_data[4:2]};
wire [7:0] out_g = {pal_data[9:5],  pal_data[9:7]};
wire [7:0] out_b = {pal_data[14:10], pal_data[14:12]};

assign tile_rgb    = {out_r, out_g, out_b};
assign tile_opaque = disp_opaque_d;    // 48 MHz: un registro dopo display_word, come pal_data
assign tile_prio   = disp_prio_d;

// Debug: coordinate mapping probe
// Captures the mapping triad at out_x=0 and out_x=112 on first target line
// Uses existing dbg_tile_code/attr/romdata outputs (already wired to overlay)
// Format:
//   dbg_tile_code   = {6'b0, src_x[9:0]}  at out_x=0
//   dbg_tile_attr   = {3'b0, tile_index[12:0]} at out_x=0
//   dbg_tile_romdata = {src_y[8:0], prep_line_y[8:0], code_at_0[13:0]}
// (03/11) la sonda leggeva gli stati della catena di prima; le uscite non sono collegate nel top: a zero
always @(posedge clk) begin
	dbg_tile_code    <= 16'd0;
	dbg_tile_attr    <= 16'd0;
	dbg_tile_romdata <= 32'd0;
end


endmodule
