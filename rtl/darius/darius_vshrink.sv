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

// darius_vshrink — CRT Shrink: compressione verticale senza memoria (dal darius2_vshrink di Darius 2 Rework, con il
// contratto dei renderer di Darius 1).
//
// NON e' uno scaler: non sposta nessuna riga nel tempo e non ne conserva nessuna. Invece di chiedere ai renderer le 224
// righe sorgente su 224 righe di display, si usa una finestra di N righe centrata nell'attivo e a ognuna si assegna una
// riga sorgente con passo 224/N in formato 8.8. L'unico stato e' l'accumulatore y_acc.
//   vshrink 0 = Off (224 righe)  1 = 1/2 (112)  2 = 1/3 (75)  3 = 1/4 (56)
// PASSI 512 / 764 / 1024 e finestre 112 / 75 / 56: quelli di Darius 2, scelti dall'utente guardandoli a schermo
// (512 e 1024 sono rapporti interi esatti e decimano in modo uniforme). Non si toccano senza un suo ordine.
//
// CONTRATTO CON I RENDERER DI DARIUS 1 (diverso da Darius 2, dove il chip mostra due righe dopo quella chiesta):
//  - render_y sulla riga di display r e' la riga sorgente che quella riga MOSTRA. I renderer, a inizio riga,
//    mostrano la riga preparata se coincide con render_y (pannelli: darius_panel_renderer.sv, swap su
//    prep_line_y == render_y; FG: darius_fg_renderer.sv idem) o la mostrano comunque (sprite: ping-pong a ogni
//    new_line), e preparano durante la riga quella successiva: render_y_next.
//  - render_y_next = la riga sorgente della riga di display successiva; 224 dopo l'ultima riga della finestra (come
//    vc+1 = 224 dopo la riga 223): i pannelli e gli sprite la portano a 0 (riga 0 del quadro dopo), il FG resta
//    fermo e prepara la riga 0 all'inizio del VBlank, come oggi.
//  - Fuori finestra render_y = 300: >= 224 tiene i renderer fuori dall'attivo (nessun inizio di riga, VBlank per lo
//    sprite e il FG).
//  - Con vshrink == 0: render_y = vc e render_y_next = vc + 1, i valori che i renderer usavano prima, bit per bit.
// La riga NATURALE (vc) non passa di qui: IRQ4, savestate e follow-cam la prendono dal compositore (render_y_nat).
//
// FASE: y_acc si aggiorna su pxl_en && line_end, lo STESSO fronte in cui hc torna a 0 e vc incrementa nel
// compositore: i confronti usano la vc pre-incremento (la riga che finisce) e la riga dopo (vc+1). line_end deve
// essere la combinatoria (hc == H_TOTAL-1), mai un registro, e pxl_en lo stesso enable del compositore.
// in_win torna al compositore (VBlank, active, render_x): combinatorio da vc, come il VBlank di prima.

module darius_vshrink
(
	input         clk,
	input         reset,
	input         pxl_en,        // enable di pixel del compositore
	input         line_end,      // COMBINATORIO: (hc == H_TOTAL-1), mai registrato
	input   [8:0] vc,            // contatore di riga del compositore
	input   [1:0] vshrink,       // 0=Off 1=1/2 2=1/3 3=1/4
	input         fld,           // campo dispari dell'interlacciato (0 senza interlacciato): finestra da mezzo passo
	input         fld_next,      // campo del quadro dopo (0 senza interlacciato)

	output  [8:0] render_y,      // riga sorgente MOSTRATA sulla riga vc
	output  [8:0] render_y_next, // riga sorgente da preparare per la riga vc+1 (224: nessuna in questo quadro)
	output        in_win,        // attivo verticale di display
	output  [8:0] render_y_first // prima riga sorgente del quadro dopo, preparata nel vblank (0 senza interlacciato)
);

localparam V_ACTIVE = 9'd224;

wire shrink_on = (vshrink != 2'd0);

// ── finestra compressa: N righe centrate nell'attivo, passo sorgente 224/N in 8.8 ──
wire [8:0]  win_n   = (vshrink == 2'd1) ? 9'd112 :
                      (vshrink == 2'd2) ? 9'd75  :
                      (vshrink == 2'd3) ? 9'd56  : V_ACTIVE;
wire [15:0] win_st  = (vshrink == 2'd1) ? 16'd512 :
                      (vshrink == 2'd2) ? 16'd764 :
                      (vshrink == 2'd3) ? 16'd1024 : 16'd256;
wire [8:0]  win_top = (V_ACTIVE - win_n) >> 1;
wire [8:0]  win_end = win_top + win_n;                     // prima riga dopo la finestra
wire [8:0]  vc_n    = vc + 9'd1;                           // riga successiva (262 a fine quadro: fuori)
assign      in_win  = (vc >= win_top) && (vc < win_end);
wire        in_win_n = (vc_n >= win_top) && (vc_n < win_end);
wire        last    = (vc == win_end - 9'd1);

// y_acc = (riga - win_top) * passo sulla riga di display in finestra; zero fuori, a ogni riga (cambiando rapporto
// dall'OSD a meta' quadro si riparte puliti alla finestra dopo).
reg [15:0] y_acc;
always @(posedge clk) begin
	if (reset) y_acc <= 16'd0;
	else if (pxl_en && line_end) begin
		if (in_win_n && vc_n != win_top) y_acc <= y_acc + win_st;   // riga successiva in finestra
		else                             y_acc <= fld ? {1'b0, win_st[15:1]} : 16'd0;   // prima riga della finestra, o fuori;
		                                                            // campo dispari: da mezzo passo
	end
end
wire [15:0] y_acc_n = y_acc + win_st;
wire [8:0]  y_src   = {1'b0, y_acc[15:8]};
wire [8:0]  y_nxt   = {1'b0, y_acc_n[15:8]};

// campo dispari del quadro dopo: la sua prima riga e' mezzo passo (1/2 e 1/3: riga 1, 1/4: riga 2)
assign render_y_first = (shrink_on && fld_next) ? {2'b00, win_st[15:9]} : 9'd0;
assign render_y      = !shrink_on ? vc       :
                       in_win     ? y_src    : 9'd300;
assign render_y_next = !shrink_on ? vc_n     :
                       (in_win && !last) ? y_nxt : V_ACTIVE;

endmodule
