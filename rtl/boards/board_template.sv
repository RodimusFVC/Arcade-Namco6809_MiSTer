//============================================================================
//
//  board_template.sv - starting point for a new Namco6809 board (not compiled: not in files.qip).
//  Copyright (C) 2026 Rodimus
//
//  Boards never instantiate a CPU, sound chip, ROM store or board RAM. Drive the pool ports. Copy this file to start
//  a board: rtl/boards/<board>/<board>_board.sv, then replace the board's tie-off in rtl/namco6809_dispatcher.sv
//  (Boards section) with its instance. Pool slots, ROM windows and the RAM block map: the dispatcher's pool sections.
//  A private RAM or chip that cannot be shared needs // POOL-EXCEPTION: <reason> on its line.
//
//============================================================================

module board_template #(parameter int RAM_BLOCKS = 6)
(
    input  logic        clk,                    // 49.152 MHz
    input  logic        reset,
    input  logic        pause,
    input  logic [4:0][16:0] rom_ofs,           // packed-store offset per region
    input  logic        crt_flip,
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    input  logic  [7:0] in_coins,
    input  logic  [7:0] in_p1,
    input  logic  [7:0] in_p2,
    input  logic  [7:0] in_buttons,
    input  logic  [7:0] dsw0,
    input  logic  [7:0] dsw1,
    input  logic  [7:0] dsw2,

    output logic        ce_pix,
    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,
    output logic signed [15:0] audio,

    // CPU / sound chip pool
    output chip_pool_pkg::m6809r_i_t  m6809_0_i,
    input  chip_pool_pkg::m6809r_o_t  m6809_0_o,
    output chip_pool_pkg::m6809r_i_t  m6809_1_i,
    input  chip_pool_pkg::m6809r_o_t  m6809_1_o,
    output chip_pool_pkg::m6809r_i_t  m6809_2_i,
    input  chip_pool_pkg::m6809r_o_t  m6809_2_o,
    output chip_pool_pkg::wsg15_i_t   wsg15_0_i,
    output logic                      wsg15_0_smp,
    output chip_pool_pkg::namcoio_i_t namcoio_0_i,
    input  chip_pool_pkg::namcoio_o_t namcoio_0_o,
    output chip_pool_pkg::namcoio_i_t namcoio_1_i,
    input  chip_pool_pkg::namcoio_o_t namcoio_1_o,
    output chip_pool_pkg::namco_62xx_i_t n62_0_i,
    input  chip_pool_pkg::namco_62xx_o_t n62_0_o,

    output logic        mcu_rst,                // mcu63 (HD63701)
    output logic        mcu_cen,
    output logic        mcu_irq,
    output logic  [7:0] mcu_xdin,
    output logic  [7:0] mcu_p1_din,
    input  logic [15:0] mcu_addr,
    input  logic  [7:0] mcu_dout,
    input  logic        mcu_wr,
    input  logic        mcu_xcs,
    input  logic  [7:0] mcu_p1_dout,

    output logic        c30_cen,                // c30 (CUS30)
    output logic        c30_bsel,
    output logic        c30_bcs,
    output logic        c30_brnw,
    output logic  [9:0] c30_baddr,
    output logic  [7:0] c30_bdout,
    output logic        c30_scs,
    output logic        c30_srnw,
    output logic [15:0] c30_saddr,
    output logic  [7:0] c30_sdout,
    input  logic  [7:0] c30_xdin,

    // ROM blocks
    output logic [16:0] rom_a_addr,             // packed store, port A (CPU side)
    input  logic  [7:0] rom_a_q,
    output logic [16:0] rom_b_addr,             // packed store, port B (video side)
    input  logic  [7:0] rom_b_q,
    output logic [10:0] prom_a_addr,            // colour PROM window
    input  logic  [7:0] prom_a_q,
    output logic [10:0] prom_b_addr,
    input  logic  [7:0] prom_b_q,
    input  logic  [3:0] wave_q,                 // 15XX waveform PROM at wsg15_0_o.wave_a
    input  logic  [7:0] mcu_rom_q,              // MCU ROM block (n62_0 rom_a / mcu_addr)

    // RAM pool
    output ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] pr_i,
    input  ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pr_o,
    output logic  [9:0] lbuf_aa,                // sprite line buffer (9 bits)
    output logic  [8:0] lbuf_da,
    output logic        lbuf_wa,
    output logic  [9:0] lbuf_ab,
    input  logic  [8:0] lbuf_qb,

    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write
);

endmodule
