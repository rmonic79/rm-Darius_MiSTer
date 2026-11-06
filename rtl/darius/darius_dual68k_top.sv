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

// darius_dual68k_top — Top-level del core Darius.
// Istanzia entrambe le CPU 68000 (main + sub), memory maps, shared/sprite/
// FG/palette RAM, sprite renderer, FG renderer, 3 panel renderer (L/C/R),
// vram arbiter, sdram bridge, audio Z80 subsystem, triple screen composer.

module darius_dual68k_top
#(
	parameter [1:0] MAIN_CORE_IMPL    = 2'd1,
	parameter [1:0] SUB_CORE_IMPL     = 2'd1,
	parameter       HOLD_SUB_IN_RESET = 1'b0,
	parameter       ENABLE_C00050_NOP = 1'b1,
	parameter       ENABLE_WATCHDOG   = 1'b1,
	parameter       ENABLE_PC080_CTRL = 1'b1,
	parameter       ENABLE_DC0000     = 1'b1,
	parameter       ENABLE_C00060     = 1'b1,
	parameter       ENABLE_C00020     = 1'b1,
	parameter       ENABLE_C00022     = 1'b1,
	parameter       ENABLE_C00024     = 1'b1,
	parameter       ENABLE_C00030     = 1'b1,
	parameter       ENABLE_C00032     = 1'b1,
	parameter       ENABLE_C00034     = 1'b1,
	parameter       ENABLE_D40000     = 1'b1,
	parameter       ENABLE_D40002     = 1'b1,
	parameter       ENABLE_D20000     = 1'b1,
	parameter       ENABLE_D20002     = 1'b1,
	parameter       ENABLE_C0000C     = 1'b1,
	parameter       ENABLE_C00010     = 1'b1,
	parameter       ENABLE_MAIN_PC060HA_PORT = 1'b1,
	parameter       ENABLE_MAIN_PC060HA_COMM = 1'b1,
	parameter       ENABLE_MAIN_D00000 = 1'b1,
	parameter       ENABLE_MAIN_PALETTE = 1'b1,
	parameter       ENABLE_FG_RAM      = 1'b1,
	parameter       ENABLE_MAIN_CTRL  = 1'b1,
	parameter       ENABLE_MAIN_SHARED = 1'b1,
	parameter       ENABLE_MAIN_SPRITE = 1'b1,
	parameter       ENABLE_MAIN_IO    = 1'b1,
	parameter       ENABLE_MAIN_VIDEO = 1'b1,
	parameter       ENABLE_MAIN_PLAYER_IO = 1'b1,
	parameter       ENABLE_SUB_SHARED = 1'b1,
	parameter       ENABLE_SUB_SPRITE = 1'b1,
	parameter       ENABLE_SUB_PALETTE = 1'b1,
	parameter       ENABLE_SUB_IO     = 1'b1,
	parameter       ENABLE_VBLANK_IRQ = 1'b1
)
(
	input  wire        clk,
	input  wire        reset,
	input  wire        pause,
	input  wire  [2:0] clk_sel,      // Main CPU: 000=8MHz, 001=12MHz, 010=16MHz, 011=24MHz, 100=32MHz*, 101=48MHz*
	input  wire  [2:0] sub_clk_sel,   // Sub CPU: 000=8MHz, 001=12MHz, 010=16MHz, 011=24MHz, 100=32MHz*, 101=48MHz*
	input  wire  [1:0] z80_clk_sel,  // Z80: 00=4MHz, 01=8MHz, 10=2MHz, 11=1MHz
	input  wire  [7:0] p1_input,
	input  wire  [7:0] p2_input,
	input  wire  [7:0] system_input,   // MAME SYSTEM port: {00,start2,start1,tilt,service,coin2,coin1}
	input  wire [15:0] dsw_input,
	input  wire [15:0] main_rom_rdata,
	input  wire        main_rom_ready,
	input  wire [15:0] sub_rom_rdata,
	input  wire        sub_rom_ready,
	input  wire [9:0]  render_x,
	input  wire [8:0]  render_y,        // riga sorgente mostrata (compressa con CRT Shrink): ai renderer
	input  wire [8:0]  render_y_next,   // riga sorgente da preparare per la riga dopo: ai renderer
	input  wire [8:0]  render_y_first,  // prima riga del quadro dopo (CRT Shrink interlacciato; altrimenti 0): ai renderer
	input  wire [1:0]  spr_snap,        // CRT Shrink: Y degli sprite alla griglia della finestra (status[29:28]; 0 niente)
	input  wire [8:0]  render_y_nat,    // riga NATURALE: IRQ4 e savestate, mai compressa
	input  wire [31:0] tilerom_data,
	input  wire        tilerom_valid,
	output wire [23:0] main_rom_addr,
	output wire        main_rom_req,
	output wire [23:0] sub_rom_addr,
	output wire        sub_rom_req,
	output wire [23:0] tilerom_addr,
	output wire        tilerom_req,
	output wire        tilerom_is_sprite,
	output wire        tilerom_is_text,
	// GFX ROM, una porta per cliente verso sdrc_darius:
	// 0 = pannello sinistro, 1 = centrale, 2 = destro, 3 = sprite. req a livello, valid impulso col dato.
	output wire  [3:0] gfx_req,
	output wire [95:0] gfx_addr,
	input  wire [127:0] gfx_data,
	input  wire  [3:0] gfx_valid,
	// Audio ROM download (ioctl → BRAM inside audio module)
	input  wire        ioctl_download,
	input  wire        ioctl_wr,
	input  wire [26:0] ioctl_addr,
	input  wire [15:0] ioctl_dout,
	output wire [23:0] fg_rgb,
	output wire        fg_opaque,
	output wire [15:0] xscroll_l0,
	output wire [15:0] xscroll_l1,
	output wire [15:0] yscroll_l0,
	output wire [15:0] yscroll_l1,
	output wire [15:0] ctrl_l0,
	output wire [15:0] ctrl_l1,
	output wire [23:0] tile_rgb,
	output wire [1:0]  tile_prio,
	output wire        tile_opaque,
	output wire [23:0] sprite_rgb,
	output wire  [1:0] sprite_prio,
	output wire        sprite_opaque,
	// Follow-cam: tracking navicella
	output wire  [9:0] ship_x,
	output wire        ship_commit,
	// OSD layer offsets
	input  wire signed [9:0] l0_xoff, l0_yoff,
	input  wire signed [9:0] l1_xoff, l1_yoff,
	input  wire signed [9:0] spr_xoff, spr_yoff,
	input  wire signed [9:0] fg_xoff, fg_yoff,
	// Text ROM download for FG BRAM
	input  wire        fg_dl_wr,
	input  wire [13:0] fg_dl_addr,
	input  wire [15:0] fg_dl_data,
	// Audio ROM DDR3 (passthrough verso darius_audio_z80)
	output wire        audio_ioctl_wait,
	input  wire        DDRAM_BUSY,
	output wire  [7:0] DDRAM_BURSTCNT,
	output wire [28:0] DDRAM_ADDR,
	input  wire [63:0] DDRAM_DOUT,
	input  wire        DDRAM_DOUT_READY,
	output wire        DDRAM_RD,
	output wire [63:0] DDRAM_DIN,
	output wire  [7:0] DDRAM_BE,
	output wire        DDRAM_WE,
	// Savestate (trigger da savestate_ui nel Template)
	input  wire        ss_save,
	input  wire        ss_load,
	input  wire  [3:0] ss_slot,
	input  wire        paused_real,    // paused_safe registrato a vblank (Template)
	output wire        ss_pause_out,   // verso il hook ss_pause di paused_safe
	// OSD mixer gain: 9 selettori 4-bit (default = 4'd0 -> mixer invariato)
	input  wire [3:0]  mix_sel_fm0, mix_sel_fm1,
	input  wire [3:0]  mix_sel_p0a, mix_sel_p0b, mix_sel_p0c,
	input  wire [3:0]  mix_sel_p1a, mix_sel_p1b, mix_sel_p1c,
	input  wire [3:0]  mix_sel_msm,
	// Audio output
	output wire signed [15:0] audio_l,
	output wire signed [15:0] audio_r
);

// ── Forward declarations (needed by ModelSim) ────────────────────────────
wire [23:0] main_bus_addr;
wire [23:0] sub_bus_addr;
wire        main_bus_asn;
wire        sub_bus_asn;
wire        main_bus_rnw;
wire        sub_bus_rnw;
wire [1:0]  main_bus_dsn;
wire [1:0]  sub_bus_dsn;
wire [15:0] main_bus_dout;
wire [15:0] sub_bus_dout;
wire [15:0] main_bus_rdata;
wire [15:0] sub_bus_rdata;
wire        main_bus_cs;
wire        sub_bus_cs;
wire        main_bus_busy;
wire        sub_bus_busy;
wire [15:0] shared_main_rdata;
wire [15:0] shared_sub_rdata;
wire        shared_main_ready;
wire        shared_sub_ready;
wire        main_shared_rd;
wire        main_shared_wr;
wire [11:0] main_shared_addr;
wire [15:0] main_shared_wdata;
wire        sub_shared_rd;
wire        sub_shared_wr;
wire [11:0] sub_shared_addr;
wire [15:0] sub_shared_wdata;
wire [15:0] main_ram_rdata;
wire [15:0] main_e100_rdata;
wire [15:0] sub_ram_rdata;
wire [15:0] d000_main_rdata;
wire [15:0] palette_main_rdata;
wire [15:0] sprite_main_rdata;
wire [15:0] sprite_sub_rdata;
wire        sprite_main_ready;
wire        sprite_sub_ready;
wire        main_sprite_rd;
wire        main_sprite_wr;
wire [10:0] main_sprite_addr;
wire [15:0] main_sprite_wdata;
wire        sub_sprite_rd;
wire        sub_sprite_wr;
wire [10:0] sub_sprite_addr;
wire [15:0] sub_sprite_wdata;
wire [15:0] fg_main_rdata;
wire [15:0] fg_sub_rdata;
wire        fg_main_ready;
wire        fg_sub_ready;
wire        main_fg_rd;
wire        main_fg_wr;
wire [13:0] main_fg_addr;
wire [15:0] main_fg_wdata;
wire        sub_fg_rd;
wire        sub_fg_wr;
wire [13:0] sub_fg_addr;
wire [15:0] sub_fg_wdata;
wire        main_ram_rd;
wire        main_ram_wr;
wire  [1:0] main_ram_be;
wire  [1:0] main_bus_be;
wire  [1:0] sub_bus_be = ~sub_bus_dsn;
wire [14:0] main_ram_addr;
wire [15:0] main_ram_wdata;
wire        main_e100_rd;
wire        main_e100_wr;
wire [10:0] main_e100_addr;
wire [15:0] main_e100_wdata;
wire        main_d000_rd;
wire        main_d000_wr;
wire [14:0] main_d000_addr;
wire [15:0] main_d000_wdata;
wire        main_palette_rd;
wire        main_palette_wr;
wire [10:0] main_palette_addr;
wire [15:0] main_palette_wdata;
wire        palette_main_ready;
wire        sub_palette_wr;
wire [10:0] sub_palette_addr;
wire [15:0] sub_palette_wdata;
wire        palette_sub_ready;
wire [15:0] palette_sub_rdata;
wire        sub_ram_rd;
wire        sub_ram_wr;
wire [14:0] sub_ram_addr;
wire [15:0] sub_ram_wdata;
wire        cpua_ctrl_wr;
wire [7:0]  cpua_ctrl_data;
wire        main_pc060ha_port_wr;
wire [7:0]  main_pc060ha_port_data;
wire        main_pc060ha_comm_wr;
wire [7:0]  main_pc060ha_comm_data;
reg  [7:0]  cpua_ctrl_reg;
reg  [7:0]  main_pc060ha_port_reg;
reg  [7:0]  main_pc060ha_comm_reg;
wire        main_iack;
wire        sub_iack;
wire [2:0]  main_ipl_n;
wire [2:0]  sub_ipl_n;
wire        pc060_snd_cs;
wire        pc060_snd_addr;
wire        pc060_snd_wr;
wire        pc060_snd_rd;
wire  [7:0] pc060_snd_wdata;
wire  [7:0] pc060_snd_rdata;
wire        pc060_snd_nmi_n;
wire        pc060_snd_reset;

// vblank a livello top (per il gate del save: iniettare IRQ7 solo a fine
// vblank, quando la VBL-ISR del gioco ha gia' ricompilato la lista sprite).
wire vblank_area_top = (render_y_nat >= 9'd224);

// --- VBlank IRQ4 generation (cpp: set_vblank_int irq4_line_hold, both CPUs) ---

generate if (ENABLE_VBLANK_IRQ) begin : gen_vblank_irq
	// 60Hz VBlank from render_y_nat: assert when the natural line enters vblank region
	// V_ACTIVE=224, vblank starts at vc >= 224 (render_y_nat = vc, never compressed by CRT Shrink)
	wire vblank_area = (render_y_nat >= 9'd224);
	reg  vblank_prev;
	reg  main_irq4_pending;
	reg  sub_irq4_pending;

	always @(posedge clk) begin
		if (reset) begin
			vblank_prev       <= 1'b0;
			main_irq4_pending <= 1'b0;
			sub_irq4_pending  <= 1'b0;
		end else begin
			vblank_prev <= vblank_area;
			// Rising edge of vblank → assert IRQ4
			if (vblank_area && !vblank_prev) begin
				main_irq4_pending <= 1'b1;
				sub_irq4_pending  <= 1'b1;
			end
			// Clear on the acknowledge of level 4 only (A3:A1 = 100 in the IACK cycle): the level-7 acknowledge of the external
			// savestate must not consume the request. With 4 and 7 the only levels present, A2 = 0 identifies level 4:
			// one input more on each flag (five), still one LUT.
			if (main_iack && !main_bus_addr[2]) main_irq4_pending <= 1'b0;
			if (sub_iack  && !sub_bus_addr[2])  sub_irq4_pending  <= 1'b0;
		end
	end

	// IRQ4 = level 4 → ipl_n = ~3'd4 = 3'b011
	assign main_ipl_n = main_irq4_pending ? 3'b011 : 3'b111;
	assign sub_ipl_n  = sub_irq4_pending  ? 3'b011 : 3'b111;
end else begin : gen_no_vblank
	assign main_ipl_n = 3'b111;
	assign sub_ipl_n  = 3'b111;
end
endgenerate

always @(posedge clk) begin
	if (reset)
		cpua_ctrl_reg <= 8'h00;
	else if (ss_regs_ld)
		cpua_ctrl_reg <= ss_cpua_ctrl;   // restore savestate
	else if (cpua_ctrl_wr)
		cpua_ctrl_reg <= cpua_ctrl_data;
end

always @(posedge clk) begin
	if (reset)
		main_pc060ha_port_reg <= 8'h00;
	else if (main_pc060ha_port_wr)
		main_pc060ha_port_reg <= main_pc060ha_port_data;
end

always @(posedge clk) begin
	if (reset)
		main_pc060ha_comm_reg <= 8'h00;
	else if (main_pc060ha_comm_wr)
		main_pc060ha_comm_reg <= main_pc060ha_comm_data;
end

// PC060HA — real protocol handler (jtrastan_pc060 rewrite, single clock)
wire [7:0] pc060ha_main_rdata;

// Main 68K CS: active when accessing C00000-C00003
wire pc060_main_cs = ~main_bus_asn & main_bus_cs &
                     (main_bus_addr >= 24'hC00000) & (main_bus_addr <= 24'hC00003);
wire pc060_main_addr = main_bus_addr[1];  // 0=port (C00000), 1=comm (C00002)
wire pc060_main_wr = pc060_main_cs & ~main_bus_rnw;
wire pc060_main_rd = pc060_main_cs &  main_bus_rnw;

// [SS-HOOK] wire savestate PC060HA (dichiarate prima dell'istanza)
wire [45:0] pc060_ss_out, pc060_ss_in;
wire        pc060_ss_ld;

pc060ha_link u_pc060ha (
	.clk(clk),
	.reset(reset),
	// Main 68000 side
	.main_cs(pc060_main_cs),
	.main_addr(pc060_main_addr),
	.main_wr(pc060_main_wr),
	.main_rd(pc060_main_rd),
	.main_wdata(main_bus_dout[7:0]),
	.main_rdata(pc060ha_main_rdata),
	// Sound Z80 side
	.snd_cs(pc060_snd_cs),
	.snd_addr(pc060_snd_addr),
	.snd_wr(pc060_snd_wr),
	.snd_rd(pc060_snd_rd),
	.snd_wdata(pc060_snd_wdata),
	.snd_rdata(pc060_snd_rdata),
	// Control outputs
	.snd_nmi_n(pc060_snd_nmi_n),
	.snd_reset(pc060_snd_reset),
	.dbg_snd_full(),
	.dbg_main_full(),
	// [SS-HOOK] savestate handshake
	.ss_out(pc060_ss_out),
	.ss_ld(pc060_ss_ld),
	.ss_in(pc060_ss_in)
);
auto_save_adaptor #(.N_BITS(46), .SS_IDX(SS_IDX_PC060)) u_ss_pc060 (
	.clk(clk), .ssbus(ssb[SS_IDX_PC060]),
	.bits_in(pc060_ss_out), .bits_out(pc060_ss_in), .bits_wr(pc060_ss_ld)
);

// Main CPU clock divider (48MHz / den; 02/11: clk_sys 96 -> 48)
reg [7:0] main_clk_den;
always @(*) case (clk_sel)
	3'd0: main_clk_den = 8'd6;   // 48/6  = 8MHz (original, default)
	3'd1: main_clk_den = 8'd4;   // 48/4  = 12MHz
	3'd2: main_clk_den = 8'd3;   // 48/3  = 16MHz
	3'd3: main_clk_den = 8'd2;   // 48/2  = 24MHz
	3'd4: main_clk_den = 8'd2;   // 32MHz non ottenibile da 48 (servirebbe /1,5): 24MHz
	3'd5: main_clk_den = 8'd2;   // 48MHz non ottenibile (servirebbe /1): 24MHz
	default: main_clk_den = 8'd6;
endcase

// Sub CPU clock divider (48MHz / den; 02/11: clk_sys 96 -> 48)
reg [7:0] sub_clk_den;
always @(*) case (sub_clk_sel)
	3'd0: sub_clk_den = 8'd6;   // 48/6  = 8MHz (original, default)
	3'd1: sub_clk_den = 8'd4;   // 48/4  = 12MHz
	3'd2: sub_clk_den = 8'd3;   // 48/3  = 16MHz
	3'd3: sub_clk_den = 8'd2;   // 48/2  = 24MHz
	3'd4: sub_clk_den = 8'd2;   // 32MHz non ottenibile da 48 (servirebbe /1,5): 24MHz
	3'd5: sub_clk_den = 8'd2;   // 48MHz non ottenibile (servirebbe /1): 24MHz
	default: sub_clk_den = 8'd6;
endcase

// Savestate dei 68000: m68k_ss_seq (piu' sotto) sostituisce il dato e l'IPL delle due CPU e ne comanda pausa e
// reset; qui i function code che gli servono.
wire [2:0]  main_fc, sub_fc;
// (SS7) savestate esterno dei due 68000 verso i nodi: comandi da flop; mux del dato e dell'IPL qui, nella forma del
// savestate del gioco (halt_n = ~(pausa & ~exec), IPL 7 / nascosto / sistema, dato sostituito / mappa)
wire        ss68_m_exec, ss68_s_exec, ss68_m_ovr, ss68_s_ovr, ss68_m_ssp, ss68_s_ssp;
wire        ss68_m_i7, ss68_s_i7, ss68_m_hide, ss68_s_hide, ss68_m_srst, ss68_s_srst;
wire [15:0] ss68_word, ss68_sec_word;

darius_cpu_node #(
	.CPU_ID(1'b0),
	.CORE_IMPL(MAIN_CORE_IMPL)
) u_main_cpu (
	.clk(clk),
	.reset(reset),
	.soft_reset(ss68_m_srst),
	.halt_n(~(pause & ~ss68_m_exec)),
	.clk_num(7'd1),
	.clk_den(main_clk_den),
	.ipl_n(ss68_m_i7 ? 3'b000 : (ss68_m_hide ? 3'b111 : main_ipl_n)),
	.bus_din(ss68_m_ovr ? (ss68_m_ssp ? ss68_sec_word : ss68_word) : main_bus_rdata),
	.bus_cs(main_bus_cs),
	.bus_busy(main_bus_busy),
	.dev_br(1'b0),
	.bus_addr(main_bus_addr),
	.bus_asn(main_bus_asn),
	.bus_rnw(main_bus_rnw),
	.bus_dsn(main_bus_dsn),
	.bus_dout(main_bus_dout),
	.dbg_pc(),
	.dbg_fc(main_fc),
	.dbg_dtackn(),
	.dbg_fave(),
	.dbg_fworst(),
	.iack(main_iack),
	.bus_rw_raw(),
	.ss_cen_raw(),
	.ss_cenb_raw(),
	.ss_cen_g(1'b0),
	.ss_cenb_g(1'b0),
	.ss_gate_q(1'b0),
	.ss_gate_raw(1'b0),
	.ss_ovr(1'b0),
	.ss_word(16'd0),
	.ss_ovr_c(1'b0),
	.ss_word_c(16'd0)
);

darius_cpu_node #(
	.CPU_ID(1'b1),
	.CORE_IMPL(SUB_CORE_IMPL)
) u_sub_cpu (
	.clk(clk),
	.reset(reset),
	.soft_reset((HOLD_SUB_IN_RESET ? 1'b1 : ~cpua_ctrl_reg[0]) | ss68_s_srst),
	.halt_n(~(pause & ~ss68_s_exec)),
	.clk_num(7'd1),
	.clk_den(sub_clk_den),
	.ipl_n(ss68_s_i7 ? 3'b000 : (ss68_s_hide ? 3'b111 : sub_ipl_n)),
	.bus_din(ss68_s_ovr ? (ss68_s_ssp ? ss68_sec_word : ss68_word) : sub_bus_rdata),
	.bus_cs(sub_bus_cs),
	.bus_busy(sub_bus_busy),
	.dev_br(1'b0),
	.bus_addr(sub_bus_addr),
	.bus_asn(sub_bus_asn),
	.bus_rnw(sub_bus_rnw),
	.bus_dsn(sub_bus_dsn),
	.bus_dout(sub_bus_dout),
	.dbg_pc(),
	.dbg_fc(sub_fc),
	.dbg_dtackn(),
	.dbg_fave(),
	.dbg_fworst(),
	.iack(sub_iack),
	.bus_rw_raw(),
	.ss_cen_raw(),
	.ss_cenb_raw(),
	.ss_cen_g(1'b0),
	.ss_cenb_g(1'b0),
	.ss_gate_q(1'b0),
	.ss_gate_raw(1'b0),
	.ss_ovr(1'b0),
	.ss_word(16'd0),
	.ss_ovr_c(1'b0),
	.ss_word_c(16'd0)
);

darius_maincpu_map #(
	.ENABLE_NOP_C00050(ENABLE_C00050_NOP),
	.ENABLE_WATCHDOG(ENABLE_WATCHDOG),
	.ENABLE_PC080_CTRL(ENABLE_PC080_CTRL),
	.ENABLE_DC0000(ENABLE_DC0000),
	.ENABLE_C00060(ENABLE_C00060),
	.ENABLE_C00020(ENABLE_C00020),
	.ENABLE_C00022(ENABLE_C00022),
	.ENABLE_C00024(ENABLE_C00024),
	.ENABLE_C00030(ENABLE_C00030),
	.ENABLE_C00032(ENABLE_C00032),
	.ENABLE_C00034(ENABLE_C00034),
	.ENABLE_D40000(ENABLE_D40000),
	.ENABLE_D40002(ENABLE_D40002),
	.ENABLE_D20000(ENABLE_D20000),
	.ENABLE_D20002(ENABLE_D20002),
	.ENABLE_C0000C(ENABLE_C0000C),
	.ENABLE_C00010(ENABLE_C00010),
	.ENABLE_PC060HA_PORT(ENABLE_MAIN_PC060HA_PORT),
	.ENABLE_PC060HA_COMM(ENABLE_MAIN_PC060HA_COMM),
	.ENABLE_D00000(ENABLE_MAIN_D00000),
	.ENABLE_PALETTE(ENABLE_MAIN_PALETTE),
	.ENABLE_FG(ENABLE_FG_RAM),
	.ENABLE_CTRL(ENABLE_MAIN_CTRL),
	.ENABLE_SHARED(ENABLE_MAIN_SHARED),
	.ENABLE_SPRITE(ENABLE_MAIN_SPRITE),
	.ENABLE_IO(ENABLE_MAIN_IO),
	.ENABLE_VIDEO(ENABLE_MAIN_VIDEO),
	.ENABLE_PLAYER_IO(ENABLE_MAIN_PLAYER_IO)
) u_main_map
(
	.clk(clk),
	.reset(reset),
	.p1_input(p1_input),
	.p2_input(p2_input),
	.system_input(system_input),
	.dsw_input(dsw_input),
	.bus_addr(main_bus_addr),
	.bus_asn(main_bus_asn),
	.bus_rnw(main_bus_rnw),
	.bus_dsn(main_bus_dsn),
	.bus_wdata(main_bus_dout),
	.bus_rdata(main_bus_rdata),
	.bus_cs(main_bus_cs),
	.bus_busy(main_bus_busy),
	.rom_rdata(main_rom_rdata),
	.rom_ready(main_rom_ready),
	.cpua_ctrl_q(cpua_ctrl_reg),
	.shared_rdata(shared_main_rdata),
	.shared_ready(shared_main_ready),
	.shared_rd(main_shared_rd),
	.shared_wr(main_shared_wr),
	.shared_addr(main_shared_addr),
	.shared_wdata(main_shared_wdata),
	.sprite_rdata(sprite_main_rdata),
	.sprite_ready(sprite_main_ready),
	.sprite_rd(main_sprite_rd),
	.sprite_wr(main_sprite_wr),
	.sprite_addr(main_sprite_addr),
	.sprite_wdata(main_sprite_wdata),
	.fg_rdata(fg_main_rdata),
	.fg_ready(fg_main_ready),
	.fg_rd(main_fg_rd),
	.fg_wr(main_fg_wr),
	.fg_addr(main_fg_addr),
	.fg_wdata(main_fg_wdata),
	.ram_rdata(main_ram_rdata),
	.ram_rd(main_ram_rd),
	.ram_wr(main_ram_wr),
	.ram_be(main_ram_be),
	.bus_byte_en(main_bus_be),
	.ram_addr(main_ram_addr),
	.ram_wdata(main_ram_wdata),
	.e100_rdata(main_e100_rdata),
	.e100_rd(main_e100_rd),
	.e100_wr(main_e100_wr),
	.e100_addr(main_e100_addr),
	.e100_wdata(main_e100_wdata),
	.d000_rdata(d000_main_rdata),
	.d000_rd(main_d000_rd),
	.d000_wr(main_d000_wr),
	.d000_addr(main_d000_addr),
	.d000_wdata(main_d000_wdata),
	.palette_rdata(palette_main_rdata),
	.palette_ready(palette_main_ready),
	.palette_rd(main_palette_rd),
	.palette_wr(main_palette_wr),
	.palette_addr(main_palette_addr),
	.palette_wdata(main_palette_wdata),
	.cpua_ctrl_wr(cpua_ctrl_wr),
	.cpua_ctrl_data(cpua_ctrl_data),
	.pc060ha_port_wr(main_pc060ha_port_wr),
	.pc060ha_port_data(main_pc060ha_port_data),
	.pc060ha_comm_wr(main_pc060ha_comm_wr),
	.pc060ha_comm_data(main_pc060ha_comm_data),
	.pc060ha_comm_rdata(pc060ha_main_rdata),
	.rom_addr(main_rom_addr),
	.rom_req(main_rom_req),
	.cs_vector()
);

darius_subcpu_map #(
	.ENABLE_NOP_C00050(ENABLE_C00050_NOP),
	.ENABLE_SHARED(ENABLE_SUB_SHARED),
	.ENABLE_SPRITE(ENABLE_SUB_SPRITE),
	.ENABLE_FG(ENABLE_FG_RAM),
	.ENABLE_PALETTE(ENABLE_SUB_PALETTE),
	.ENABLE_IO(ENABLE_SUB_IO)
) u_sub_map
(
	.clk(clk),
	.reset(reset),
	.bus_addr(sub_bus_addr),
	.bus_asn(sub_bus_asn),
	.bus_rnw(sub_bus_rnw),
	.bus_dsn(sub_bus_dsn),
	.bus_wdata(sub_bus_dout),
	.bus_rdata(sub_bus_rdata),
	.bus_cs(sub_bus_cs),
	.bus_busy(sub_bus_busy),
	.rom_rdata(sub_rom_rdata),
	.rom_ready(sub_rom_ready),
	.shared_rdata(shared_sub_rdata),
	.shared_ready(shared_sub_ready),
	.shared_rd(sub_shared_rd),
	.shared_wr(sub_shared_wr),
	.shared_addr(sub_shared_addr),
	.shared_wdata(sub_shared_wdata),
	.sprite_rdata(sprite_sub_rdata),
	.sprite_ready(sprite_sub_ready),
	.sprite_rd(sub_sprite_rd),
	.sprite_wr(sub_sprite_wr),
	.sprite_addr(sub_sprite_addr),
	.sprite_wdata(sub_sprite_wdata),
	.fg_rdata(fg_sub_rdata),
	.fg_ready(fg_sub_ready),
	.fg_rd(sub_fg_rd),
	.fg_wr(sub_fg_wr),
	.fg_addr(sub_fg_addr),
	.fg_wdata(sub_fg_wdata),
	.ram_rdata(sub_ram_rdata),
	.ram_rd(sub_ram_rd),
	.ram_wr(sub_ram_wr),
	.ram_addr(sub_ram_addr),
	.ram_wdata(sub_ram_wdata),
	.palette_ready(palette_sub_ready),
	.palette_wr(sub_palette_wr),
	.palette_addr(sub_palette_addr),
	.palette_wdata(sub_palette_wdata),
	.rom_addr(sub_rom_addr),
	.rom_req(sub_rom_req),
	.cs_vector()
);

// =====================================================================
// Savestate (pattern BoogieWings/F2, portato 1:1)
// SS_IDX_* = indice univoco di ogni blocco di stato (come BW boogwings_top).
// Adaptor interposti sulla porta SUB delle RAM dual-port (CPU ferme durante
// gather/scatter) e sull'unica porta delle RAM locali.
// =====================================================================
localparam SS_IDX_GLOBAL   = 0;   // sezione del savestate dei 68000 (m68k_ss_seq: 4 parole)
localparam SS_IDX_MAIN_RAM = 1;
localparam SS_IDX_SUB_RAM  = 2;
localparam SS_IDX_SHARED   = 3;
localparam SS_IDX_SPRITE   = 4;
localparam SS_IDX_PALETTE  = 5;
localparam SS_IDX_FG       = 6;
localparam SS_IDX_FG_MIR   = 7;
localparam SS_IDX_E100     = 8;
localparam SS_IDX_VRAM     = 9;
localparam SS_IDX_CTRL     = 10;  // cpua_ctrl_reg + scroll regs (slave inline)
localparam SS_IDX_FGPAL    = 11;  // copia snooped palette FG
localparam SS_IDX_SPRPAL   = 12;  // copia snooped palette sprite
localparam SS_IDX_PAL_L    = 13;  // copie pal interne ai 3 panel renderer
localparam SS_IDX_PAL_C    = 14;
localparam SS_IDX_PAL_R    = 15;
localparam SS_IDX_SPR_LOC  = 16;  // OBJ RAM locale del sprite renderer
localparam SS_IDX_ZRAM     = 17;  // audio Fase A: RAM Z80A 4KB (hook esterno)
localparam SS_IDX_AMISC    = 18;  // audio Fase A: bank/cmd/pan/msm (hook esterno)
localparam SS_IDX_YMSH1    = 19;  // audio Fase B: shadow registri YM1
localparam SS_IDX_YMSH2    = 20;  // audio Fase B: shadow registri YM2
localparam SS_IDX_Z80A     = 21;  // audio Fase C: stato rmZ80 Z80A (274 bit nei bassi di 358)
localparam SS_IDX_Z80B     = 22;  // audio Fase C: stato rmZ80 Z80B (274 bit nei bassi di 358)
localparam SS_IDX_PC060    = 23;  // audio: handshake PC060HA (46 bit)
localparam SS_NSLAVES      = 24;
localparam SS_MS_COUNT     = 32;  // potenza di 2 >= NSLAVES (regola BW)

ssbus_if ssbus();
ssbus_if ssb[SS_NSLAVES]();

// --- u_shared_ram: adaptor sulla porta SUB ---
wire        sshr_we_lo, sshr_we_hi;
wire [11:0] sshr_addr;
wire [15:0] sshr_wdata;
ss_ram16_adaptor #(.WIDTHAD(12), .SS_IDX(SS_IDX_SHARED)) u_ss_shared (
	.clk(clk),
	.we_lo_in(sub_shared_wr & sub_bus_be[0]),
	.we_hi_in(sub_shared_wr & sub_bus_be[1]),
	.addr_in(sub_shared_addr),
	.wdata_in(sub_shared_wdata),
	.we_lo_out(sshr_we_lo), .we_hi_out(sshr_we_hi),
	.addr_out(sshr_addr), .wdata_out(sshr_wdata),
	.q_in(shared_sub_rdata),
	.ssbus(ssb[SS_IDX_SHARED])
);

darius_shared_ram #(
	.ADDR_WIDTH(12)
) u_shared_ram
(
	.clk(clk),
	.main_rd(main_shared_rd),
	.main_wr(main_shared_wr),
	.main_be(main_bus_be),
	.main_addr(main_shared_addr),
	.main_wdata(main_shared_wdata),
	.main_rdata(shared_main_rdata),
	.main_ready(shared_main_ready),
	.sub_rd(sub_shared_rd),
	.sub_wr(sshr_we_lo | sshr_we_hi),
	.sub_be({sshr_we_hi, sshr_we_lo}),
	.sub_addr(sshr_addr),
	.sub_wdata(sshr_wdata),
	.sub_rdata(shared_sub_rdata),
	.sub_ready(shared_sub_ready)
);

// --- u_sprite_ram: adaptor sulla porta SUB ---
wire        sspr_we_lo, sspr_we_hi;
wire [10:0] sspr_addr;
wire [15:0] sspr_wdata;
ss_ram16_adaptor #(.WIDTHAD(11), .SS_IDX(SS_IDX_SPRITE)) u_ss_sprite (
	.clk(clk),
	.we_lo_in(sub_sprite_wr & sub_bus_be[0]),
	.we_hi_in(sub_sprite_wr & sub_bus_be[1]),
	.addr_in(sub_sprite_addr),
	.wdata_in(sub_sprite_wdata),
	.we_lo_out(sspr_we_lo), .we_hi_out(sspr_we_hi),
	.addr_out(sspr_addr), .wdata_out(sspr_wdata),
	.q_in(sprite_sub_rdata),
	.ssbus(ssb[SS_IDX_SPRITE])
);

darius_shared_ram #(
	.ADDR_WIDTH(11)
) u_sprite_ram
(
	.clk(clk),
	.main_rd(main_sprite_rd),
	.main_wr(main_sprite_wr),
	.main_be(main_bus_be),
	.main_addr(main_sprite_addr),
	.main_wdata(main_sprite_wdata),
	.main_rdata(sprite_main_rdata),
	.main_ready(sprite_main_ready),
	.sub_rd(sub_sprite_rd),
	.sub_wr(sspr_we_lo | sspr_we_hi),
	.sub_be({sspr_we_hi, sspr_we_lo}),
	.sub_addr(sspr_addr),
	.sub_wdata(sspr_wdata),
	.sub_rdata(sprite_sub_rdata),
	.sub_ready(sprite_sub_ready)
);

// FG RAM — dual BRAM (primary + mirror) to eliminate cross-port
// read/write collision on no_rw_check M10K.
// Primary: main Port A (R/W) + sub Port B (R/W, no renderer).
// Mirror:  main Port A (write only, read ignored) +
//          sub Port B write + renderer Port B read (tiny mux, sub_wr has priority).
// Both RAMs receive identical writes from main and sub. Renderer reads
// exclusively from mirror Port B: zero collisions with sub reads.
wire [13:0] fg_render_addr;
wire [15:0] fg_render_rdata;
wire        fg_render_stall;

// Mirror Port B mux: sub_wr (priority, rare) vs renderer read (default)
wire mirror_sub_active = sub_fg_wr;  // sub READS go to primary only
wire        mirror_portb_rd    = mirror_sub_active ? 1'b0          : 1'b1;
wire        mirror_portb_wr    = mirror_sub_active ? sub_fg_wr     : 1'b0;
wire [1:0]  mirror_portb_be    = mirror_sub_active ? sub_bus_be    : 2'b11;
wire [13:0] mirror_portb_addr  = mirror_sub_active ? sub_fg_addr   : fg_render_addr;
wire [15:0] mirror_portb_wdata = sub_fg_wdata;
wire [15:0] mirror_portb_rdata;
wire        mirror_portb_ready;

// Stall renderer when sub writes on mirror (same 2-cycle recovery as old mux)
reg mirror_sub_active_d, mirror_sub_active_d2;
always @(posedge clk) begin
	if (reset) begin mirror_sub_active_d <= 1'b0; mirror_sub_active_d2 <= 1'b0; end
	else begin mirror_sub_active_d <= mirror_sub_active; mirror_sub_active_d2 <= mirror_sub_active_d; end
end
assign fg_render_stall = mirror_sub_active | mirror_sub_active_d | mirror_sub_active_d2;
assign fg_render_rdata = mirror_portb_rdata;

// --- u_fg_ram: adaptor sulla porta SUB ---
wire        sfg_we_lo, sfg_we_hi;
wire [13:0] sfg_addr;
wire [15:0] sfg_wdata;
ss_ram16_adaptor #(.WIDTHAD(14), .SS_IDX(SS_IDX_FG)) u_ss_fg (
	.clk(clk),
	.we_lo_in(sub_fg_wr & sub_bus_be[0]),
	.we_hi_in(sub_fg_wr & sub_bus_be[1]),
	.addr_in(sub_fg_addr),
	.wdata_in(sub_fg_wdata),
	.we_lo_out(sfg_we_lo), .we_hi_out(sfg_we_hi),
	.addr_out(sfg_addr), .wdata_out(sfg_wdata),
	.q_in(fg_sub_rdata),
	.ssbus(ssb[SS_IDX_FG])
);

// Primary FG RAM — CPU-visible (main_rdata, sub_rdata come from here)
darius_shared_ram #(
	.ADDR_WIDTH(14)
) u_fg_ram
(
	.clk(clk),
	.main_rd(main_fg_rd),
	.main_wr(main_fg_wr),
	.main_be(main_bus_be),
	.main_addr(main_fg_addr),
	.main_wdata(main_fg_wdata),
	.main_rdata(fg_main_rdata),
	.main_ready(fg_main_ready),
	.sub_rd(sub_fg_rd),
	.sub_wr(sfg_we_lo | sfg_we_hi),
	.sub_be({sfg_we_hi, sfg_we_lo}),
	.sub_addr(sfg_addr),
	.sub_wdata(sfg_wdata),
	.sub_rdata(fg_sub_rdata),
	.sub_ready(fg_sub_ready)
);

// --- u_fg_ram_mirror: adaptor sulla porta B (mux renderer/sub) — come i
//     mirror di BW (SS_IDX dedicato, si salva/ripristina anche la copia) ---
wire        sfgm_we_lo, sfgm_we_hi;
wire [13:0] sfgm_addr;
wire [15:0] sfgm_wdata;
ss_ram16_adaptor #(.WIDTHAD(14), .SS_IDX(SS_IDX_FG_MIR)) u_ss_fg_mir (
	.clk(clk),
	.we_lo_in(mirror_portb_wr & mirror_portb_be[0]),
	.we_hi_in(mirror_portb_wr & mirror_portb_be[1]),
	.addr_in(mirror_portb_addr),
	.wdata_in(mirror_portb_wdata),
	.we_lo_out(sfgm_we_lo), .we_hi_out(sfgm_we_hi),
	.addr_out(sfgm_addr), .wdata_out(sfgm_wdata),
	.q_in(mirror_portb_rdata),
	.ssbus(ssb[SS_IDX_FG_MIR])
);

// Mirror FG RAM — renderer reads exclusively from here
darius_shared_ram #(
	.ADDR_WIDTH(14)
) u_fg_ram_mirror
(
	.clk(clk),
	.main_rd(1'b0),
	.main_wr(main_fg_wr),
	.main_be(main_bus_be),
	.main_addr(main_fg_addr),
	.main_wdata(main_fg_wdata),
	.main_rdata(/* unused */),
	.main_ready(/* unused */),
	.sub_rd(mirror_portb_rd),
	.sub_wr(sfgm_we_lo | sfgm_we_hi),
	.sub_be({sfgm_we_hi, sfgm_we_lo}),
	.sub_addr(sfgm_addr),
	.sub_wdata(sfgm_wdata),
	.sub_rdata(mirror_portb_rdata),
	.sub_ready(mirror_portb_ready)
);

// --- u_main_ram: adaptor sull'unica porta (CPU ferma durante SS) ---
wire        smr_we_lo, smr_we_hi;
wire [14:0] smr_addr;
wire [15:0] smr_wdata;
ss_ram16_adaptor #(.WIDTHAD(15), .SS_IDX(SS_IDX_MAIN_RAM)) u_ss_main_ram (
	.clk(clk),
	.we_lo_in(main_ram_wr & main_ram_be[0]),
	.we_hi_in(main_ram_wr & main_ram_be[1]),
	.addr_in(main_ram_addr),
	.wdata_in(main_ram_wdata),
	.we_lo_out(smr_we_lo), .we_hi_out(smr_we_hi),
	.addr_out(smr_addr), .wdata_out(smr_wdata),
	.q_in(main_ram_rdata),
	.ssbus(ssb[SS_IDX_MAIN_RAM])
);

darius_local_ram #(
	.ADDR_WIDTH(15)
) u_main_ram (
	.clk(clk),
	.rd(main_ram_rd),
	.wr(smr_we_lo | smr_we_hi),
	.be({smr_we_hi, smr_we_lo}),
	.addr(smr_addr),
	.wdata(smr_wdata),
	.rdata(main_ram_rdata)
);

// --- u_main_e100_ram: adaptor sull'unica porta ---
wire        se1_we_lo, se1_we_hi;
wire [10:0] se1_addr;
wire [15:0] se1_wdata;
ss_ram16_adaptor #(.WIDTHAD(11), .SS_IDX(SS_IDX_E100)) u_ss_e100 (
	.clk(clk),
	.we_lo_in(main_e100_wr & main_bus_be[0]),
	.we_hi_in(main_e100_wr & main_bus_be[1]),
	.addr_in(main_e100_addr),
	.wdata_in(main_e100_wdata),
	.we_lo_out(se1_we_lo), .we_hi_out(se1_we_hi),
	.addr_out(se1_addr), .wdata_out(se1_wdata),
	.q_in(main_e100_rdata),
	.ssbus(ssb[SS_IDX_E100])
);

darius_local_ram #(
	.ADDR_WIDTH(11)
) u_main_e100_ram (
	.clk(clk),
	.rd(main_e100_rd),
	.wr(se1_we_lo | se1_we_hi),
	.be({se1_we_hi, se1_we_lo}),
	.addr(se1_addr),
	.wdata(se1_wdata),
	.rdata(main_e100_rdata)
);

// --- u_palette_ram: adaptor sulla porta SUB (sub_rd libero) ---
wire        spal_we_lo, spal_we_hi;
wire [10:0] spal_addr;
wire [15:0] spal_wdata;
ss_ram16_adaptor #(.WIDTHAD(11), .SS_IDX(SS_IDX_PALETTE)) u_ss_palette (
	.clk(clk),
	.we_lo_in(sub_palette_wr & sub_bus_be[0]),
	.we_hi_in(sub_palette_wr & sub_bus_be[1]),
	.addr_in(sub_palette_addr),
	.wdata_in(sub_palette_wdata),
	.we_lo_out(spal_we_lo), .we_hi_out(spal_we_hi),
	.addr_out(spal_addr), .wdata_out(spal_wdata),
	.q_in(palette_sub_rdata),
	.ssbus(ssb[SS_IDX_PALETTE])
);

darius_shared_ram #(
	.ADDR_WIDTH(11)
) u_palette_ram (
	.clk(clk),
	.main_rd(main_palette_rd),
	.main_wr(main_palette_wr),
	.main_be(main_bus_be),
	.main_addr(main_palette_addr),
	.main_wdata(main_palette_wdata),
	.main_rdata(palette_main_rdata),
	.main_ready(palette_main_ready),
	.sub_rd(1'b0),
	.sub_wr(spal_we_lo | spal_we_hi),
	.sub_be({spal_we_hi, spal_we_lo}),
	.sub_addr(spal_addr),
	.sub_wdata(spal_wdata),
	.sub_rdata(palette_sub_rdata),
	.sub_ready(palette_sub_ready)
);

// --- u_sub_ram: adaptor sull'unica porta ---
wire        ssr_we_lo, ssr_we_hi;
wire [14:0] ssr_addr;
wire [15:0] ssr_wdata;
ss_ram16_adaptor #(.WIDTHAD(15), .SS_IDX(SS_IDX_SUB_RAM)) u_ss_sub_ram (
	.clk(clk),
	.we_lo_in(sub_ram_wr & sub_bus_be[0]),
	.we_hi_in(sub_ram_wr & sub_bus_be[1]),
	.addr_in(sub_ram_addr),
	.wdata_in(sub_ram_wdata),
	.we_lo_out(ssr_we_lo), .we_hi_out(ssr_we_hi),
	.addr_out(ssr_addr), .wdata_out(ssr_wdata),
	.q_in(sub_ram_rdata),
	.ssbus(ssb[SS_IDX_SUB_RAM])
);

darius_local_ram #(
	.ADDR_WIDTH(15)
) u_sub_ram (
	.clk(clk),
	.rd(sub_ram_rd),
	.wr(ssr_we_lo | ssr_we_hi),
	.be({ssr_we_hi, ssr_we_lo}),
	.addr(ssr_addr),
	.wdata(ssr_wdata),
	.rdata(sub_ram_rdata)
);

// =====================================================================
// 3 parallel panel renderers (tile ROM: one sdrc_darius port each)
// =====================================================================

// =====================================================================
// Shared VRAM for 3 panel renderers (replaces 3 internal copies)
// =====================================================================
// Unified VRAM: True Dual-Port M10K
//   Port A: CPU read + write (from maincpu_map d000 interface, with byte enable)
//   Port B: renderer read (from VRAM arbiter, read-only)
// Replaces both d000_ram (64 M10K) and shared_vram (52 M10K) → saves 64 M10K.
// =====================================================================
(* ramstyle = "M10K,no_rw_check" *) reg [7:0] unified_vram_hi [0:32767];
(* ramstyle = "M10K,no_rw_check" *) reg [7:0] unified_vram_lo [0:32767];

// Port A: CPU (read + write with byte enable) — adaptor savestate interposto
wire        svr_we_lo, svr_we_hi;
wire [14:0] svr_addr;
wire [15:0] svr_wdata;
reg [15:0] vram_cpu_rdata;
ss_ram16_adaptor #(.WIDTHAD(15), .SS_IDX(SS_IDX_VRAM)) u_ss_vram (
	.clk(clk),
	.we_lo_in(main_d000_wr & main_bus_be[0]),
	.we_hi_in(main_d000_wr & main_bus_be[1]),
	.addr_in(main_d000_addr),
	.wdata_in(main_d000_wdata),
	.we_lo_out(svr_we_lo), .we_hi_out(svr_we_hi),
	.addr_out(svr_addr), .wdata_out(svr_wdata),
	.q_in(vram_cpu_rdata),
	.ssbus(ssb[SS_IDX_VRAM])
);
always @(posedge clk) begin
	if (svr_we_hi) unified_vram_hi[svr_addr] <= svr_wdata[15:8];
	if (svr_we_lo) unified_vram_lo[svr_addr] <= svr_wdata[7:0];
	vram_cpu_rdata <= {unified_vram_hi[svr_addr], unified_vram_lo[svr_addr]};
end
assign d000_main_rdata = vram_cpu_rdata;

// Port B: renderer (read-only, via VRAM arbiter)
reg [15:0] shared_vram_rdata;
wire [14:0] shared_vram_rd_addr;
always @(posedge clk) begin
	shared_vram_rdata <= {unified_vram_hi[shared_vram_rd_addr], unified_vram_lo[shared_vram_rd_addr]};
end

// Per-panel VRAM read ports
wire [14:0] r0_vram_addr, r1_vram_addr, r2_vram_addr;
wire        r0_vram_req,  r1_vram_req,  r2_vram_req;
wire [15:0] r0_vram_data, r1_vram_data, r2_vram_data;
wire        r0_vram_valid, r1_vram_valid, r2_vram_valid;

darius_vram_arbiter u_vram_arb (
	.clk(clk), .reset(reset),
	.p0_addr(r0_vram_addr), .p0_req(r0_vram_req), .p0_data(r0_vram_data), .p0_valid(r0_vram_valid),
	.p1_addr(r1_vram_addr), .p1_req(r1_vram_req), .p1_data(r1_vram_data), .p1_valid(r1_vram_valid),
	.p2_addr(r2_vram_addr), .p2_req(r2_vram_req), .p2_data(r2_vram_data), .p2_valid(r2_vram_valid),
	.vram_addr(shared_vram_rd_addr), .vram_data(shared_vram_rdata)
);

// Per-renderer tile ROM interface
wire [23:0] r0_tilerom_addr, r1_tilerom_addr, r2_tilerom_addr;
wire        r0_tilerom_req,  r1_tilerom_req,  r2_tilerom_req;
wire [31:0] r0_tilerom_data, r1_tilerom_data, r2_tilerom_data;
wire        r0_tilerom_valid, r1_tilerom_valid, r2_tilerom_valid;

// Per-renderer pixel output
wire [23:0] r0_rgb, r1_rgb, r2_rgb;
wire [1:0]  r0_prio, r1_prio, r2_prio;
wire        r0_opaque, r1_opaque, r2_opaque;

// Debug from LEFT renderer only

// Savestate: load registri scroll/ctrl (da adaptor CTRL, broadcast ai 3 pannelli)
wire        ss_regs_ld;
wire [15:0] ss_xs0, ss_xs1, ss_ys0, ss_ys1, ss_c0, ss_c1;

// LEFT panel (pixels 0-287)
darius_panel_renderer #(.X_OFFSET(10'd0), .H_PIXELS(10'd288), .SS_IDX(SS_IDX_PAL_L)) u_render_left (
	.ssbus(ssb[SS_IDX_PAL_L]),
	.ss_regs_ld(ss_regs_ld),
	.ss_xs0(ss_xs0), .ss_xs1(ss_xs1), .ss_ys0(ss_ys0), .ss_ys1(ss_ys1), .ss_c0(ss_c0), .ss_c1(ss_c1),
	.clk(clk), .reset(reset),
	.render_x(render_x), .render_y(render_y), .render_y_next(render_y_next), .render_y_first(render_y_first),
	.cpu_bus_addr(main_bus_addr), .cpu_bus_asn(main_bus_asn),
	.cpu_bus_rnw(main_bus_rnw), .cpu_bus_dsn(main_bus_dsn),
	.cpu_bus_wdata(main_bus_dout), .cpu_bus_cs(main_bus_cs),
	.sub_pal_wr(sub_palette_wr), .sub_pal_addr(sub_palette_addr),
	.sub_pal_wdata(sub_palette_wdata), .sub_pal_be(sub_bus_be),
	.vram_rd_addr(r0_vram_addr), .vram_rd_req(r0_vram_req), .vram_rd_data(r0_vram_data), .vram_rd_valid(r0_vram_valid),
	.tilerom_data(r0_tilerom_data), .tilerom_valid(r0_tilerom_valid),
	.tilerom_addr(r0_tilerom_addr), .tilerom_req(r0_tilerom_req),
	.xscroll_l0(xscroll_l0), .xscroll_l1(xscroll_l1),
	.yscroll_l0(yscroll_l0), .yscroll_l1(yscroll_l1),
	.ctrl_l0(ctrl_l0), .ctrl_l1(ctrl_l1),
	.l0_xoff(l0_xoff), .l0_yoff(l0_yoff), .l1_xoff(l1_xoff), .l1_yoff(l1_yoff),
	.tile_rgb(r0_rgb), .tile_prio(r0_prio), .tile_opaque(r0_opaque),
	.dbg_tile_code(), .dbg_tile_attr(),
	.dbg_tile_romdata()
);

// CENTER panel (pixels 288-575)
darius_panel_renderer #(.X_OFFSET(10'd288), .H_PIXELS(10'd288), .SS_IDX(SS_IDX_PAL_C)) u_render_center (
	.ssbus(ssb[SS_IDX_PAL_C]),
	.ss_regs_ld(ss_regs_ld),
	.ss_xs0(ss_xs0), .ss_xs1(ss_xs1), .ss_ys0(ss_ys0), .ss_ys1(ss_ys1), .ss_c0(ss_c0), .ss_c1(ss_c1),
	.clk(clk), .reset(reset),
	.render_x(render_x), .render_y(render_y), .render_y_next(render_y_next), .render_y_first(render_y_first),
	.cpu_bus_addr(main_bus_addr), .cpu_bus_asn(main_bus_asn),
	.cpu_bus_rnw(main_bus_rnw), .cpu_bus_dsn(main_bus_dsn),
	.cpu_bus_wdata(main_bus_dout), .cpu_bus_cs(main_bus_cs),
	.sub_pal_wr(sub_palette_wr), .sub_pal_addr(sub_palette_addr),
	.sub_pal_wdata(sub_palette_wdata), .sub_pal_be(sub_bus_be),
	.vram_rd_addr(r1_vram_addr), .vram_rd_req(r1_vram_req), .vram_rd_data(r1_vram_data), .vram_rd_valid(r1_vram_valid),
	.tilerom_data(r1_tilerom_data), .tilerom_valid(r1_tilerom_valid),
	.tilerom_addr(r1_tilerom_addr), .tilerom_req(r1_tilerom_req),
	.xscroll_l0(), .xscroll_l1(),
	.yscroll_l0(), .yscroll_l1(),
	.ctrl_l0(), .ctrl_l1(),
	.l0_xoff(l0_xoff), .l0_yoff(l0_yoff), .l1_xoff(l1_xoff), .l1_yoff(l1_yoff),
	.tile_rgb(r1_rgb), .tile_prio(r1_prio), .tile_opaque(r1_opaque),
	.dbg_tile_code(), .dbg_tile_attr(), .dbg_tile_romdata()
);

// RIGHT panel (pixels 576-863)
darius_panel_renderer #(.X_OFFSET(10'd576), .H_PIXELS(10'd288), .SS_IDX(SS_IDX_PAL_R)) u_render_right (
	.ssbus(ssb[SS_IDX_PAL_R]),
	.ss_regs_ld(ss_regs_ld),
	.ss_xs0(ss_xs0), .ss_xs1(ss_xs1), .ss_ys0(ss_ys0), .ss_ys1(ss_ys1), .ss_c0(ss_c0), .ss_c1(ss_c1),
	.clk(clk), .reset(reset),
	.render_x(render_x), .render_y(render_y), .render_y_next(render_y_next), .render_y_first(render_y_first),
	.cpu_bus_addr(main_bus_addr), .cpu_bus_asn(main_bus_asn),
	.cpu_bus_rnw(main_bus_rnw), .cpu_bus_dsn(main_bus_dsn),
	.cpu_bus_wdata(main_bus_dout), .cpu_bus_cs(main_bus_cs),
	.sub_pal_wr(sub_palette_wr), .sub_pal_addr(sub_palette_addr),
	.sub_pal_wdata(sub_palette_wdata), .sub_pal_be(sub_bus_be),
	.vram_rd_addr(r2_vram_addr), .vram_rd_req(r2_vram_req), .vram_rd_data(r2_vram_data), .vram_rd_valid(r2_vram_valid),
	.tilerom_data(r2_tilerom_data), .tilerom_valid(r2_tilerom_valid),
	.tilerom_addr(r2_tilerom_addr), .tilerom_req(r2_tilerom_req),
	.xscroll_l0(), .xscroll_l1(),
	.yscroll_l0(), .yscroll_l1(),
	.ctrl_l0(), .ctrl_l1(),
	.l0_xoff(l0_xoff), .l0_yoff(l0_yoff), .l1_xoff(l1_xoff), .l1_yoff(l1_yoff),
	.tile_rgb(r2_rgb), .tile_prio(r2_prio), .tile_opaque(r2_opaque),
	.dbg_tile_code(), .dbg_tile_attr(), .dbg_tile_romdata()
);

// Sprite renderer ROM interface (lato RENDERER: renderer <-> cache)
wire [23:0] sprite_romaddr;
wire        sprite_romreq;
wire [31:0] sprite_romdata;
wire        sprite_romvalid;
// Sprite ROM interface (lato BACKEND: cache <-> porta grafica 3 di sdrc_darius)
// La sprite_rom_cache si interpone: gli sprite che riusano lo stesso tile/row
// (oggetti grandi, ripetizioni, animazioni) fanno HIT in 1 ck senza toccare la
// SDRAM -> niente contesa/annegamento coi tile in frame densi.
wire [23:0] spr_be_addr;
wire        spr_be_req;
wire [31:0] spr_be_data;
wire        spr_be_valid;

// FG text renderer (text ROM in local BRAM, no SDRAM)
wire [10:0] fg_pal_addr;
reg  [15:0] fg_pal_data;

// FG palette: snooped copy (same bus write detection as panel renderer)
wire fg_pal_bus_active = ~main_bus_asn && ~main_bus_rnw && main_bus_cs && (main_bus_dsn != 2'b11);
reg  fg_pal_write_seen;
always @(posedge clk) begin
	if (reset) fg_pal_write_seen <= 1'b0;
	else if (!fg_pal_bus_active) fg_pal_write_seen <= 1'b0;
	else fg_pal_write_seen <= 1'b1;
end
wire fg_pal_wr_pulse = fg_pal_bus_active && !fg_pal_write_seen;
wire fg_pal_sel = (main_bus_addr >= 24'hD80000) && (main_bus_addr <= 24'hD80FFF);
wire fg_pal_wr = fg_pal_wr_pulse && fg_pal_sel;

// Split into HI/LO byte RAMs so byte enables are respected on byte writes.
// Previous single-word write corrupted the non-selected byte on move.b to palette,
// producing grey blocks in Japan set (uses move.b on palette).
(* ramstyle = "M10K,no_rw_check" *) reg [7:0] fg_pal_ram_hi [0:2047];
(* ramstyle = "M10K,no_rw_check" *) reg [7:0] fg_pal_ram_lo [0:2047];

// Adaptor savestate sulla gamba SUB (durante SS il main è fermo, la gamba è
// libera). Lettura di gather sul write-leg (stessa porta fisica delle write).
wire        sfp_we_lo, sfp_we_hi;
wire [10:0] sfp_addr;
wire [15:0] sfp_wdata;
reg  [15:0] fg_pal_ss_q;
ss_ram16_adaptor #(.WIDTHAD(11), .SS_IDX(SS_IDX_FGPAL)) u_ss_fgpal (
	.clk(clk),
	.we_lo_in(sub_palette_wr & sub_bus_be[0]),
	.we_hi_in(sub_palette_wr & sub_bus_be[1]),
	.addr_in(sub_palette_addr),
	.wdata_in(sub_palette_wdata),
	.we_lo_out(sfp_we_lo), .we_hi_out(sfp_we_hi),
	.addr_out(sfp_addr), .wdata_out(sfp_wdata),
	.q_in(fg_pal_ss_q),
	.ssbus(ssb[SS_IDX_FGPAL])
);

// Porta B unica (write muxata main/sub-ss + read di gather sullo stesso addr);
// porta A = lookup renderer. 2 porte totali = M10K true dual port.
wire [10:0] fgp_b_addr  = fg_pal_wr ? main_bus_addr[11:1] : sfp_addr;
wire [15:0] fgp_b_wdata = fg_pal_wr ? main_bus_dout       : sfp_wdata;
wire        fgp_b_we_hi = fg_pal_wr ? main_bus_be[1]      : sfp_we_hi;
wire        fgp_b_we_lo = fg_pal_wr ? main_bus_be[0]      : sfp_we_lo;
always @(posedge clk) begin
	if (fgp_b_we_hi) fg_pal_ram_hi[fgp_b_addr] <= fgp_b_wdata[15:8];
	if (fgp_b_we_lo) fg_pal_ram_lo[fgp_b_addr] <= fgp_b_wdata[7:0];
	fg_pal_ss_q <= {fg_pal_ram_hi[fgp_b_addr], fg_pal_ram_lo[fgp_b_addr]};
	fg_pal_data <= {fg_pal_ram_hi[fg_pal_addr], fg_pal_ram_lo[fg_pal_addr]};
end


darius_fg_renderer u_fg_renderer (
	.clk(clk), .reset(reset),
	.render_x(render_x), .render_y(render_y), .render_y_next(render_y_next), .render_y_first(render_y_first),
	.fg_ram_addr(fg_render_addr),
	.fg_ram_rdata(fg_render_rdata),
	.fg_stall(fg_render_stall),
	.dl_wr(fg_dl_wr), .dl_addr(fg_dl_addr), .dl_data(fg_dl_data),
	.fg_xoff(fg_xoff), .fg_yoff(fg_yoff),
	.pal_addr(fg_pal_addr), .pal_data(fg_pal_data),
	.fg_rgb(fg_rgb), .fg_opaque(fg_opaque)
);

// GFX ROM: ogni cliente ha la sua porta in sdrc_darius
// (req a livello + indirizzo in byte; valid impulso di un ciclo col dato a 32 bit),
// cosi' le letture dei tre pannelli e degli sprite sono in volo insieme. La porta tile del bridge resta ferma.
assign gfx_req  = {spr_be_req,  r2_tilerom_req,  r1_tilerom_req,  r0_tilerom_req};
assign gfx_addr = {spr_be_addr, r2_tilerom_addr, r1_tilerom_addr, r0_tilerom_addr};
assign r0_tilerom_data  = gfx_data[ 31: 0];  assign r0_tilerom_valid = gfx_valid[0];
assign r1_tilerom_data  = gfx_data[ 63:32];  assign r1_tilerom_valid = gfx_valid[1];
assign r2_tilerom_data  = gfx_data[ 95:64];  assign r2_tilerom_valid = gfx_valid[2];
assign spr_be_data      = gfx_data[127:96];  assign spr_be_valid     = gfx_valid[3];
assign tilerom_req       = 1'b0;
assign tilerom_addr      = 24'd0;
assign tilerom_is_sprite = 1'b0;
assign tilerom_is_text   = 1'b0;
wire [32:0] unused_tilerom = {tilerom_data, tilerom_valid};

// Output mux: select panel based on render_x
assign tile_rgb    = (render_x < 10'd288) ? r0_rgb :
                     (render_x < 10'd576) ? r1_rgb : r2_rgb;
assign tile_prio   = (render_x < 10'd288) ? r0_prio :
                     (render_x < 10'd576) ? r1_prio : r2_prio;
assign tile_opaque = (render_x < 10'd288) ? r0_opaque :
                     (render_x < 10'd576) ? r1_opaque : r2_opaque;


// =====================================================================
// Sprite renderer
// =====================================================================
// Sprite palette: shared with tile palette in panel renderer LEFT
// We need a separate palette read port for sprites — use a dedicated copy
wire [10:0] sprite_pal_addr;
reg  [15:0] sprite_pal_data;

// Sprite palette RAM (snooped from CPU, same as tile palette)
wire spr_pal_sel = (main_bus_addr >= 24'hD80000) && (main_bus_addr <= 24'hD80FFF);
wire spr_pal_wr_active = ~main_bus_asn && ~main_bus_rnw && main_bus_cs && (main_bus_dsn != 2'b11);
reg  spr_pal_seen;
always @(posedge clk) begin
	if (reset) spr_pal_seen <= 0;
	else if (!spr_pal_wr_active) spr_pal_seen <= 0;
	else spr_pal_seen <= 1;
end
wire spr_pal_wr = spr_pal_wr_active && !spr_pal_seen && spr_pal_sel;

(* ramstyle = "M10K,no_rw_check" *) reg [7:0] spr_pal_ram_hi [0:2047];
(* ramstyle = "M10K,no_rw_check" *) reg [7:0] spr_pal_ram_lo [0:2047];

// Adaptor savestate sulla gamba SUB (stesso schema della palette FG)
wire        ssp2_we_lo, ssp2_we_hi;
wire [10:0] ssp2_addr;
wire [15:0] ssp2_wdata;
reg  [15:0] spr_pal_ss_q;
ss_ram16_adaptor #(.WIDTHAD(11), .SS_IDX(SS_IDX_SPRPAL)) u_ss_sprpal (
	.clk(clk),
	.we_lo_in(sub_palette_wr & sub_bus_be[0]),
	.we_hi_in(sub_palette_wr & sub_bus_be[1]),
	.addr_in(sub_palette_addr),
	.wdata_in(sub_palette_wdata),
	.we_lo_out(ssp2_we_lo), .we_hi_out(ssp2_we_hi),
	.addr_out(ssp2_addr), .wdata_out(ssp2_wdata),
	.q_in(spr_pal_ss_q),
	.ssbus(ssb[SS_IDX_SPRPAL])
);

wire [10:0] spp_b_addr  = spr_pal_wr ? main_bus_addr[11:1] : ssp2_addr;
wire [15:0] spp_b_wdata = spr_pal_wr ? main_bus_dout       : ssp2_wdata;
wire        spp_b_we_hi = spr_pal_wr ? main_bus_be[1]      : ssp2_we_hi;
wire        spp_b_we_lo = spr_pal_wr ? main_bus_be[0]      : ssp2_we_lo;
always @(posedge clk) begin
	if (spp_b_we_hi) spr_pal_ram_hi[spp_b_addr] <= spp_b_wdata[15:8];
	if (spp_b_we_lo) spr_pal_ram_lo[spp_b_addr] <= spp_b_wdata[7:0];
	spr_pal_ss_q <= {spr_pal_ram_hi[spp_b_addr], spr_pal_ram_lo[spp_b_addr]};
	sprite_pal_data <= {spr_pal_ram_hi[sprite_pal_addr], spr_pal_ram_lo[sprite_pal_addr]};
end

darius_sprite_renderer #(.SS_IDX(SS_IDX_SPR_LOC)) u_sprite (
	.ssbus(ssb[SS_IDX_SPR_LOC]),
	.clk(clk), .reset(reset),
	.render_x(render_x), .render_y(render_y), .render_y_next(render_y_next), .render_y_first(render_y_first), .render_y_nat(render_y_nat), .snap_mode(spr_snap),
	.x_offset(10'd0),  // wide-screen: sprites use raw sx, no panel offset needed
	.cpu_bus_addr(main_bus_addr), .cpu_bus_asn(main_bus_asn),
	.cpu_bus_rnw(main_bus_rnw), .cpu_bus_dsn(main_bus_dsn),
	.cpu_bus_wdata(main_bus_dout), .cpu_bus_cs(main_bus_cs),
	.sub_bus_addr(sub_bus_addr), .sub_bus_asn(sub_bus_asn),
	.sub_bus_rnw(sub_bus_rnw), .sub_bus_dsn(sub_bus_dsn),
	.sub_bus_wdata(sub_bus_dout), .sub_bus_cs(sub_bus_cs),
	.spriterom_data(sprite_romdata), .spriterom_valid(sprite_romvalid),
	.spriterom_addr(sprite_romaddr), .spriterom_req(sprite_romreq),
	.spr_xoff(spr_xoff), .spr_yoff(spr_yoff),
	.pal_data(sprite_pal_data), .pal_lookup_addr(sprite_pal_addr),
	.sprite_rgb(sprite_rgb), .sprite_prio(sprite_prio), .sprite_opaque(sprite_opaque),
	.dbg_disp_word(),
	.ship_x(ship_x), .ship_commit(ship_commit)
);

// Cache ROM sprite interposta (renderer <-> cache <-> porta grafica 3). Port di Darius2
// (stesso HW), backend adattato alla porta SDRAM (pulse/valid) e cache RADDOPPIATA.
sprite_rom_cache u_spr_cache (
	.clk(clk), .reset(reset),
	.req_addr(sprite_romaddr), .req_pulse(sprite_romreq),
	.resp_data(sprite_romdata), .resp_valid(sprite_romvalid),
	.be_addr(spr_be_addr), .be_req(spr_be_req),
	.be_data(spr_be_data), .be_valid(spr_be_valid)
);

// =====================================================================
// Audio subsystem — 2× Z80 + YM2203 ×2 + MSM5205 + PC060HA
// =====================================================================
// [SS-HOOK] wire dei hook savestate audio (adaptor nel blocco framework)
wire        ss_zram_cpu_we, ss_zram_we;
wire [11:0] ss_zram_cpu_addr, ss_zram_addr;
wire  [7:0] ss_zram_cpu_wdata, ss_zram_wdata, ss_zram_q;
wire        ss_amisc_ld;
wire [55:0] ss_amisc_in, ss_amisc_out;
wire        ss_ym1_wr, ss_ym2_wr, ss_ym_a0;
wire  [7:0] ss_ym_wdata;
wire        ss_ymrp_active, ss_ymrp_cs1, ss_ymrp_cs2, ss_ymrp_a0, ss_ymrp_wr;
wire  [7:0] ss_ymrp_data;
wire        ss_ym_replay_busy;
wire        ss_ce_ym;   // [FIX ottava] tick campionamento jt03 verso il replay
wire [357:0] z80a_ss_in, z80a_ss_out;  wire z80a_ss_wr;
wire [357:0] z80b_ss_in, z80b_ss_out;  wire z80b_ss_wr;

// [SS-HOOK] impulso al RILASCIO della pausa-savestate = quando TUTTO il restore
// e' concluso (68k restore + replay YM, coperti da ss_pause_out). Risincronizza
// le fasi dei clock-enable audio (ce_cnt/msm_ce_cnt) -> l'audio riparte SEMPRE
// da fase 0 = restore deterministico, indipendente dal momento in cui lo si fa.
// NON e' il rilascio della pausa-utente (usa ss_pause_out, specifico savestate).
// A SS spento ss_pause_out=0 sempre -> impulso mai attivo -> TRASPARENTE.
reg  ss_pause_out_d;
always @(posedge clk) ss_pause_out_d <= ss_pause_out;
wire ss_restore_release = ss_pause_out_d & ~ss_pause_out;

darius_audio_z80 u_audio (
	.clk(clk), .reset(reset),
	.pause(pause),
	.clk_sel(z80_clk_sel),
	.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
	.ioctl_wait(audio_ioctl_wait),
	.DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(audio_DDRAM_BURSTCNT),
	.DDRAM_ADDR(audio_DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(audio_DDRAM_RD),
	.DDRAM_DIN(audio_DDRAM_DIN), .DDRAM_BE(audio_DDRAM_BE), .DDRAM_WE(audio_DDRAM_WE),
	.snd_cs(pc060_snd_cs),
	.snd_addr(pc060_snd_addr),
	.snd_wr(pc060_snd_wr),
	.snd_rd(pc060_snd_rd),
	.snd_wdata(pc060_snd_wdata),
	.snd_rdata(pc060_snd_rdata),
	.snd_nmi_n(pc060_snd_nmi_n),
	.snd_reset_in(pc060_snd_reset),
	.audio_l(audio_l), .audio_r(audio_r),
	// [SS-HOOK] Fase A: ZRAM interposta + registri misc (adaptor sotto, nel
	// blocco framework). Rimozione SS: ss_zram_* = ss_zram_cpu_*, ld = 0.
	.ss_zram_cpu_we(ss_zram_cpu_we), .ss_zram_cpu_addr(ss_zram_cpu_addr),
	.ss_zram_cpu_wdata(ss_zram_cpu_wdata),
	.ss_zram_we(ss_zram_we), .ss_zram_addr(ss_zram_addr),
	.ss_zram_wdata(ss_zram_wdata), .ss_zram_q(ss_zram_q),
	.ss_amisc_ld(ss_amisc_ld), .ss_amisc_in(ss_amisc_in),
	.ss_amisc_out(ss_amisc_out),
	// [SS-HOOK] Fase B: snoop YM + injector replay
	.ss_ym1_wr(ss_ym1_wr), .ss_ym2_wr(ss_ym2_wr),
	.ss_ym_a0(ss_ym_a0), .ss_ym_wdata(ss_ym_wdata),
	.ss_ymrp_active(ss_ymrp_active),
	.ss_ymrp_cs1(ss_ymrp_cs1), .ss_ymrp_cs2(ss_ymrp_cs2),
	.ss_ymrp_a0(ss_ymrp_a0), .ss_ymrp_data(ss_ymrp_data),
	.ss_ymrp_wr(ss_ymrp_wr),
	.ss_ce_ym(ss_ce_ym),   // [FIX ottava] verso il replay
	// [SS-HOOK] Fase C: stato rmZ80 (2x 274 bit nelle sezioni da 358)
	.ss_z80a_ssin(z80a_ss_in), .ss_z80a_ssout(z80a_ss_out), .ss_z80a_sswr(z80a_ss_wr),
	.ss_z80b_ssin(z80b_ss_in), .ss_z80b_ssout(z80b_ss_out), .ss_z80b_sswr(z80b_ss_wr),
	.mix_sel_fm0(mix_sel_fm0), .mix_sel_fm1(mix_sel_fm1),
	.mix_sel_p0a(mix_sel_p0a), .mix_sel_p0b(mix_sel_p0b), .mix_sel_p0c(mix_sel_p0c),
	.mix_sel_p1a(mix_sel_p1a), .mix_sel_p1b(mix_sel_p1b), .mix_sel_p1c(mix_sel_p1c),
	.mix_sel_msm(mix_sel_msm),
	.ss_restore_release(ss_restore_release)
);

// =====================================================================
// Savestate — framework (cablaggio 1:1 da BoogieWings boogwings_top)
// =====================================================================

// --- Audio Fase A: adaptor ZRAM (8-bit) + registri misc, via hook esterni ---
// I chip audio restano vanilla: qui si interpone solo la porta write della
// RAM Z80A e si campionano/ricaricano i registri misc del modulo audio.
// (wire dichiarate sopra u_audio, blocco [SS-HOOK])
ss_ram_adaptor #(.WIDTH(8), .WIDTHAD(12), .SS_IDX(SS_IDX_ZRAM)) u_ss_zram (
	.clk(clk),
	.wren_in(ss_zram_cpu_we),
	.addr_in(ss_zram_cpu_addr),
	.wdata_in(ss_zram_cpu_wdata),
	.wren_out(ss_zram_we),
	.addr_out(ss_zram_addr),
	.wdata_out(ss_zram_wdata),
	.q_in(ss_zram_q),
	.ssbus(ssb[SS_IDX_ZRAM])
);

auto_save_adaptor #(.N_BITS(56), .SS_IDX(SS_IDX_AMISC)) u_ss_amisc (
	.clk(clk),
	.ssbus(ssb[SS_IDX_AMISC]),
	.bits_in(ss_amisc_out),
	.bits_out(ss_amisc_in),
	.bits_wr(ss_amisc_ld)
);

// --- Audio Fase C: stato delle due rmZ80 (savestate parallelo, rmZ80 docs/07 §4) ---
// auto_save_adaptor (load a blocco unico su bits_wr=sentinella): rmZ80 carica tutto
// lo stato in un clock con ss_load = bits_wr, a CPU ferme. La sezione resta da 358 bit:
// rmZ80 ne usa i 274 bassi, gli 84 alti escono a 0. Trasparente a sswr=0.
auto_save_adaptor #(.N_BITS(358), .SS_IDX(SS_IDX_Z80A)) u_ss_z80a (
	.clk(clk), .ssbus(ssb[SS_IDX_Z80A]),
	.bits_in(z80a_ss_out), .bits_out(z80a_ss_in), .bits_wr(z80a_ss_wr)
);
auto_save_adaptor #(.N_BITS(358), .SS_IDX(SS_IDX_Z80B)) u_ss_z80b (
	.clk(clk), .ssbus(ssb[SS_IDX_Z80B]),
	.bits_in(z80b_ss_out), .bits_out(z80b_ss_in), .bits_wr(z80b_ss_wr)
);

// (SS7y) livello "stream di caricamento in corso" per ss_ym_shadow: dall'avvio del caricamento alla fine dello stream
reg  ss_ld_lvl = 1'b0, ss_busy_d = 1'b0;
// (SS7p) gli impulsi di avvio dello stream escono da un flop che ha come soli utenti save_state_data e ss_ym_shadow
reg  ss_do_save_q = 1'b0, ss_do_load_q = 1'b0;
// --- Audio Fase B: shadow registri YM + replay al restore (chip vanilla) ---
ss_ym_shadow #(.SS_IDX_SH1(SS_IDX_YMSH1), .SS_IDX_SH2(SS_IDX_YMSH2)) u_ss_ymsh (
	.clk(clk),
	.reset(reset),
	.ce_ym(ss_ce_ym),   // [FIX ottava] limita ogni write del replay a 1 ce
	.ym1_wr(ss_ym1_wr), .ym2_wr(ss_ym2_wr),
	.a0(ss_ym_a0), .wdata(ss_ym_wdata),
	.ss_mem_read(ss_ld_lvl),
	.replay_busy(ss_ym_replay_busy),
	.rp_active(ss_ymrp_active),
	.rp_cs1(ss_ymrp_cs1), .rp_cs2(ss_ymrp_cs2),
	.rp_a0(ss_ymrp_a0), .rp_data(ss_ymrp_data), .rp_wr(ss_ymrp_wr),
	.ssb1(ssb[SS_IDX_YMSH1]),
	.ssb2(ssb[SS_IDX_YMSH2])
);

// --- CTRL: cpua_ctrl_reg + registri scroll/ctrl (auto_save_adaptor) ---
// bits = {cpua_ctrl(8), xs0,xs1,ys0,ys1,c0,c1 (16 ciascuno)} = 104 bit.
// Al restore bits_wr ricarica cpua_ctrl_reg e (broadcast) i regs dei 3 pannelli.
wire [103:0] ss_ctrl_out;
wire [7:0]   ss_cpua_ctrl = ss_ctrl_out[103:96];
assign {ss_xs0, ss_xs1, ss_ys0, ss_ys1, ss_c0, ss_c1} = ss_ctrl_out[95:0];
auto_save_adaptor #(.N_BITS(104), .SS_IDX(SS_IDX_CTRL)) u_ss_ctrl (
	.clk(clk),
	.ssbus(ssb[SS_IDX_CTRL]),
	.bits_in({cpua_ctrl_reg, xscroll_l0, xscroll_l1, yscroll_l0, yscroll_l1, ctrl_l0, ctrl_l1}),
	.bits_out(ss_ctrl_out),
	.bits_wr(ss_regs_ld)
);

// --- savestate dei due 68000 ---
wire ss_do_save, ss_do_load;
always @(posedge clk) begin   // (SS7p) registro di passaggio verso il framework
	if (reset) begin ss_do_save_q <= 1'b0; ss_do_load_q <= 1'b0; end
	else begin ss_do_save_q <= ss_do_save; ss_do_load_q <= ss_do_load; end
end
wire ss_busy;
always @(posedge clk) begin   // (SS7y) caricamento in corso: sale con l'avvio, scende alla fine dello stream
	if (reset) begin ss_ld_lvl <= 1'b0; ss_busy_d <= 1'b0; end
	else begin
		ss_busy_d <= ss_busy;
		if (ss_do_load) ss_ld_lvl <= 1'b1;
		else if (ss_busy_d && !ss_busy) ss_ld_lvl <= 1'b0;
	end
end
wire ss_slot_empty;   // [FIX slot vuoto] da u_save_state a u_ss68k

// ---- (SS7) savestate esterno dei due 68000: m68k_ss_seq a sequenza (clean room); sezione = 4 parole su SS_IDX_GLOBAL
wire         ss68_pause;
wire         ss68_sec_rd, ss68_sec_wr;
wire [15:0]  ss68_sec_wdata;

m68k_ss_seq #(.N(2), .WIN_BASE(24'hFF0000), .H_SCR(24'hFF0040)) u_ss68k (
	.clk(clk), .rst(reset),
	.ss_save(ss_save), .ss_load(ss_load), .paused(paused_real), .ss_busy(ss_busy), .slot_empty(ss_slot_empty),
	.ss_pause(ss68_pause), .ss_mem_write(ss_do_save), .ss_mem_read(ss_do_load),
	.sec_word(ss68_sec_word), .sec_rd(ss68_sec_rd), .sec_wr(ss68_sec_wr), .sec_wdata(ss68_sec_wdata),
	.cpu_as_n({sub_bus_asn, main_bus_asn}),
	.cpu_rw({sub_bus_rnw, main_bus_rnw}),
	.cpu_fc({sub_fc, main_fc}),
	.cpu_dout({sub_bus_dout, main_bus_dout}),
	.cpu_in_reset({reset | (HOLD_SUB_IN_RESET ? 1'b1 : ~cpua_ctrl_reg[0]), reset}),
	.cpu_exec({ss68_s_exec, ss68_m_exec}), .cpu_ovr({ss68_s_ovr, ss68_m_ovr}), .cpu_sspsel({ss68_s_ssp, ss68_m_ssp}),
	.cpu_word(ss68_word), .cpu_ipl7({ss68_s_i7, ss68_m_i7}), .cpu_iplhide({ss68_s_hide, ss68_m_hide}),
	.cpu_soft_reset({ss68_s_srst, ss68_m_srst}),
	.state_o(), .phase_o(), .cpu_sel_o()
);

ss68_sec_slave #(.SS_IDX(SS_IDX_GLOBAL), .N_WORDS(4)) u_ss68k_sec (
	.clk(clk), .ssbus(ssb[SS_IDX_GLOBAL]),
	.word(ss68_sec_word), .rd(ss68_sec_rd), .wr(ss68_sec_wr), .wdata(ss68_sec_wdata)
);
// [SS-HOOK] la pausa resta alta anche durante replay YM e handler Z80
assign ss_pause_out = ss68_pause | ss_ym_replay_busy;

// --- Gate DDR fra adapter audio (master gioco) e memory_stream (master SS) ---
wire  [7:0] audio_DDRAM_BURSTCNT;
wire [28:0] audio_DDRAM_ADDR;
wire        audio_DDRAM_RD;
wire [63:0] audio_DDRAM_DIN;
wire  [7:0] audio_DDRAM_BE;
wire        audio_DDRAM_WE;

ddr_if ss_ddr();
wire ss_hold, ss_ddr_grant;
wire ss_tx_inflight = ss_ddr.read | ss_ddr.write;

ss_ddr_gate #(.AW(29), .DRAIN_TH(3)) u_ss_ddr_gate (
	.clk            (clk),
	.reset          (reset),
	.ss_busy        (ss_busy),
	.ss_tx_inflight (ss_tx_inflight),
	.game_burstcnt  (audio_DDRAM_BURSTCNT),
	.game_addr      (audio_DDRAM_ADDR),
	.game_rd        (audio_DDRAM_RD),
	.game_din       (audio_DDRAM_DIN),
	.game_be        (audio_DDRAM_BE),
	.game_we        (audio_DDRAM_WE),
	.ss_burstcnt    (ss_ddr.burstcnt),
	.ss_addr        (ss_ddr.addr[31:3]),
	.ss_rd          (ss_ddr.read),
	.ss_din         (ss_ddr.wdata),
	.ss_be          (ss_ddr.byteenable),
	.ss_we          (ss_ddr.write),
	.DDRAM_BUSY     (DDRAM_BUSY),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_BURSTCNT (DDRAM_BURSTCNT),
	.DDRAM_ADDR     (DDRAM_ADDR),
	.DDRAM_RD       (DDRAM_RD),
	.DDRAM_DIN      (DDRAM_DIN),
	.DDRAM_BE       (DDRAM_BE),
	.DDRAM_WE       (DDRAM_WE),
	.ss_hold        (ss_hold),
	.ss_ddr_grant   (ss_ddr_grant)
);

// ddr_if del savestate <-> bus fisico (pattern BW: stall finche' non c'e' grant)
assign ss_ddr.rdata       = DDRAM_DOUT;
assign ss_ddr.rdata_ready = ss_ddr_grant & DDRAM_DOUT_READY;
assign ss_ddr.busy        = ~ss_ddr_grant | DDRAM_BUSY;

// --- mux slave + master memory_stream ---
ssbus_mux #(.COUNT(SS_NSLAVES)) ss_mux (
	.clk     (clk),
	.slave   (ssbus),
	.masters (ssb)
);

save_state_data #(.COUNT(SS_MS_COUNT)) u_save_state (
	.clk        (clk),
	.reset      (reset),
	.ddr        (ss_ddr),
	.read_start (ss_do_load_q),
	.write_start(ss_do_save_q),
	.index      (ss_slot),
	.busy       (ss_busy),
	.slot_empty (ss_slot_empty),   // [FIX slot vuoto]
	.ssbus      (ssbus)
);

endmodule
