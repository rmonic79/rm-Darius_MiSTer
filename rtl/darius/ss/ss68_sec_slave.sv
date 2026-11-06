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

// ss68_sec_slave.sv — slave del bus del savestate (ssbus) per la sezione del savestate esterno dei 68000 (m68k_ss_seq SS7):
// N_WORDS parole da 16 bit, lette e scritte IN ORDINE dallo stream (memory_stream: una parola per richiesta, indirizzi
// 0..count-1 in ordine, una volta ciascuno). Stesso protocollo delle funzioni dell'interfaccia (setup, read_response,
// write_ack), scritto per esteso: ack un clock dopo ogni richiesta selezionata; dato della lettura preso al primo clock e
// tenuto per tutta la richiesta; risposta alla query = {indice, larghezza 16 bit, N_WORDS}.
// Verso il modulo tutto da flop, un clock dopo il primo clock della richiesta: lettura -> impulso `rd` (la catena avanza,
// il dato e' gia' in dq); scrittura -> impulso `wr` con il dato del bus registrato (entra nella catena). La prossima
// richiesta arriva dopo piu' clock (ack, discesa della richiesta, ack basso): la catena e' gia' a posto.
module ss68_sec_slave #(parameter SS_IDX = -1, parameter N_WORDS = 4)(
    input              clk,
    ssbus_if.slave     ssbus,
    input       [15:0] word,
    output             rd,
    output             wr,
    output      [15:0] wdata
);
reg        first_done = 1'b0;   // la richiesta in corso ha gia' avuto il primo clock
reg        ack_r = 1'b0, qresp = 1'b0, rd_q = 1'b0, wr_q = 1'b0;
reg [15:0] dq = 16'd0, wd_q = 16'd0;
wire sel    = (ssbus.select == 8'(SS_IDX));
wire acc    = sel & ~ssbus.query & (ssbus.read | ssbus.write);
wire rd_now = acc & ssbus.read & ~first_done;
wire wr_now = acc & ~ssbus.read & ssbus.write & ~first_done;
assign rd    = rd_q;
assign wr    = wr_q;
assign wdata = wd_q;

always @(posedge clk) begin
    first_done <= acc;
    ack_r      <= sel & (ssbus.query | ssbus.read | ssbus.write);
    rd_q       <= rd_now;
    wr_q       <= wr_now;
    wd_q       <= ssbus.data[15:0];
    if (sel & ssbus.query) begin qresp <= 1'b1; dq <= 16'(N_WORDS); end
    else if (rd_now) begin qresp <= 1'b0; dq <= word; end
end
assign ssbus.ack      = ack_r;
assign ssbus.data_out = {(qresp ? 8'(SS_IDX) : 8'd0), 22'd0, 1'b0, qresp, 16'd0, dq};

endmodule
