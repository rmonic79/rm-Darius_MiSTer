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

// darius_cpu_node — nodo di una CPU 68000 del core (main o sub): il processore rm68000 nel ponte cpu68000_bridge,
// con il reset registrato, l'IPL e l'interfaccia di bus comune. Le fasi della CPU e il DTACK nascono dentro il
// processore (m68k_cpu_dt_si) dal divisore clk_num/clk_den.

module darius_cpu_node
#(
	parameter [0:0] CPU_ID = 1'b0,
	parameter [1:0] CORE_IMPL = 2'd1
)
(
	input  wire        clk,
	input  wire        reset,
	input  wire        soft_reset,
	input  wire        halt_n,
	input  wire  [6:0] clk_num,
	input  wire  [7:0] clk_den,
	input  wire [2:0]  ipl_n,
	input  wire [15:0] bus_din,
	input  wire        bus_cs,
	input  wire        bus_busy,
	input  wire        dev_br,
	output wire [23:0] bus_addr,
	output wire        bus_asn,
	output wire        bus_rnw,
	output wire [1:0]  bus_dsn,
	output wire [15:0] bus_dout,
	output wire [23:0] dbg_pc,
	output wire [2:0]  dbg_fc,
	output wire        dbg_dtackn,
	output wire [15:0] dbg_fave,
	output wire [15:0] dbg_fworst,
	output wire        iack,
	output wire        bus_rw_raw,
	output wire        ss_cen_raw,
	output wire        ss_cenb_raw,
	input  wire        ss_cen_g,
	input  wire        ss_cenb_g,
	input  wire        ss_gate_q,
	input  wire        ss_gate_raw,
	input  wire        ss_ovr,
	input  wire [15:0] ss_word,
	input  wire        ss_ovr_c,
	input  wire [15:0] ss_word_c
);

// (B, 14/10) reset registrato nel nodo: il reset di emu (hps status/cfg/ioctl) arrivava al control store del
// processore con 3 ns di rotta e 7 celle. Un clock di ritardo sul reset di tutto il nodo (DTACK, ponte, CPU),
// uguale per main e sub: nessun ciclo del processore cambia. Accensione a 1 (reset attivo).
reg rst_q = 1'b1;
always @(posedge clk) rst_q <= reset | soft_reset;

// le fasi cpu_cen/cpu_cenb e il generatore DTACK (con il recupero dei cicli persi in attesa della SDRAM) stanno
// dentro al processore (m68k_cpu_dt_si nel ponte); bus_cs e bus_busy vanno direttamente a lui
wire        dtack_n;
wire        cpu_active;
wire [31:0] cpu_cycles;
wire [23:0] cpu_bus_addr;
wire        cpu_bus_rd;
wire        cpu_bus_wr;
wire [15:0] cpu_bus_wdata;
wire [15:0] cpu_last_read_unused;
wire [23:0] cpu_dbg_pc;
wire        cpu_iack;
wire [1:0]  cpu_dsn_out;
wire [2:0]  cpu_fc_w;
wire [2:0]  irq_level = ~ipl_n;

// segnali del processore per il bus
wire        cpu_asn;
wire [1:0]  cpu_dsn;

// (L1, 14/10) pausa registrata: halt_n arriva dal top come logica (pausa, savestate) e il suo percorso finiva nel
// banco registri del processore con 6 LUT e 7 salti. La pausa registrata e l'AND con le fasi stanno dentro
// m68k_cpu_dt_si: qui passa solo halt_n. La pausa agisce sul processore un clock dopo; nessun ciclo cambia.

cpu68000_bridge #(.CPU_ID(CPU_ID)) u_bridge (
	.clk(clk),
	.reset(rst_q),       // (B) reset registrato nel nodo
	.reset_cpu(rst_q),   // (RST4, 15/10) il reset registrato del nodo: dentro, il generatore DTACK e le copie del processore lo prendono un clock dopo il ponte, uniformemente
	.clk_num(clk_num),
	.clk_den(clk_den),
	.bus_cs(bus_cs),
	.bus_busy(bus_busy),
	.pause_n(halt_n),
	.dtack_n_o(dtack_n),
	.bus_rdata(bus_din),
	.irq_level(irq_level),
	.active(cpu_active),
	.cycles(cpu_cycles),
	.bus_addr(cpu_bus_addr),
	.bus_rd(cpu_bus_rd),
	.bus_wr(cpu_bus_wr),
	.bus_wdata(cpu_bus_wdata),
	.bus_dsn_out(cpu_dsn_out),
	.cpu_asn(cpu_asn),
	.cpu_dsn(cpu_dsn),
	.last_read(cpu_last_read_unused),
	.dbg_pc(cpu_dbg_pc),
	.fc_out(cpu_fc_w),
	.iack(cpu_iack),
	.cpu_rw_out(bus_rw_raw),
	.ss_cen_raw(ss_cen_raw),
	.ss_cenb_raw(ss_cenb_raw),
	.ss_cen_g(ss_cen_g),
	.ss_cenb_g(ss_cenb_g),
	.ss_gate_q(ss_gate_q),
	.ss_gate_raw(ss_gate_raw),
	.ss_ovr(ss_ovr),
	.ss_word(ss_word),
	.ss_ovr_c(ss_ovr_c),
	.ss_word_c(ss_word_c)
);

assign bus_addr    = cpu_bus_addr;
assign bus_asn     = cpu_asn;
assign bus_rnw     = cpu_bus_rd;
assign bus_dsn     = cpu_dsn_out;
assign bus_dout    = cpu_bus_wdata;
assign dbg_pc      = cpu_dbg_pc;
assign dbg_fc      = cpu_fc_w;   // function code del processore (savestate dei 68000)
assign dbg_dtackn  = dtack_n;
assign dbg_fave    = 16'd0;      // statistiche del generatore DTACK: non esposte
assign dbg_fworst  = 16'd0;
assign iack        = cpu_iack;

endmodule
