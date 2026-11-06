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

//============================================================================
// sdrc_darius -- il controller SDRAM di Darius su sdrc.
//
// Quattro porte, con i nomi e l'ordine che usa Template.sv.
// Dentro: quattro sdrc_job (uno per porta) su un sdrc con N_PORTS = 4.
//
// Il protocollo dei clienti NON cambia: req e ack sono a COMMUTAZIONE
// (richiesta pendente = req != ack; servita = ack insegue req), e il dato
// letto e' valido nel ciclo in cui ack raggiunge req, come prima.
//
// Cosa cambia sotto (misurato, non promesso):
//  - le righe restano APERTE, una per ciascuno degli 8 banchi (2 chip x 4; con un chip, N_CHIPS = 1, 4 banchi):
//    se la riga serve di nuovo si salta l'attivazione. Le operazioni restano
//    UNA ALLA VOLTA, come prima: questo non e' un controller a pipeline.
//  - buffer di scrittura: il caricamento delle ROM non blocca piu' i lettori,
//    con controllo di coerenza se una lettura tocca una scrittura in coda;
//  - entrambi i chip della scheda 128 MB, oppure (N_CHIPS = 1, COL_BITS = 9) uno solo, che gira su ogni scheda;
//  - sdrc non genera nessun clock verso la RAM: SDRAM_CLK arriva da un'uscita
//    dedicata della PLL, sfasata, ed e' quello che a 96 MHz rende possibile
//    catturare il dato letto (vedi in fondo).
//
// prio_mode non ha piu' effetto: l'arbitraggio di sdrc e' per anzianita'
// (AGE_MAX) piu' il segnale urgent, che qui non e' usato. La porta resta per
// non toccare Template.sv.
//
// Porte grafiche (02/11): i tre pannelli e gli sprite hanno ciascuno una porta
// di sdrc, senza arbitro davanti, cosi' le loro letture sono in volo insieme e
// sdrc sovrappone i banchi. Ogni lettura a 32 bit e' UN job di 2 parole (prima:
// due accessi da 16 bit in serie). Protocollo verso i renderer:
// req a livello con l'indirizzo in byte, un impulso
// di valid di un ciclo con il dato {parola a, parola a+1}. Indirizzi come in
// sdram_bridge: parola = byte[23:1] + base (pannelli: TILE_BASE 0, sprite:
// SPRITE_BASE $080000), poi {2'b00, [21:0]}.
//============================================================================

module sdrc_darius #(
	parameter int CLK_KHZ      = 96000,   // clk_sys della PLL di Darius
	// clock dalla PLL: ritardo deterministico (PLL + pin) piu' la fase impostata
	parameter int TCKO_SLOW_PS = 8148,    // 4948 di fase + ~3200 di uscita, corner lento
	parameter int TCKO_FAST_PS = 7748,    // 4948 di fase + ~2800 di uscita, corner veloce
	// ingresso SDRAM_DQ (setup/hold dei piedini) della build: i valori di default sono quelli di sdrc
	parameter int TSU_SLOW_PS  = -584,
	parameter int TH_SLOW_PS   = 3737,
	parameter int TSU_FAST_PS  = 248,
	parameter int TH_FAST_PS   = 1716,
	parameter int CMD_STAGE    = 1,       // 1: stadio di comando (serve a 96); 0: un ciclo di latenza in meno
	parameter int AGE_MAX      = 64,      // cicli prima che una richiesta passi davanti alle righe aperte
	// scheda (02/11, vedi l'intestazione di sdrc): 2 chip e colonna 10 = la 128 MB; 1 chip e colonna 9 = gira su
	// tutte (32, 64, 128 MB). Con un chip la 32 MB puo' montare il W9825G6KH: tRRD, tWR, tMRD di due clock.
	parameter int N_CHIPS      = 2,
	parameter int COL_BITS     = 10,
	parameter int T_RRD_PS     = 14000,
	parameter int T_WR_PS      = 14000,
	parameter int T_MRD_PS     = 14000,
	parameter int INIT_REFS    = 2        // AUTO REFRESH dell'accensione: 2 per gli Alliance, 8 per il W9825G6KH
)(
	inout      [15:0] SDRAM_DQ,
	output     [12:0] SDRAM_A,
	output            SDRAM_DQML,
	output            SDRAM_DQMH,
	output      [1:0] SDRAM_BA,
	output            SDRAM_nCS,
	output            SDRAM_nWE,
	output            SDRAM_nRAS,
	output            SDRAM_nCAS,
	output            SDRAM_CLK,
	output            SDRAM_CKE,
	output            ready,

	input             clk_ram,   // clk sfasato dalla PLL (a 48 MHz mezzo periodo, 10417 ps): va al piedino
	input             init,
	input             clk,
	input       [1:0] prio_mode,

	input      [24:1] addr0,
	input             wrl0,
	input             wrh0,
	input      [15:0] din0,
	output     [15:0] dout0,
	input             req0,
	output reg        ack0 = 0,

	input      [24:1] addr1,
	input             wrl1,
	input             wrh1,
	input      [15:0] din1,
	output     [15:0] dout1,
	input             req1,
	output reg        ack1 = 0,

	input      [24:1] addr2,
	input             wrl2,
	input             wrh2,
	input      [15:0] din2,
	output     [15:0] dout2,
	input             req2,
	output reg        ack2 = 0,

	input      [24:1] addr3,
	input             wrl3,
	input             wrh3,
	input      [15:0] din3,
	output     [15:0] dout3,
	input             req3,
	output reg        ack3 = 0,

	// porte grafiche: 0 = pannello sinistro, 1 = centrale, 2 = destro, 3 = sprite
	input       [3:0] gfx_req,     // livello, alto finche' serve il dato
	input      [95:0] gfx_addr,    // 4 x indirizzo in byte (24 bit)
	output    [127:0] gfx_data,    // 4 x 32 bit, {parola a, parola a+1}
	output      [3:0] gfx_valid    // impulso di un ciclo, insieme al dato
);

	localparam int NT       = 4;     // porte a commutazione (download, CPU main, CPU sub, libera)
	localparam int NG       = 4;     // porte grafiche
	localparam int NP       = NT + NG;
	localparam int ADR_BITS = 24;    // indirizzo di parola, come addr0[24:1]
	localparam int LEN_BITS = 4;

	wire rst_n = ~init;

	// prio_mode non usato: sdrc arbitra per anzianita'.
	wire [1:0] unused_prio = prio_mode;

	// --- lato clienti, impacchettato ------------------------------------
	wire [ADR_BITS-1:0] c_adr  [0:NT-1];
	wire         [15:0] c_din  [0:NT-1];
	wire          [1:0] c_bsel [0:NT-1];
	wire                c_req  [0:NT-1];
	wire                c_we   [0:NT-1];
	reg                 c_ack  [0:NT-1];
	reg          [15:0] c_dout [0:NT-1];

	assign c_adr[0] = addr0; assign c_din[0] = din0; assign c_bsel[0] = {wrh0, wrl0};
	assign c_adr[1] = addr1; assign c_din[1] = din1; assign c_bsel[1] = {wrh1, wrl1};
	assign c_adr[2] = addr2; assign c_din[2] = din2; assign c_bsel[2] = {wrh2, wrl2};
	assign c_adr[3] = addr3; assign c_din[3] = din3; assign c_bsel[3] = {wrh3, wrl3};

	assign c_req[0] = req0;  assign c_we[0] = wrl0 | wrh0;
	assign c_req[1] = req1;  assign c_we[1] = wrl1 | wrh1;
	assign c_req[2] = req2;  assign c_we[2] = wrl2 | wrh2;
	assign c_req[3] = req3;  assign c_we[3] = wrl3 | wrh3;

	assign dout0 = c_dout[0];
	assign dout1 = c_dout[1];
	assign dout2 = c_dout[2];
	assign dout3 = c_dout[3];

	always @(*) begin
		ack0 = c_ack[0];
		ack1 = c_ack[1];
		ack2 = c_ack[2];
		ack3 = c_ack[3];
	end

	// --- porte di sdrc, impacchettate -----------------------------------
	wire          [NP-1:0] p_req, p_we, p_ready, p_rvalid;
	wire       [NP*26-1:0] p_addr;
	wire [NP*LEN_BITS-1:0] p_len;
	wire       [NP*32-1:0] p_wdata;
	wire        [NP*4-1:0] p_wbe;
	wire            [15:0] p_rdata;

	genvar g;
	generate
		for (g = 0; g < NT; g = g + 1) begin : gp
			// Da commutazione a impulso: un job parte quando c'e' una
			// richiesta pendente e non se ne sta gia' servendo una. Il
			// gate `serving` garantisce UN job per commutazione di req.
			reg  serving = 1'b0;
			wire pend  = (c_req[g] != c_ack[g]);
			wire busy;
			wire done;
			wire start = pend & ~serving & ~busy;

			wire [15:0] j_rdat;

			always @(posedge clk) begin
				if (init) begin
					serving   <= 1'b0;
					c_ack[g]  <= 1'b0;
					c_dout[g] <= 16'h0;
				end else begin
					if (start) serving <= 1'b1;
					if (done) begin
						serving   <= 1'b0;
						c_ack[g]  <= c_req[g];   // servita
						c_dout[g] <= j_rdat;     // valido al done
					end
				end
			end

			sdrc_job #(
				.ADR_BITS (ADR_BITS),
				.BL_BITS  (1),
				.LEN_BITS (LEN_BITS),
				.FIXED1   (1)            // una parola per accesso, come prima
			) u_job (
				.clk      (clk),
				.rst_n    (rst_n),
				.adr      (c_adr[g]),
				.rd       (start & ~c_we[g]),
				.wr       (start &  c_we[g]),
				.blen     (1'b1),
				.bsel     (c_bsel[g]),
				.wdat     (c_din[g]),
				.rdat     (j_rdat),
				.rval     (),
				.bnum     (),
				.done     (done),
				.busy     (busy),

				.p_req    (p_req[g]),
				.p_we     (p_we[g]),
				.p_addr   (p_addr[g*26 +: 26]),
				.p_len    (p_len[g*LEN_BITS +: LEN_BITS]),
				.p_wdata  (p_wdata[g*32 +: 32]),
				.p_wbe    (p_wbe[g*4 +: 4]),
				.p_ready  (p_ready[g]),
				.p_rdata  (p_rdata),
				.p_rvalid (p_rvalid[g])
			);
		end

		// --- porte grafiche: una per cliente, un job di 2 parole per lettura ---
		for (g = 0; g < NG; g = g + 1) begin : gg
			localparam int        P    = NT + g;                              // porta di sdrc
			localparam [23:0]     BASE = (g == 3) ? 24'h080000 : 24'h000000;  // SPRITE_BASE / TILE_BASE di sdram_bridge

			reg         req_q = 1'b0;      // req al ciclo prima: il fronte di salita apre la lettura
			reg         go    = 1'b0;      // impulso rd verso il job, il ciclo dopo il fronte
			reg  [23:0] adr   = 24'd0;     // indirizzo di parola della lettura (il job lo prende al via)
			reg  [15:0] w_hi  = 16'd0;     // parola 0 (indirizzo a)
			reg  [15:0] w_lo  = 16'd0;     // parola 1 (indirizzo a+1)
			reg  [31:0] dat   = 32'd0;
			reg         val   = 1'b0;

			wire        j_rval, j_done, j_busy;
			wire [15:0] j_rdat;
			wire  [0:0] j_bnum;
			wire [23:0] word = {1'b0, gfx_addr[g*24+1 +: 23]} + BASE;     // come gfx_addr di sdram_bridge

			always @(posedge clk) begin
				if (init) begin
					req_q <= 1'b0;
					go    <= 1'b0;
					val   <= 1'b0;
				end else begin
					req_q <= gfx_req[g];
					go    <= 1'b0;
					val   <= 1'b0;
					if (gfx_req[g] & ~req_q) begin
						adr <= {2'b00, word[21:0]};   // banco 0 forzato, come sdram_bridge
						go  <= 1'b1;
					end
					if (j_rval) begin
						if (j_bnum == 1'b0) w_hi <= j_rdat;
						else                w_lo <= j_rdat;
					end
					if (j_done) begin              // il ciclo dopo l'ultima parola
						dat <= {w_hi, w_lo};
						val <= 1'b1;
					end
				end
			end

			assign gfx_data[g*32 +: 32] = dat;
			assign gfx_valid[g]         = val;

			sdrc_job #(
				.ADR_BITS (ADR_BITS),
				.BL_BITS  (1),
				.LEN_BITS (LEN_BITS),
				.FIXED1   (0),
				.HAS_RD   (1),
				.HAS_WR   (0)              // sola lettura (WR_PORTS di sdrc uguale)
			) u_job (
				.clk      (clk),
				.rst_n    (rst_n),
				.adr      (adr),
				.rd       (go),
				.wr       (1'b0),
				.blen     (1'b0),          // 0 = 2^BL_BITS = 2 parole
				.bsel     (2'b00),
				.wdat     (16'h0),
				.rdat     (j_rdat),
				.rval     (j_rval),
				.bnum     (j_bnum),
				.done     (j_done),
				.busy     (j_busy),

				.p_req    (p_req[P]),
				.p_we     (p_we[P]),
				.p_addr   (p_addr[P*26 +: 26]),
				.p_len    (p_len[P*LEN_BITS +: LEN_BITS]),
				.p_wdata  (p_wdata[P*32 +: 32]),
				.p_wbe    (p_wbe[P*4 +: 4]),
				.p_ready  (p_ready[P]),
				.p_rdata  (p_rdata),
				.p_rvalid (p_rvalid[P])
			);
		end
	endgenerate

	// --- il controller ---------------------------------------------------
	sdrc #(
		.CLK_KHZ  (CLK_KHZ),
		.N_PORTS  (NP),
		.LEN_BITS (LEN_BITS),
		.MAP      (1),
		.WR_PORTS ({{NG{1'b0}}, {NT{1'b1}}}),   // le porte grafiche non scrivono
		.CMD_STAGE(CMD_STAGE),
		.AGE_MAX  (AGE_MAX),
		.N_CHIPS  (N_CHIPS),
		.COL_BITS (COL_BITS),
		.T_RRD_PS (T_RRD_PS),
		.T_WR_PS  (T_WR_PS),
		.T_MRD_PS (T_MRD_PS),
		.INIT_REFS(INIT_REFS),
		// clock dalla PLL: ritardo deterministico (PLL + pin) piu' la fase
		// impostata. Sostituiscono i valori del percorso d'uscita, che a
		// 96 MHz lasciavano la finestra di cattura vuota.
		.TCKO_SLOW_PS (TCKO_SLOW_PS),
		.TCKO_FAST_PS (TCKO_FAST_PS),
		.TSU_SLOW_PS  (TSU_SLOW_PS),
		.TH_SLOW_PS   (TH_SLOW_PS),
		.TSU_FAST_PS  (TSU_FAST_PS),
		.TH_FAST_PS   (TH_FAST_PS)
	) u_sdrc (
		.clk         (clk),
		.rst_n       (rst_n),
		.ready       (ready),

		.req         (p_req),
		.we          (p_we),
		.urgent      ({NP{1'b0}}),
		.addr        (p_addr),
		.len         (p_len),
		.wdata       (p_wdata),
		.wbe         (p_wbe),
		.port_ready  (p_ready),
		.rdata       (p_rdata),
		.rvalid      (p_rvalid),

		.sdram_ncs   (SDRAM_nCS),
		.sdram_nras  (SDRAM_nRAS),
		.sdram_ncas  (SDRAM_nCAS),
		.sdram_nwe   (SDRAM_nWE),
		.sdram_ba    (SDRAM_BA),
		.sdram_a     (SDRAM_A),
		.sdram_dqm   ({SDRAM_DQMH, SDRAM_DQML}),
		.sdram_dq    (SDRAM_DQ)
	);

	// --- pin che sdrc non genera ------------------------------------------
	// SDRAM_CLK arriva da un'uscita dedicata della PLL, sfasata di 5000 ps
	// (4948: valore legale della PLL piu' vicino a mezzo periodo, e quello con
// il margine migliore). Rispetto a ~clk portato fuori da un
	// percorso d'uscita il ritardo e' deterministico invece di variare di
	// 5,5 ns fra i corner: e' quello che riapre la finestra di cattura a
	// 96 MHz e la fa cadere su un fronte di SALITA (CAP_H = 6, margine
	// 1576 ps), quindi senza usare il registro su negedge di sdrc.
	assign SDRAM_CLK = clk_ram;
	assign SDRAM_CKE = 1'b1;

endmodule
