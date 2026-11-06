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

// cpu68000_bridge — il MC68000 (rm68000: m68k_cpu_dt_si, processore + generatore DTACK in un nodo) verso il bus
// sincrono del core Darius: AS/UDS/LDS/R-W del processore diventano bus_rd/bus_wr/bus_addr/bus_wdata, l'IACK si
// riconosce da FC = 111 (autovettore: VPAn basso nel ciclo di IACK), il livello di interrupt arriva su irq_level.
// Le fasi cen/cenb e il DTACK nascono dentro m68k_cpu_dt_si dal divisore clk_num/clk_den, con il recupero dei cicli
// persi in attesa della memoria (bus_cs/bus_busy); la pausa (pause_n) e' registrata li' dentro. Le porte ss_* sono
// quelle del savestate esterno (rm68000 docs/external-savestate.md); qui non usate (SS_EXT = 0), il savestate dei
// 68000 sostituisce dato e IPL nel top (m68k_ss_seq). Vale per entrambe le CPU (main e sub), istanziato dal nodo.

module cpu68000_bridge
#(
	parameter [0:0] CPU_ID = 1'b0
)
(
	input  wire        clk,
	input  wire        reset,
	input  wire        reset_cpu,    // reset non registrato per il processore, che lo registra dentro (rst_q del nodo)
	input  wire [6:0]  clk_num,      // divisore del generatore DTACK, dentro il processore
	input  wire [7:0]  clk_den,
	input  wire [15:0] bus_rdata,
	input  wire        bus_cs,       // accesso alla memoria lenta (SDRAM), dalla mappa
	input  wire        bus_busy,     // memoria occupata: trattiene il DTACK
	input  wire        pause_n,      // 1 = il processore avanza; pausa registrata dentro al processore
	input  wire [2:0]  irq_level,

	output reg         active,
	output reg  [31:0] cycles,
	output reg  [23:0] bus_addr,
	output reg         bus_rd,
	output reg         bus_wr,
	output reg  [15:0] bus_wdata,
	output wire [1:0]  bus_dsn_out,
	output wire        cpu_asn,      // AS del processore
	output wire [1:0]  cpu_dsn,      // {UDSn, LDSn} del processore
	output reg  [15:0] last_read,
	output wire [23:0] dbg_pc,
	output wire [2:0]  fc_out,       // function code del processore
	output wire        dtack_n_o,    // DTACKn del generatore interno (per il nodo: dbg_dtackn)
	output wire        cpu_rw_out,   // R/W del processore (savestate esterno)
	output wire        ss_cen_raw,   // clock-enable grezzi del generatore (savestate esterno)
	output wire        ss_cenb_raw,
	input  wire        ss_cen_g,     // clock-enable chiusi a cicli interi dal savestate
	input  wire        ss_cenb_g,
	input  wire        ss_gate_q,    // chiusura del savestate e suo ingresso
	input  wire        ss_gate_raw,
	input  wire        ss_ovr,       // sostituzione del dato dal savestate
	input  wire [15:0] ss_word,
	input  wire        ss_ovr_c,     // forma combinatoria (rete di sicurezza)
	input  wire [15:0] ss_word_c,
	output wire        iack
);

// dal processore: fasi gated con la pausa e DTACKn del generatore interno
wire ce_cpu, ce_cpub, bus_dtackn;
assign dtack_n_o  = bus_dtackn;
assign cpu_rw_out = c_rw;

// segnali del bus del 68000 (controlli attivi bassi)
wire [23:1] c_addr;
wire [15:0] c_data_out;
// il latch del dato letto (preso col DTACK) sta dentro m68k_cpu_dt_si
wire        c_as_n;
wire        c_uds_n;
wire        c_lds_n;
wire        c_rw;
wire [2:0]  c_ipl_n;
wire        c_halt_n;
wire        c_fc0;
wire        c_fc1;
wire        c_fc2;

assign c_halt_n    = 1'b1;
assign bus_dsn_out = {c_uds_n, c_lds_n};
assign cpu_asn     = c_as_n;
assign cpu_dsn     = {c_uds_n, c_lds_n};

// le linee di interrupt del 68000 sono attive basse
assign c_ipl_n = ~irq_level;

// IACK: FC2:FC0 = 111 durante un ciclo di bus = riconoscimento di interrupt
wire iack_cycle = c_fc0 & c_fc1 & c_fc2;
assign iack = iack_cycle & ~c_as_n;

wire lane_sel = (~c_uds_n) | (~c_lds_n);
wire bus_req  = (~c_as_n) & lane_sel;
wire bus_rd_w = bus_req & c_rw & ~iack_cycle;
wire bus_wr_w = bus_req & ~c_rw & ~iack_cycle;
wire [2:0] c_fc = {c_fc2, c_fc1, c_fc0};
assign fc_out = c_fc;
wire prog_fetch_w = bus_rd_w && ((c_fc == 3'b010) || (c_fc == 3'b110));
reg  [23:0] dbg_pc_reg;

always @(*) begin
	bus_addr  = {c_addr, 1'b0};
	bus_rd    = bus_rd_w;
	bus_wr    = bus_wr_w;
	bus_wdata = c_data_out;
end

always @(posedge clk) begin
	if(reset) begin
		cycles     <= 32'd0;
		active     <= 1'b0;
		last_read  <= 16'd0;
		dbg_pc_reg <= 24'd0;
	end else begin
		if(ce_cpu) begin
			active <= 1'b1;
			cycles <= cycles + 32'd1;
		end

		// dato preso quando il DTACK e' attivo (basso)
		if(bus_req && !bus_dtackn && !iack_cycle) begin
			if(prog_fetch_w)
				dbg_pc_reg <= {c_addr, 1'b0};
			if(bus_rd_w) begin
				last_read  <= bus_rdata;
			end
		end
	end
end

// === rm68000: processore + generatore DTACK
wire        w_data_oe_nc, w_e_nc, w_vma_n_nc, w_halted_n_nc, w_bg_n_nc, w_bus_tri_nc, w_iack_nc;
wire [23:0] w_dbg_pc_nc;
m68k_cpu_dt_si #(.W(8), .RECOVERY(1), .RST_REG(1'b1), .SS_EXT(1'b0)) u_cpu (
	.clk      (clk),
	.reset    (reset_cpu),   // non registrato: dentro lo registra (rst_q per il generatore, tre copie per il processore)
	.num      (clk_num),
	.den      (clk_den),
	.bus_cs   (bus_cs),
	.bus_busy (bus_busy),
	.pause_n  (pause_n),
	.cen_o    (ce_cpu),
	.cenb_o   (ce_cpub),
	.dtack_n_o(bus_dtackn),
	.cen_raw_o(ss_cen_raw), .cenb_raw_o(ss_cenb_raw), .cen_ext_i(ss_cen_g), .cenb_ext_i(ss_cenb_g),
	.gate_q_i(ss_gate_q), .gate_raw_i(ss_gate_raw), .ss_ovr_i(ss_ovr), .ss_word_i(ss_word), .ss_ovr_c_i(ss_ovr_c), .ss_word_c_i(ss_word_c),
	.addr     (c_addr),
	.as_n     (c_as_n),
	.uds_n    (c_uds_n),
	.lds_n    (c_lds_n),
	.rw       (c_rw),
	.data_oe  (w_data_oe_nc),
	.bus_rdata(bus_rdata),       // il latch del dato e' dentro al modulo
	.data_out (c_data_out),
	.fc       ({c_fc2, c_fc1, c_fc0}),
	.ipl_n    (c_ipl_n),
	.iack     (w_iack_nc),
	.vpa_n    (iack_cycle ? 1'b0 : 1'b1),
	.vma_n    (w_vma_n_nc),
	.e        (w_e_nc),
	.berr_n   (1'b1),
	.halt_n   (c_halt_n),
	.halted_n (w_halted_n_nc),
	.br_n     (1'b1),
	.bg_n     (w_bg_n_nc),
	.bgack_n  (1'b1),
	.bus_tri  (w_bus_tri_nc),
	.dbg_pc   (w_dbg_pc_nc)
);
assign dbg_pc = dbg_pc_reg;

endmodule
