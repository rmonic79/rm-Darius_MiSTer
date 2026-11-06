/*  This file is part of Darius_MiSTer.
    GPL-3.
    Original author: Martin Donlon (wickerwaka) — Arcade-TaitoF2 savestate system.
    Modified/adapted by: Umberto Parisi (rmonic79)
*/

//============================================================================
//  Savestate — ddr_if interface
//  Portato da ddram.sv di Arcade-TaitoF2 (Martin Donlon).
//  ddr_if mappa 1:1 sui segnali DDRAM_* MiSTer.
//  NB: ddr_mux dell'originale RIMOSSO — nel core il mux DDR è fatto a mano (ss_ddr_gate.sv)
//  nel top (gated su ss_busy). Qui serve solo l'interface ddr_if.
//============================================================================

interface ddr_if;
    logic        acquire;

    logic [31:0] addr;
    logic [63:0] wdata;
    logic [63:0] rdata;
    logic        read;
    logic        write;
    logic  [7:0] burstcnt;
    logic  [7:0] byteenable;
    logic        busy;
    logic        rdata_ready;

    modport to_host(
        output addr, wdata, read, write, burstcnt, byteenable, acquire,
        input rdata, busy, rdata_ready
    );

    modport from_host(
        output rdata, busy, rdata_ready,
        input addr, wdata, read, write, burstcnt, byteenable, acquire
    );


endinterface


