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

// darius_subcpu_map — Memory map del Sub 68000.
// Decode e dispatch bus della CPU secondaria verso ROM, shared RAM,
// sprite RAM, FG RAM, palette e I/O.

module darius_subcpu_map
#(
	parameter ENABLE_NOP_C00050 = 1'b0,
	parameter ENABLE_SHARED = 1'b0,
	parameter ENABLE_SPRITE = 1'b0,
	parameter ENABLE_FG     = 1'b0,
	parameter ENABLE_PALETTE = 1'b0,
	parameter ENABLE_IO     = 1'b0
)
(
	input  wire        clk,
	input  wire        reset,
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
	output reg  [14:0] ram_addr,
	output reg  [15:0] ram_wdata,
	input  wire        palette_ready,
	output reg         palette_wr,
	output reg  [10:0] palette_addr,
	output reg  [15:0] palette_wdata,
	output reg  [23:0] rom_addr,
	output reg         rom_req,
	output reg  [15:0] cs_vector
);

localparam CS_ROM    = 0;
localparam CS_RAM    = 1;
localparam CS_SHARED = 2;
localparam CS_SPRITE = 3;
localparam CS_IO     = 4;
localparam CS_NOP    = 5;
localparam CS_PALETTE = 6;

localparam TXN_NONE      = 4'd0;
localparam TXN_ROM       = 4'd1;
localparam TXN_RAM_WAIT  = 4'd2;
localparam TXN_RAM_RD    = 4'd3;
localparam TXN_RAM_WR    = 4'd4;
localparam TXN_SHARED_WAIT = 5'd5;
localparam TXN_SHARED_RD = 5'd6;
localparam TXN_SHARED_WR = 5'd7;
localparam TXN_SPRITE_RD = 5'd8;
localparam TXN_SPRITE_WR = 5'd9;
localparam TXN_FG_RD     = 5'd10;
localparam TXN_FG_WR     = 5'd11;
localparam TXN_IO        = 5'd12;
localparam TXN_NOP       = 5'd13;
localparam TXN_PALETTE_WR = 5'd14;
localparam TXN_UNMAPPED  = 5'd15;
localparam TXN_DONE      = 5'd16;

wire sel_rom    = (bus_addr >= 24'h000000) && (bus_addr <= 24'h03ffff);
	wire sel_ram    = (bus_addr >= 24'h040000) && (bus_addr <= 24'h04ffff);
// Shared RAM: full 8KB range ($E01000-$E02FFF), 4096 words, 12-bit addr.
wire sel_shared = ENABLE_SHARED && (bus_addr >= 24'he01000) && (bus_addr <= 24'he02fff);
wire sel_sprite = ENABLE_SPRITE && (bus_addr >= 24'he00100) && (bus_addr <= 24'he00fff);
wire sel_fg     = ENABLE_FG     && (bus_addr >= 24'he08000) && (bus_addr <= 24'he0ffff);
wire sel_palette = ENABLE_PALETTE && (bus_addr >= 24'hd80000) && (bus_addr <= 24'hd80fff);
wire sel_nop    = ENABLE_NOP_C00050 && (bus_addr >= 24'hc00050) && (bus_addr <= 24'hc00051);
wire sel_io     = ENABLE_IO     && (bus_addr >= 24'he00000) && (bus_addr <= 24'he00fff);
wire bus_active = ~bus_asn && (bus_dsn != 2'b11);

// TAS detection: read→write transition while ASn stays low
reg prev_bus_rnw;
always @(posedge clk) begin
	if (reset) prev_bus_rnw <= 1'b1;
	else prev_bus_rnw <= bus_rnw;
end
wire tas_write_phase = bus_active && !bus_rnw && prev_bus_rnw;

reg [4:0] txn_state;
reg [15:0] cs_hold;

always @(posedge clk) begin
	if (reset) begin
		bus_cs       <= 1'b0;
		bus_busy     <= 1'b0;
		shared_rd    <= 1'b0;
		shared_wr    <= 1'b0;
		shared_addr  <= 12'd0;
		shared_wdata <= 16'd0;
		sprite_rd    <= 1'b0;
		sprite_wr    <= 1'b0;
		sprite_addr  <= 11'd0;
		sprite_wdata <= 16'd0;
		fg_rd        <= 1'b0;
		fg_wr        <= 1'b0;
		fg_addr      <= 14'd0;
		fg_wdata     <= 16'd0;
		palette_wr   <= 1'b0;
		palette_addr <= 11'd0;
		palette_wdata <= 16'd0;
		ram_rd       <= 1'b0;
		ram_wr       <= 1'b0;
		ram_addr     <= 11'd0;
		ram_wdata    <= 16'd0;
		rom_addr     <= 24'd0;
		rom_req      <= 1'b0;
		cs_vector    <= 16'd0;
		cs_hold      <= 16'd0;
		txn_state    <= TXN_NONE;
	end else begin
		rom_req   <= 1'b0;
		ram_rd    <= 1'b0;
		ram_wr    <= 1'b0;
		shared_rd <= 1'b0;
		shared_wr <= 1'b0;
		sprite_rd <= 1'b0;
		sprite_wr <= 1'b0;
		fg_rd     <= 1'b0;
		fg_wr     <= 1'b0;
		palette_wr <= 1'b0;

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
						cs_hold   <= (16'h0001 << CS_RAM);
					if (bus_rnw) begin
							ram_rd    <= 1'b1;
							txn_state <= TXN_RAM_WAIT;
						end else begin
							ram_wr    <= 1'b1;
							txn_state <= TXN_RAM_WR;
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
					end else if (sel_fg) begin
						fg_addr    <= bus_addr[14:1];
						fg_wdata   <= bus_wdata;
						cs_hold    <= (16'h0001 << CS_SHARED);
						if (bus_rnw) begin
							fg_rd <= 1'b1;
							txn_state <= TXN_FG_RD;
						end else begin
							fg_wr <= 1'b1;
							txn_state <= TXN_FG_WR;
						end
					end else if (sel_palette && ~bus_rnw) begin
						palette_addr  <= bus_addr[11:1];
						palette_wdata <= bus_wdata;
						palette_wr    <= 1'b1;
						cs_hold       <= (16'h0001 << CS_PALETTE);
						txn_state     <= TXN_PALETTE_WR;
					end else if (sel_nop) begin
						cs_hold   <= (16'h0001 << CS_NOP);
						txn_state <= TXN_NOP;
					end else if (sel_io) begin
						cs_hold   <= (16'h0001 << CS_IO);
						txn_state <= TXN_IO;
					end else begin
						txn_state <= TXN_UNMAPPED;
					end
				end
			end

			TXN_ROM: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~rom_ready;
				cs_vector <= cs_hold;
				if (rom_ready) begin
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
				cs_vector <= cs_hold;
				txn_state <= TXN_DONE;
			end

			TXN_RAM_WR,
			TXN_NOP,
			TXN_IO,
			TXN_UNMAPPED: begin
				bus_cs    <= 1'b1;
				bus_busy  <= 1'b0;
				cs_vector <= cs_hold;
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

			TXN_FG_RD: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~fg_ready;
				cs_vector <= cs_hold;
				if (fg_ready) begin
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

			TXN_PALETTE_WR: begin
				bus_cs    <= 1'b1;
				bus_busy  <= ~palette_ready;
				cs_vector <= cs_hold;
				if (palette_ready)
					txn_state <= TXN_DONE;
				else
					palette_wr <= 1'b1;
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
					bus_busy  <= 1'b1;
					txn_state <= TXN_NONE;
				end else begin
					txn_state <= TXN_DONE;
				end
			end
		endcase
	end
end

// Registered data mux — same pattern as maincpu_map
// Runs every clock, reflects current peripheral data
always @(posedge clk) begin
	if (sel_rom)           bus_rdata <= rom_rdata;
	else if (sel_ram)      bus_rdata <= ram_rdata;
	else if (sel_shared)   bus_rdata <= shared_rdata;
	else if (sel_sprite)   bus_rdata <= sprite_rdata;
	else if (sel_fg)       bus_rdata <= fg_rdata;
	else                   bus_rdata <= 16'hFFFF;
end

endmodule
