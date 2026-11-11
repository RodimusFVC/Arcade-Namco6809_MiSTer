//============================================================================
//
//  Namco 62XX (CUS62): a Fujitsu MB88 (MAME: MB8843) in a 28-pin package with Namco's program in its mask ROM.
//  Used by Gaplus. Drives an MB88 on the mb88_* pool; the 2K mask ROM (62xx.bin) is read through rom_a / rom_d
//  from the core's ROM block.
//  Copyright (C) 2026 Rodimus
//  SPDX-License-Identifier: BSD-3-Clause
//  Pinout from the Gaplus schematic (gaplus-1.pdf, logic P.C. sheet 3 of 3); MAME src/mame/namco/namco62.cpp
//  (copyright-holders: Philip Bennett) identifies the part but leaves its ports unconnected.
//
//  Pins: R0-R3 12/13/15/16, R4-R6 17-19, R7 20, R8/R9 21/22, R10/_IRQ 23 (one pin), K0-K3 24-27, X 2, RESET 3.
//  R0-R10 are bonded: each reads as its own output latch AND the external drive (r_ext, 1 = released).
//  _IRQ takes the external drive on pin 23 (r_ext[10]). R11-R15, TC and SI are not bonded: R11-R15 read back
//  their latch, TC / SI are inactive.
//
//============================================================================

module namco_62xx
(
    input  chip_pool_pkg::namco_62xx_i_t i,
    output chip_pool_pkg::namco_62xx_o_t o,
    output logic                  [10:0] rom_a,
    input  logic                   [7:0] rom_d,
    output chip_pool_pkg::mb88_i_t       mb88_i,
    input  chip_pool_pkg::mb88_o_t       mb88_o
);

assign mb88_i.ena     = i.ena;
assign mb88_i.reset_n = i.reset_n;
assign mb88_i.k       = i.k;
assign mb88_i.r_in    = {mb88_o.r_out[15:11], mb88_o.r_out[10:0] & i.r_ext};
assign mb88_i.irq_n   = i.r_ext[10];
assign mb88_i.tc_n    = 1'b1;
assign mb88_i.si_n    = 1'b1;
assign mb88_i.rom_d   = rom_d;

assign rom_a   = mb88_o.rom_a;
assign o.r_out = mb88_o.r_out[10:0];
assign o.o     = mb88_o.o;
assign o.o_wr  = mb88_o.o_wr;

endmodule
