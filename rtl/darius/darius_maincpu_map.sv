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

// darius_maincpu_map — Memory map del Main 68000.
// Decode e dispatch bus della CPU principale verso ROM, main RAM, shared RAM,
// sprite RAM, FG RAM, palette, I/O ports, PC060HA, watchdog e controlli
// scroll/control. FSM TXN per accessi multi-ciclo a BRAM.

module darius_maincpu_map
#(
	parameter ENABLE_NOP_C00050 = 1'b0,
	parameter ENABLE_WATCHDOG   = 1'b0,
	parameter ENABLE_PC080_CTRL = 1'b0,
	parameter ENABLE_DC0000     = 1'b0,
	parameter ENABLE_C00060     = 1'b0,
	parameter ENABLE_C00020     = 1'b0,
	parameter ENABLE_C00022     = 1'b0,
	parameter ENABLE_C00024     = 1'b0,
	parameter ENABLE_C00030     = 1'b0,
	parameter ENABLE_C00032     = 1'b0,
	parameter ENABLE_C00034     = 1'b0,
	parameter ENABLE_D40000     = 1'b0,
	parameter ENABLE_D40002     = 1'b0,
	parameter ENABLE_D20000     = 1'b0,
	parameter ENABLE_D20002     = 1'b0,
	parameter ENABLE_C0000C     = 1'b0,
	parameter ENABLE_C00010     = 1'b0,
	parameter ENABLE_PC060HA_PORT = 1'b0,
	parameter ENABLE_PC060HA_COMM = 1'b0,
	parameter ENABLE_D00000     = 1'b0,
	parameter ENABLE_PALETTE    = 1'b0,
	parameter ENABLE_FG         = 1'b0,
	parameter ENABLE_CTRL   = 1'b0,
	parameter ENABLE_SHARED = 1'b0,
	parameter ENABLE_SPRITE = 1'b0,
	parameter ENABLE_IO     = 1'b0,
	parameter ENABLE_VIDEO  = 1'b0,
	parameter ENABLE_PLAYER_IO = 1'b0
)
(
	input  wire        clk,
	input  wire        reset,
	input  wire  [7:0] p1_input,     // player 1 (active low)
	input  wire  [7:0] p2_input,     // player 2 (active low)
	input  wire  [7:0] system_input, // MAME SYSTEM port: {00,start2,start1,tilt,service,coin2,coin1}
	input  wire [15:0] dsw_input,    // DIP switches
	input  wire [23:0] bus_addr,
	input  wire        bus_asn,
	input  wire        bus_rnw,
	input  wire [1:0]  bus_dsn,
	input  wire [15:0] bus_wdata,
	output reg  [15:0] bus_rdata,
	output reg         bus_cs,
	output reg         bus_busy,
	input  wire [15:0] rom_rdata,
	input  wire        rom_ready,
	input  wire [7:0]  cpua_ctrl_q,
	input  wire [15:0] shared_rdata,
	input  wire        shared_ready,
	output reg         shared_rd,
	output reg         shared_wr,
	output reg  [11:0] shared_addr,
	output reg  [15:0] shared_wdata,
	input  wire [15:0] sprite_rdata,
	input  wire        sprite_ready,
	output reg         sprite_rd,
	output reg         sprite_wr,
	output reg  [10:0] sprite_addr,
	output reg  [15:0] sprite_wdata,
	input  wire [15:0] fg_rdata,
	input  wire        fg_ready,
	output reg         fg_rd,
	output reg         fg_wr,
	output reg  [13:0] fg_addr,
	output reg  [15:0] fg_wdata,
	input  wire [15:0] ram_rdata,
	output reg         ram_rd,
	output reg         ram_wr,
	output reg  [1:0]  ram_be,     // byte enable: ~bus_dsn
	output wire [1:0]  bus_byte_en, // byte enable for ALL RAM writes
	output reg  [14:0] ram_addr,
	output reg  [15:0] ram_wdata,
	input  wire [15:0] e100_rdata,
	output reg         e100_rd,
	output reg         e100_wr,
	output reg  [10:0] e100_addr,
	output reg  [15:0] e100_wdata,
	input  wire [15:0] d000_rdata,
	output reg         d000_rd,
	output reg         d000_wr,
	output reg  [14:0] d000_addr,
	output reg  [15:0] d000_wdata,
	input  wire [15:0] palette_rdata,
	input  wire        palette_ready,
	output reg         palette_rd,
	output reg         palette_wr,
	output reg  [10:0] palette_addr,
	output reg  [15:0] palette_wdata,
	output reg         cpua_ctrl_wr,
	output reg  [7:0]  cpua_ctrl_data,
	output reg         pc060ha_port_wr,
	output reg  [7:0]  pc060ha_port_data,
	output reg         pc060ha_comm_wr,
	output reg  [7:0]  pc060ha_comm_data,
	input  wire [7:0]  pc060ha_comm_rdata,
	output reg  [23:0] rom_addr,
	output reg         rom_req,
	output reg  [15:0] cs_vector
);

localparam CS_ROM    = 0;
localparam CS_RAM    = 1;
localparam CS_SHARED = 2;
localparam CS_SPRITE = 3;
localparam CS_IO     = 4;
localparam CS_VIDEO  = 5;
localparam CS_CTRL   = 6;
localparam CS_NOP    = 7;
localparam CS_WDOG   = 8;
localparam CS_PC080_CTRL = 9;
localparam CS_DC0000 = 10;
localparam CS_C00060 = 11;
localparam CS_C00020 = 12;
localparam CS_C00022 = 13;
localparam CS_C00024 = 14;
localparam CS_C00030 = 15;
localparam CS_C00032 = 16;
localparam CS_C00034 = 17;
localparam CS_D40000 = 18;
localparam CS_D40002 = 19;
localparam CS_D20000 = 20;
localparam CS_D20002 = 21;
localparam CS_E10000 = 22;
localparam CS_C00010 = 23;
localparam CS_PC060HA = 24;
localparam CS_PC060HA_COMM = 25;

localparam TXN_NONE       = 6'd0;
localparam TXN_ROM        = 6'd1;
localparam TXN_RAM_WAIT   = 6'd2;
localparam TXN_RAM_RD     = 6'd3;
localparam TXN_RAM_WR     = 6'd4;
localparam TXN_SHARED_WAIT = 6'd5;
localparam TXN_SHARED_RD  = 6'd6;
localparam TXN_SHARED_WR  = 6'd7;
localparam TXN_SPRITE_RD  = 6'd8;
localparam TXN_SPRITE_WR  = 6'd9;
localparam TXN_CTRL       = 6'd10;
localparam TXN_IO         = 6'd11;
localparam TXN_VIDEO      = 6'd12;
localparam TXN_NOP        = 6'd13;
localparam TXN_WDOG       = 6'd14;
localparam TXN_PC080_CTRL = 6'd15;
localparam TXN_DC0000     = 6'd16;
localparam TXN_C00060     = 6'd17;
localparam TXN_C00020     = 6'd18;
localparam TXN_C00022     = 6'd19;
localparam TXN_C00024     = 6'd20;
localparam TXN_C00030     = 6'd21;
localparam TXN_C00032     = 6'd22;
localparam TXN_C00034     = 6'd23;
localparam TXN_D40000     = 6'd24;
localparam TXN_D40002     = 6'd25;
localparam TXN_D20000     = 6'd26;
localparam TXN_D20002     = 6'd27;
localparam TXN_C0000C     = 6'd28;
localparam TXN_E100_WAIT  = 6'd29;
localparam TXN_E100_RD    = 6'd30;
localparam TXN_E100_WR    = 6'd31;
localparam TXN_C00010     = 6'd32;
localparam TXN_PC060HA    = 6'd33;
localparam TXN_PC060HA_COMM = 6'd34;
localparam TXN_D000_RD    = 6'd35;
localparam TXN_D000_WR    = 6'd36;
localparam TXN_PALETTE_WAIT = 6'd37;
localparam TXN_PALETTE_RD = 6'd38;
localparam TXN_PALETTE_WR = 6'd39;
localparam TXN_FG_RD      = 6'd44;
localparam TXN_FG_WR      = 6'd45;
localparam TXN_UNMAPPED   = 6'd46;
localparam TXN_DONE       = 6'd47;

wire sel_rom    = (bus_addr >= 24'h000000) && (bus_addr <= 24'h05ffff);
wire sel_ram    = (bus_addr >= 24'h080000) && (bus_addr <= 24'h08ffff);
wire sel_ctrl   = ENABLE_CTRL   && (bus_addr >= 24'h0a0000) && (bus_addr <= 24'h0a0001);
wire sel_wdog   = ENABLE_WATCHDOG && (bus_addr >= 24'h0b0000) && (bus_addr <= 24'h0b0001);
wire sel_pc080_ctrl = ENABLE_PC080_CTRL && (bus_addr >= 24'hd50000) && (bus_addr <= 24'hd50003);
wire sel_dc0000 = ENABLE_DC0000 && (bus_addr >= 24'hdc0000) && (bus_addr <= 24'hdc0001);
wire sel_c00060 = ENABLE_C00060 && (bus_addr >= 24'hc00060) && (bus_addr <= 24'hc00061);
wire sel_c00020 = ENABLE_C00020 && (bus_addr >= 24'hc00020) && (bus_addr <= 24'hc00021);
wire sel_c00022 = ENABLE_C00022 && (bus_addr >= 24'hc00022) && (bus_addr <= 24'hc00023);
wire sel_c00024 = ENABLE_C00024 && (bus_addr >= 24'hc00024) && (bus_addr <= 24'hc00025);
wire sel_c00030 = ENABLE_C00030 && (bus_addr >= 24'hc00030) && (bus_addr <= 24'hc00031);
wire sel_c00032 = ENABLE_C00032 && (bus_addr >= 24'hc00032) && (bus_addr <= 24'hc00033);
wire sel_c00034 = ENABLE_C00034 && (bus_addr >= 24'hc00034) && (bus_addr <= 24'hc00035);
wire sel_d40000 = ENABLE_D40000 && (bus_addr >= 24'hd40000) && (bus_addr <= 24'hd40001);
wire sel_d40002 = ENABLE_D40002 && (bus_addr >= 24'hd40002) && (bus_addr <= 24'hd40003);
wire sel_d20000 = ENABLE_D20000 && (bus_addr >= 24'hd20000) && (bus_addr <= 24'hd20001);
wire sel_d20002 = ENABLE_D20002 && (bus_addr >= 24'hd20002) && (bus_addr <= 24'hd20003);
wire sel_c0000c = ENABLE_C0000C && (bus_addr >= 24'hc0000c) && (bus_addr <= 24'hc0000d);
wire sel_c00010 = ENABLE_C00010 && (bus_addr >= 24'hc00010) && (bus_addr <= 24'hc00011);
wire sel_e10000 = (bus_addr >= 24'he10000) && (bus_addr <= 24'he10fff);
wire sel_pc060ha_port = ENABLE_PC060HA_PORT && (bus_addr >= 24'hc00000) && (bus_addr <= 24'hc00001);
wire sel_pc060ha_comm = ENABLE_PC060HA_COMM && (bus_addr >= 24'hc00002) && (bus_addr <= 24'hc00003);
wire sel_d00000 = ENABLE_D00000 && (bus_addr >= 24'hd00000) && (bus_addr <= 24'hd0ffff);
wire sel_palette = ENABLE_PALETTE && (bus_addr >= 24'hd80000) && (bus_addr <= 24'hd80fff);
wire sel_fg     = ENABLE_FG     && (bus_addr >= 24'he08000) && (bus_addr <= 24'he0ffff);
// Shared RAM: full 8KB range ($E01000-$E02FFF), 4096 words, 12-bit addr.
// The upper half is used by all sets during POST common-RAM test;
// dariuse Sub also bulk-copies a table into it via (A1)+ indirect.
wire sel_shared = ENABLE_SHARED && (bus_addr >= 24'he01000) && (bus_addr <= 24'he02fff);
wire sel_sprite = ENABLE_SPRITE && (bus_addr >= 24'he00100) && (bus_addr <= 24'he00fff);
wire sel_player_io = ENABLE_PLAYER_IO && (bus_addr >= 24'hc00004) && (bus_addr <= 24'hc0000b);
wire sel_coin_r    = ENABLE_PLAYER_IO && (bus_addr >= 24'hc0000e) && (bus_addr <= 24'hc0000f);
wire sel_nop    = ENABLE_NOP_C00050 && (bus_addr >= 24'hc00050) && (bus_addr <= 24'hc00051);
wire sel_io     = ENABLE_IO     && (bus_addr >= 24'hc00000) && (bus_addr <= 24'hc000ff);
wire sel_video  = ENABLE_VIDEO  && (bus_addr >= 24'hd00000) && (bus_addr <= 24'hdfffff);
wire bus_active = ~bus_asn && (bus_dsn != 2'b11);

// Coin lockout/counter register (MAME: m_coin_word, written at $C00060, read back at $C0000E)
reg [15:0] coin_word;

// TAS detection: read→write transition while ASn stays low
reg prev_bus_rnw;
always @(posedge clk) begin
	if (reset) prev_bus_rnw <= 1'b1;
	else prev_bus_rnw <= bus_rnw;
end
wire tas_write_phase = bus_active && !bus_rnw && prev_bus_rnw;

reg [5:0] txn_state;
reg [15:0] cs_hold;

always @(posedge clk) begin
	if (reset) begin
		// bus_rdata [moved to mux]      <= 16'hffff;
		bus_cs         <= 1'b0;
		bus_busy       <= 1'b0;
		coin_word      <= 16'd0;
		shared_rd      <= 1'b0;
		shared_wr      <= 1'b0;
		shared_addr    <= 12'd0;
		shared_wdata   <= 16'd0;
		sprite_rd      <= 1'b0;
		sprite_wr      <= 1'b0;
		sprite_addr    <= 11'd0;
		sprite_wdata   <= 16'd0;
		fg_rd          <= 1'b0;
		fg_wr          <= 1'b0;
		fg_addr        <= 14'd0;
		fg_wdata       <= 16'd0;
		d000_rd        <= 1'b0;
		d000_wr        <= 1'b0;
		d000_addr      <= 15'd0;
		d000_wdata     <= 16'd0;
		palette_rd     <= 1'b0;
		palette_wr     <= 1'b0;
		palette_addr   <= 11'd0;
		palette_wdata  <= 16'd0;
		ram_rd         <= 1'b0;
		ram_wr         <= 1'b0;
		ram_be         <= 2'b11;
		ram_addr       <= 15'd0;
		ram_wdata      <= 16'd0;
		e100_rd        <= 1'b0;
		e100_wr        <= 1'b0;
		e100_addr      <= 11'd0;
		e100_wdata     <= 16'd0;
		cpua_ctrl_wr   <= 1'b0;
		cpua_ctrl_data <= 8'd0;
		pc060ha_port_wr   <= 1'b0;
		pc060ha_port_data <= 8'd0;
		pc060ha_comm_wr   <= 1'b0;
		pc060ha_comm_data <= 8'd0;
		rom_addr       <= 24'd0;
		rom_req        <= 1'b0;
		cs_vector      <= 16'd0;
		cs_hold        <= 16'd0;
		txn_state      <= TXN_NONE;
	end else begin
		rom_req      <= 1'b0;
		ram_rd       <= 1'b0;
		ram_wr       <= 1'b0;
		e100_rd      <= 1'b0;
		e100_wr      <= 1'b0;
		shared_rd    <= 1'b0;
		shared_wr    <= 1'b0;
		sprite_rd    <= 1'b0;
		sprite_wr    <= 1'b0;
		fg_rd        <= 1'b0;
		fg_wr        <= 1'b0;
		d000_rd      <= 1'b0;
		d000_wr      <= 1'b0;
		palette_rd   <= 1'b0;
		palette_wr   <= 1'b0;
		cpua_ctrl_wr <= 1'b0;
		pc060ha_port_wr <= 1'b0;
		pc060ha_comm_wr <= 1'b0;

		case (txn_state)
			TXN_NONE: begin
				bus_cs    <= 1'b0;
				bus_busy  <= 1'b0;
				cs_vector <= 16'd0;
				cs_hold   <= 16'd0;

				if (bus_active) begin
					bus_cs   <= 1'b1;
					bus_busy <= 1'b1;

					if (sel_rom && bus_rnw) begin
						rom_addr <= bus_addr;
						rom_req  <= 1'b1;
						cs_hold  <= (16'h0001 << CS_ROM);
						txn_state <= TXN_ROM;
					end else if (sel_ram) begin
						ram_addr  <= bus_addr[15:1];
						ram_wdata <= bus_wdata;
						ram_be    <= ~bus_dsn;  // UDSn=0→be[1]=1, LDSn=0→be[0]=1
						cs_hold   <= (16'h0001 << CS_RAM);
						if (bus_rnw) begin
							ram_rd    <= 1'b1;
							txn_state <= TXN_RAM_WAIT;
						end else begin
							ram_wr    <= 1'b1;
							txn_state <= TXN_RAM_WR;
						end
					end else if (sel_e10000) begin
						e100_addr  <= bus_addr[11:1];
						e100_wdata <= bus_wdata;
						cs_hold    <= (16'h0001 << CS_E10000);
						if (bus_rnw) begin
							e100_rd   <= 1'b1;
							txn_state <= TXN_E100_WAIT;
						end else begin
							e100_wr   <= 1'b1;
							txn_state <= TXN_E100_WR;
						end
					end else if (sel_shared) begin
						shared_addr  <= bus_addr[12:1];
						shared_wdata <= bus_wdata;
						cs_hold      <= (16'h0001 << CS_SHARED);
						if (bus_rnw) begin
							shared_rd <= 1'b1;
							txn_state <= TXN_SHARED_WAIT;
						end else begin
							shared_wr <= 1'b1;
							txn_state <= TXN_SHARED_WR;
						end
					end else if (sel_sprite) begin
						sprite_addr  <= {1'b0, bus_addr[11:1]};
						sprite_wdata <= bus_wdata;
						cs_hold      <= (16'h0001 << CS_SPRITE);
						if (bus_rnw) begin
							sprite_rd <= 1'b1;
							txn_state <= TXN_SPRITE_RD;
						end else begin
							sprite_wr <= 1'b1;
							txn_state <= TXN_SPRITE_WR;
						end
					end else if (sel_d00000) begin
						d000_addr  <= bus_addr[15:1];
						d000_wdata <= bus_wdata;
						cs_hold    <= (16'h0001 << CS_VIDEO);
						if (bus_rnw) begin
							d000_rd   <= 1'b1;
							txn_state <= TXN_D000_RD;
						end else begin
							d000_wr   <= 1'b1;
							txn_state <= TXN_D000_WR;
						end
					end else if (sel_palette) begin
						palette_addr  <= bus_addr[11:1];
						palette_wdata <= bus_wdata;
						cs_hold       <= (16'h0001 << CS_VIDEO);
						if (bus_rnw) begin
							palette_rd <= 1'b1;
							txn_state  <= TXN_PALETTE_WAIT;
						end else begin
							palette_wr <= 1'b1;
							txn_state  <= TXN_PALETTE_WR;
						end
					end else if (sel_fg) begin
						fg_addr   <= bus_addr[14:1];
						fg_wdata  <= bus_wdata;
						cs_hold   <= (16'h0001 << CS_VIDEO);
						if (bus_rnw) begin
							fg_rd    <= 1'b1;
							txn_state <= TXN_FG_RD;
						end else begin
							fg_wr    <= 1'b1;
							txn_state <= TXN_FG_WR;
						end
					end else if (sel_ctrl) begin
						cpua_ctrl_data <= ((bus_wdata[15:8] != 8'h00) && (bus_wdata[7:0] == 8'h00)) ? bus_wdata[15:8] : bus_wdata[7:0];
						cpua_ctrl_wr   <= ~bus_rnw;
						// bus_rdata [moved to mux]      <= {8'h00, cpua_ctrl_q};
						cs_hold        <= (16'h0001 << CS_CTRL);
						txn_state      <= TXN_CTRL;
					end else if (sel_wdog) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_WDOG);
						txn_state <= TXN_WDOG;
					end else if (sel_pc080_ctrl) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_PC080_CTRL);
						txn_state <= TXN_PC080_CTRL;
					end else if (sel_dc0000) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_DC0000);
						txn_state <= TXN_DC0000;
					end else if (sel_c00060) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						if (!bus_rnw) coin_word <= bus_wdata;
						cs_hold   <= (16'h0001 << CS_C00060);
						txn_state <= TXN_C00060;
					end else if (sel_c00020) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_C00020);
						txn_state <= TXN_C00020;
					end else if (sel_c00022) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_C00022);
						txn_state <= TXN_C00022;
					end else if (sel_c00024) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_C00024);
						txn_state <= TXN_C00024;
					end else if (sel_c00030) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_C00030);
						txn_state <= TXN_C00030;
					end else if (sel_c00032) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_C00032);
						txn_state <= TXN_C00032;
					end else if (sel_c00034) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_C00034);
						txn_state <= TXN_C00034;
					end else if (sel_d40000) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_D40000);
						txn_state <= TXN_D40000;
					end else if (sel_d40002) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_D40002);
						txn_state <= TXN_D40002;
					end else if (sel_d20000) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_D20000);
						txn_state <= TXN_D20000;
					end else if (sel_d20002) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_D20002);
						txn_state <= TXN_D20002;
					end else if (sel_c0000c) begin
						// bus_rdata [moved to mux] <= 16'hfffc;
						cs_hold   <= (16'h0001 << CS_IO);
						txn_state <= TXN_C0000C;
					end else if (sel_c00010) begin
						// bus_rdata [moved to mux] <= 16'hffff;
						cs_hold   <= (16'h0001 << CS_C00010);
						txn_state <= TXN_C00010;
					end else if (sel_player_io) begin
						// C00004/6=NOP(0), C00008=P1(FF), C0000A=P2(FF)
						// bus_rdata [moved to mux] <= (bus_addr[3:1] >= 3'd2) ? 16'h00ff : 16'h0000;
						cs_hold   <= (16'h0001 << CS_IO);
						txn_state <= TXN_C0000C;
					end else if (sel_coin_r) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_IO);
						txn_state <= TXN_C0000C;
					end else if (sel_pc060ha_port) begin
						// bus_rdata [moved to mux] <= 16'h0001; // bit0=1: slave has read (fake ready)
						cs_hold   <= (16'h0001 << CS_PC060HA);
						if (~bus_rnw)
							pc060ha_port_data <= bus_wdata[7:0];
						txn_state <= TXN_PC060HA;
					end else if (sel_pc060ha_comm) begin
						// bus_rdata [moved to mux] <= {8'h00, pc060ha_comm_rdata};
						cs_hold   <= (16'h0001 << CS_PC060HA_COMM);
						if (~bus_rnw)
							pc060ha_comm_data <= bus_wdata[7:0];
						txn_state <= TXN_PC060HA_COMM;
					end else if (sel_nop) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_NOP);
						txn_state <= TXN_NOP;
					end else if (sel_io) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_IO);
						txn_state <= TXN_IO;
					end else if (sel_video) begin
						// bus_rdata [moved to mux] <= 16'h0000;
						cs_hold   <= (16'h0001 << CS_VIDEO);
						txn_state <= TXN_VIDEO;
					end else begin
						// bus_rdata [moved to mux] <= 16'hffff;
						txn_state <= TXN_UNMAPPED;
					end
				end
			end

			TXN_ROM: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~rom_ready;
				cs_vector <= cs_hold;
				if (rom_ready) begin
					// bus_rdata [moved to mux] <= rom_rdata;
					txn_state <= TXN_DONE;
				end
				// rom_req single pulse sent in TXN_NONE only
			end

			TXN_RAM_WAIT: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b1;
				cs_vector <= cs_hold;
				txn_state <= TXN_RAM_RD;
			end

			TXN_RAM_RD: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b0;
				// bus_rdata [moved to mux] <= ram_rdata;
				cs_vector <= cs_hold;
				txn_state <= TXN_DONE;
			end

			TXN_E100_WAIT: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b1;
				cs_vector <= cs_hold;
				txn_state <= TXN_E100_RD;
			end

			TXN_E100_RD: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b0;
				// bus_rdata [moved to mux] <= e100_rdata;
				cs_vector <= cs_hold;
				txn_state <= TXN_DONE;
			end

			TXN_RAM_WR,
			TXN_E100_WR,
			TXN_CTRL,
			TXN_IO,
			TXN_NOP,
			TXN_WDOG,
			TXN_PC080_CTRL,
			TXN_DC0000,
			TXN_C00060,
			TXN_C00020,
			TXN_C00022,
			TXN_C00024,
			TXN_C00030,
			TXN_C00032,
			TXN_C00034,
			TXN_D40000,
			TXN_D40002,
			TXN_D20000,
			TXN_D20002,
			TXN_C0000C,
			TXN_C00010,
			TXN_PC060HA,
			TXN_PC060HA_COMM,
			TXN_VIDEO,
			TXN_UNMAPPED: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b0;
				cs_vector <= cs_hold;
				if (txn_state == TXN_PC060HA && ~bus_rnw)
					pc060ha_port_wr <= 1'b1;
				if (txn_state == TXN_PC060HA_COMM && ~bus_rnw)
					pc060ha_comm_wr <= 1'b1;
				txn_state <= TXN_DONE;
			end

			TXN_SHARED_WAIT: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b1;
				cs_vector <= cs_hold;
				txn_state <= TXN_SHARED_RD;
			end

			TXN_SHARED_RD: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b0;
				// bus_rdata [moved to mux] <= shared_rdata;
				cs_vector <= cs_hold;
				txn_state <= TXN_DONE;
			end

			TXN_SHARED_WR: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~shared_ready;
				cs_vector <= cs_hold;
				if (shared_ready)
					txn_state <= TXN_DONE;
				else
					shared_wr <= 1'b1;
			end

			TXN_SPRITE_RD: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~sprite_ready;
				cs_vector <= cs_hold;
				if (sprite_ready) begin
					// bus_rdata [moved to mux] <= sprite_rdata;
					txn_state <= TXN_DONE;
				end else begin
					sprite_rd <= 1'b1;
				end
			end

			TXN_SPRITE_WR: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~sprite_ready;
				cs_vector <= cs_hold;
				if (sprite_ready)
					txn_state <= TXN_DONE;
				else
					sprite_wr <= 1'b1;
			end

			TXN_D000_RD: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b0;
				// bus_rdata [moved to mux] <= d000_rdata;
				cs_vector <= cs_hold;
				txn_state <= TXN_DONE;
			end

			TXN_D000_WR: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b0;
				cs_vector <= cs_hold;
				txn_state <= TXN_DONE;
			end

			TXN_PALETTE_WAIT: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b1;
				cs_vector <= cs_hold;
				txn_state <= TXN_PALETTE_RD;
			end

			TXN_PALETTE_RD: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b0;
				// bus_rdata [moved to mux] <= palette_rdata;
				cs_vector <= cs_hold;
				txn_state <= TXN_DONE;
			end

			TXN_PALETTE_WR: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~palette_ready;
				cs_vector <= cs_hold;
				if (palette_ready)
					txn_state <= TXN_DONE;
				else
					palette_wr <= 1'b1;
			end

			TXN_FG_RD: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~fg_ready;
				cs_vector <= cs_hold;
				if (fg_ready) begin
					// bus_rdata [moved to mux] <= fg_rdata;
					txn_state <= TXN_DONE;
				end else begin
					fg_rd <= 1'b1;
				end
			end

			TXN_FG_WR: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~fg_ready;
				cs_vector <= cs_hold;
				if (fg_ready)
					txn_state <= TXN_DONE;
				else
					fg_wr <= 1'b1;
			end

			default: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b0;
				cs_vector <= cs_hold;
				if (!bus_active) begin
					bus_cs    <= 1'b0;
					cs_vector <= 16'd0;
					cs_hold   <= 16'd0;
					txn_state <= TXN_NONE;
				end else if (tas_write_phase) begin
					// TAS read-modify-write: RW changed 1→0 while ASn low
					// Re-enter TXN_NONE to process the write phase
					bus_busy  <= 1'b1;
					txn_state <= TXN_NONE;
				end else begin
					txn_state <= TXN_DONE;
				end
			end
		endcase
	end
end

// Byte enable for all RAM writes — derived from bus_dsn (active low)
assign bus_byte_en = ~bus_dsn;

// Combinational data mux: bus_rdata must be valid in the SAME cycle as DTACK.
// I/O registers (coin, player, DSW) have no wait state, so registered mux
// would delay data by 1 cycle and the CPU would latch stale values.
always @(*) begin
	if (sel_rom)           bus_rdata = rom_rdata;
	else if (sel_ram)      bus_rdata = ram_rdata;
	else if (sel_shared)   bus_rdata = shared_rdata;
	else if (sel_sprite)   bus_rdata = sprite_rdata;
	else if (sel_fg)       bus_rdata = fg_rdata;
	else if (sel_d00000)   bus_rdata = d000_rdata;
	else if (sel_palette)  bus_rdata = palette_rdata;
	else if (sel_e10000)   bus_rdata = e100_rdata;
	else if (sel_pc060ha_port) bus_rdata = {8'h00, pc060ha_comm_rdata};
	else if (sel_c0000c) begin
		// Coin lockout: MAME coin_lockout_w(0, ~data & 0x02) → bit1=0 locks COIN1
		//               MAME coin_lockout_w(1, ~data & 0x04) → bit2=0 locks COIN2
		bus_rdata = {8'h00, system_input[7:2],
		             system_input[1] & coin_word[2],
		             system_input[0] & coin_word[1]};
	end
	else if (sel_c00010)   bus_rdata = dsw_input;
	else if (sel_player_io) begin
		case (bus_addr[3:1])
			3'd2: bus_rdata = 16'hFFFF;            // C00004: NOP (idle)
			3'd3: bus_rdata = 16'hFFFF;            // C00006: NOP (idle)
			3'd4: bus_rdata = {8'hFF, p1_input};   // C00008: P1
			3'd5: bus_rdata = {8'hFF, p2_input};   // C0000A: P2
			default: bus_rdata = 16'hFFFF;
		endcase
	end
	else if (sel_coin_r)   bus_rdata = coin_word;
	else if (sel_pc060ha_comm) bus_rdata = {8'h00, pc060ha_comm_rdata};
	else                   bus_rdata = 16'hFFFF;
end

endmodule
