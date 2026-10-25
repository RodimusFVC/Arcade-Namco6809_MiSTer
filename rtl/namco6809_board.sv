//============================================================================
//
//  Namco6809 — board top (dispatcher). SKELETON: pools only, no board logic yet (setup 2026-10-24).
//  Copyright (C) 2026 Rodimus
//
//  One rbf for the Namco 6809 / 15XX family (MAME namco/mappy.cpp + gaplus.cpp). Variant (MRA index 1 byte 0):
//    0  Super Pac-Man board  (superpac, superpacm, pacnpal, pacnpal2, pacnchmp, grobda, grobda2, grobda3)
//    1  Phozon board         (phozon, phozons)                       third 6809, 8x8 sprites, RGB PROMs
//    2  Mappy board          (mappy, mappyj, todruaga*, digdug2*, motos)   17XX scroll, 4bpp sprites, 99XX DAC
//    3  Gaplus board         (gaplus*, galaga3*)                      3x 6809, CUS26 stars, 62XX (MB8843)
//  The board not selected is held in reset. Boards come later as rtl/boards/<board>_board.sv and drive the pools
//  below through bus ports (rtl/chip_pool_pkg.sv); they never instance their own CPU / WSG / ROM / RAM.
//
//  ioctl index 0 (linear, variant-free load decode: index 1 arrives after the ROMs):
//    0x00000-0x17FFF  packed ROM store, 12 x 8K banks: each set's maincpu / sub / sub2 / tiles / sprites regions
//                     back to back, each 256-byte aligned; per-region offsets come from index 1 bytes 72-81
//                     (rom_ofs; regions 0 maincpu, 1 sub, 2 sub2, 3 tiles, 4 sprites; MAME ROM_FILLs not stored)
//    0x18000-0x187FF  colour PROMs (MAME "proms" region as dumped; decoded on read per variant)
//    0x18800-0x188FF  15XX waveform PROM (MAME "namco")
//    0x19000-0x197FF  62XX MCU ROM (namco62.zip, Gaplus only)
//
//============================================================================

module namco6809_board
(
    input  logic        clk,            // 49.152 MHz
    input  logic        reset,
    input  logic        pause,
    input  logic  [7:0] variant,
    input  logic [15:0][7:0] game_cfg,  // index 1 bytes 0-15 (byte 0 variant, 2 I/O kinds, 3 per-set options)
    input  logic [4:0][16:0] rom_ofs,   // index 1 bytes 72-81: packed-store offset per region (see Shared ROM blocks)
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

    input  logic [24:0] ioctl_addr,
    input  logic  [7:0] ioctl_dout,
    input  logic        ioctl_wr0,

    output logic        ce_pix,
    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,

    output logic signed [15:0] audio,

    input  logic        hs_access,
    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write
);

/* verilator lint_off UNUSED */
// Skeleton: the board inputs and pool outputs below are consumed by the boards (rtl/boards/, not written yet)
wire is_sp = variant == 8'd0;
wire is_ph = variant == 8'd1;
wire is_mp = variant == 8'd2;
wire is_gp = variant == 8'd3;
/* verilator lint_on UNUSED */

// 6.144 MHz pixel strobe (18.432 MHz / 3 on the PCB; 49.152 / 8 here): from the board's free-running divider, which
// also slots the 6809s (1.536 MHz) and the ROM store port A.

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

// MC6809E x3 (Greg Miller's mc6809is, unmodified). RESET is on the bus: the LS259 SUB RESET (sub / sub2) and the
// watchdog (main). Pool slot, not role:
//   m6809_0: main CPU, every board
//   m6809_1: Super Pac-Man / Mappy / Phozon sound CPU, Gaplus sub CPU
//   m6809_2: Phozon sub CPU (sub2), Gaplus sound CPU
chip_pool_pkg::m6809r_i_t m6809_i[3];
chip_pool_pkg::m6809r_o_t m6809_o[3];

chip_pool_pkg::m6809r_i_t sp_m6809_0_i, sp_m6809_1_i;
assign m6809_i[0] = sp_m6809_0_i;
assign m6809_i[1] = sp_m6809_1_i;
assign m6809_i[2].reset_n = 1'b0;            // idle until the Phozon / Gaplus boards
assign m6809_i[2].fall_e  = 1'b0;
assign m6809_i[2].fall_q  = 1'b0;
assign m6809_i[2].irq_n   = 1'b1;
assign m6809_i[2].firq_n  = 1'b1;
assign m6809_i[2].nmi_n   = 1'b1;
assign m6809_i[2].d       = 8'hFF;

genvar ci;
generate
    for (ci = 0; ci < 3; ci = ci + 1) begin : g_m6809

        wire [15:0] a;
        wire  [7:0] dout;
        wire        rw, lic;
        mc6809is m6809
        (
            .CLK(clk), .fallE_en(m6809_i[ci].fall_e), .fallQ_en(m6809_i[ci].fall_q), .D(m6809_i[ci].d), .DOut(dout),
            .ADDR(a), .RnW(rw), .BS(), .BA(), .nIRQ(m6809_i[ci].irq_n), .nFIRQ(m6809_i[ci].firq_n),
            .nNMI(m6809_i[ci].nmi_n), .AVMA(), .BUSY(), .LIC(lic), .nHALT(1'b1),
            .nRESET(~reset & m6809_i[ci].reset_n), .nDMABREQ(1'b1), .RegData()
        );
        assign m6809_o[ci].a = a;  assign m6809_o[ci].dout = dout;  assign m6809_o[ci].rw = rw;  assign m6809_o[ci].lic = lic;
    end
endgenerate

// Namco 15XX WSG x1 (every board; volume DAC by dac_mode): rtl/sound/namco_15xx.sv
chip_pool_pkg::wsg15_i_t wsg15_0_i;
chip_pool_pkg::wsg15_o_t wsg15_0_o;
logic wsg15_0_smp;
namco_15xx wsg15_0(.clk(clk), .reset(reset), .smp(wsg15_0_smp), .i(wsg15_0_i), .o(wsg15_0_o));

// Namco custom I/O x2 (56XX / 58XX / 59XX, runtime kind from index 1 byte 2; MCUs undumped: behavioural per MAME
// namcoio.cpp, rtl/namco/namco_io.sv - 56XX only so far)
chip_pool_pkg::namcoio_i_t namcoio_i[2];
chip_pool_pkg::namcoio_o_t namcoio_o[2];
generate
    for (ci = 0; ci < 2; ci = ci + 1) begin : g_namcoio
        namco_io io(.clk(clk), .reset(reset), .i(namcoio_i[ci]), .o(namcoio_o[ci]));
    end
endgenerate

// MB88 x1: Gaplus 62XX (MB8843; mask ROM dumped in MAME namco62.zip). Fleet mb88_sv (MB88-2026-10-24; was Pole Position's
// copy without ram_clr); ram_clr tied off: this board has no MCU power-on RAM sweep.
chip_pool_pkg::mb88_i_t mb88_0_i;
chip_pool_pkg::mb88_o_t mb88_0_o;
assign mb88_0_i.ena     = 1'b0;             // idle until the Gaplus board
assign mb88_0_i.reset_n = 1'b0;
assign mb88_0_i.k       = 4'hF;
assign mb88_0_i.r_in    = 16'hFFFF;
assign mb88_0_i.irq_n   = 1'b1;
assign mb88_0_i.tc_n    = 1'b1;
assign mb88_0_i.si_n    = 1'b1;
assign mb88_0_i.rom_d   = 8'h00;

wire  [3:0] mb88_r0, mb88_r1, mb88_r2, mb88_r3, mb88_ol, mb88_oh, mb88_p;
wire        mb88_owr;
wire [10:0] mb88_rom_a;
mb88 mb88_0
(
    .clock(clk), .ena(mb88_0_i.ena), .reset_n(mb88_0_i.reset_n), .ram_clr(1'b0),
    .r0_port_in(mb88_0_i.r_in[3:0]), .r1_port_in(mb88_0_i.r_in[7:4]), .r2_port_in(mb88_0_i.r_in[11:8]),
    .r3_port_in(mb88_0_i.r_in[15:12]),
    .r0_port_out(mb88_r0), .r1_port_out(mb88_r1), .r2_port_out(mb88_r2), .r3_port_out(mb88_r3),
    .k_port_in(mb88_0_i.k), .ol_port_out(mb88_ol), .oh_port_out(mb88_oh), .o_wr(mb88_owr), .p_port_out(mb88_p),
    .stby_n(1'b1), .tc_n(mb88_0_i.tc_n), .irq_n(mb88_0_i.irq_n), .sc_in_n(1'b1), .si_n(mb88_0_i.si_n),
    .sc_out_n(), .so_n(), .to_n(),
    .rom_addr(mb88_rom_a), .rom_data(mb88_0_i.rom_d)
);
assign mb88_0_o.r_out = {mb88_r3, mb88_r2, mb88_r1, mb88_r0};
assign mb88_0_o.o     = {mb88_oh, mb88_ol};
assign mb88_0_o.o_wr  = mb88_owr;
assign mb88_0_o.p     = mb88_p;
assign mb88_0_o.rom_a = mb88_rom_a;

/////////////////////////////  Shared ROM blocks  /////////////////////////////

// Packed store: 12 x 8K banks = 96K (max per-set total of the five regions: Gaplus 0x18000). Linear load,
// index 0 byte n -> bank n[16:13]. Two read ports, both 17-bit packed addresses: packed = (region address +
// rom_ofs[region]) mod 2^17, where region address = the MAME region offset (CPU address for the CPU regions).
// Port A = CPU side (the board time-slices its 6809s), port B = video side (tiles / sprites).
// Same latency as one RAM: the bank select is registered alongside the address.
localparam NBANK = 12;

logic [16:0] rom_a_addr, rom_b_addr;
logic  [7:0] rom_a_q, rom_b_q;
// driven by the board (region address + rom_ofs[region])

wire        ld_pack = ioctl_wr0 && ioctl_addr < 25'h18000;
logic [3:0] rd_bank_a, rd_bank_b;
always_ff @(posedge clk) begin
    rd_bank_a <= rom_a_addr[16:13];
    rd_bank_b <= rom_b_addr[16:13];
end

wire [7:0] bank_qa[16], bank_qb[16];
genvar bi;
generate
    for (bi = 0; bi < 16; bi = bi + 1) begin : g_bank
        if (bi < NBANK) begin : g_ram
            wire ld = ld_pack && ioctl_addr[16:13] == 4'(bi);
            dpram_dc #(.widthad_a(13)) rom
            (
                .clock_a(clk), .address_a(ld ? ioctl_addr[12:0] : rom_a_addr[12:0]), .data_a(ioctl_dout), .wren_a(ld),
                .byteena_a(1'b1), .q_a(bank_qa[bi]),
                .clock_b(clk), .address_b(rom_b_addr[12:0]), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1),
                .q_b(bank_qb[bi])
            );
        end
        else begin : g_none
            assign bank_qa[bi] = 8'd0;
            assign bank_qb[bi] = 8'd0;
        end
    end
endgenerate
assign rom_a_q = bank_qa[rd_bank_a];
assign rom_b_q = bank_qb[rd_bank_b];

// Colour PROMs (2K window: port B, and port A once loaded), 15XX waveform PROM, 62XX MCU ROM: fixed windows
logic [10:0] prom_addr, prom_a_addr;
logic  [7:0] wave_addr;
logic [10:0] mcu62_addr;
logic  [7:0] prom_q, prom_a_q;
/* verilator lint_off UNUSED */
logic  [7:0] wave_q, mcu62_q;
/* verilator lint_on UNUSED */
assign wave_addr  = wsg15_0_o.wave_a;
assign mcu62_addr = mb88_0_o.rom_a;

wire ld_prom  = ioctl_wr0 && ioctl_addr[24:11] == 14'(25'h18000 >> 11);
wire ld_wave  = ioctl_wr0 && ioctl_addr[24:8]  == 17'(25'h18800 >> 8);
wire ld_mcu62 = ioctl_wr0 && ioctl_addr[24:11] == 14'(25'h19000 >> 11);

dpram_dc #(.widthad_a(11)) prom_ram
(
    .clock_a(clk), .address_a(ld_prom ? ioctl_addr[10:0] : prom_a_addr), .data_a(ioctl_dout), .wren_a(ld_prom),
    .byteena_a(1'b1), .q_a(prom_a_q),
    .clock_b(clk), .address_b(prom_addr), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(prom_q)
);
dpram_dc #(.widthad_a(8)) wave_rom
(
    .clock_a(clk), .address_a(ioctl_addr[7:0]), .data_a(ioctl_dout), .wren_a(ld_wave), .byteena_a(1'b1), .q_a(),
    .clock_b(clk), .address_b(wave_addr), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(wave_q)
);
dpram_dc #(.widthad_a(11)) mcu62_rom
(
    .clock_a(clk), .address_a(ioctl_addr[10:0]), .data_a(ioctl_dout), .wren_a(ld_mcu62), .byteena_a(1'b1), .q_a(),
    .clock_b(clk), .address_b(mcu62_addr), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(mcu62_q)
);

/////////////////////////////  Shared RAM pool  /////////////////////////////

// Sizes = max over the sets (MAME memory maps):
//   vram    4K   tilemap RAM (Mappy family 0000-0FFF code+colour; Super Pac / Phozon / Gaplus use 2K)
//   wram[3] 3x2K work RAM with embedded sprite registers (x780-x7FF of each: number/colour, x/y, x-msb/flip/size)
//   xram    2K   Phozon sub2 private RAM (A000-A7FF)
//   sram    1K   15XX shared sound RAM (registers = first 64 bytes)
//   lbuf    1K   sprite line buffer, ping-pong by line parity (2 x 512 x 8)
// Port A = CPU side (board arbitrates its CPUs), port B = video side / hiscore.
logic [11:0] vram_aa, vram_ab;  logic [7:0] vram_da, vram_qa, vram_qb;  logic vram_wa;
logic [10:0] xram_aa;           logic [7:0] xram_da, xram_qa;           logic xram_wa;
logic  [9:0] sram_aa, sram_ab;  logic [7:0] sram_da, sram_db, sram_qa, sram_qb;  logic sram_wa, sram_wb;
logic  [9:0] lbuf_aa, lbuf_ab;  logic [7:0] lbuf_da, lbuf_qa, lbuf_qb;  logic lbuf_wa;
logic [10:0] wram_aa[3], wram_ab[3];
logic  [7:0] wram_da[3], wram_qa[3], wram_qb[3];
logic        wram_wa[3];

// driven by the board (xram: Phozon only, idle)
assign {xram_aa, xram_da, xram_wa} = '0;
logic [2:0][10:0] sp_wram_aa;
logic [2:0] [7:0] sp_wram_da, sp_wram_qa, sp_wram_qb;
logic [2:0]       sp_wram_wa;
logic      [10:0] sp_wram_ab;

dpram_dc #(.widthad_a(12)) vram
(
    .clock_a(clk), .address_a(vram_aa), .data_a(vram_da), .wren_a(vram_wa), .byteena_a(1'b1), .q_a(vram_qa),
    .clock_b(clk), .address_b(vram_ab), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(vram_qb)
);
generate
    for (ci = 0; ci < 3; ci = ci + 1) begin : g_wram
        assign wram_aa[ci] = sp_wram_aa[ci];
        assign wram_ab[ci] = sp_wram_ab;
        assign wram_da[ci] = sp_wram_da[ci];
        assign wram_wa[ci] = sp_wram_wa[ci];
        assign sp_wram_qa[ci] = wram_qa[ci];
        assign sp_wram_qb[ci] = wram_qb[ci];
        dpram_dc #(.widthad_a(11)) wram
        (
            .clock_a(clk), .address_a(wram_aa[ci]), .data_a(wram_da[ci]), .wren_a(wram_wa[ci]), .byteena_a(1'b1),
            .q_a(wram_qa[ci]),
            .clock_b(clk), .address_b(wram_ab[ci]), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(wram_qb[ci])
        );
    end
endgenerate
dpram_dc #(.widthad_a(11)) xram
(
    .clock_a(clk), .address_a(xram_aa), .data_a(xram_da), .wren_a(xram_wa), .byteena_a(1'b1), .q_a(xram_qa),
    .clock_b(clk), .address_b(11'd0), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b()
);
dpram_dc #(.widthad_a(10)) sram
(
    .clock_a(clk), .address_a(sram_aa), .data_a(sram_da), .wren_a(sram_wa), .byteena_a(1'b1), .q_a(sram_qa),
    .clock_b(clk), .address_b(sram_ab), .data_b(sram_db), .wren_b(sram_wb), .byteena_b(1'b1), .q_b(sram_qb)
);
dpram_dc #(.widthad_a(10)) lbuf
(
    .clock_a(clk), .address_a(lbuf_aa), .data_a(lbuf_da), .wren_a(lbuf_wa), .byteena_a(1'b1), .q_a(lbuf_qa),
    .clock_b(clk), .address_b(lbuf_ab), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(lbuf_qb)
);

/////////////////////////////  Boards  /////////////////////////////

// Super Pac-Man board (variant 0) and Mappy board (variant 2, the same module with its deltas gated).
// Phozon / Gaplus: not written yet (black, silent).
logic [7:0] sp_r, sp_g, sp_b, sp_hs_q;
logic       sp_hs, sp_vs, sp_hb, sp_vb;

superpac_board superpac
(
    .clk(clk), .reset(reset | ~(is_sp | is_mp)), .pause(pause), .mappy(is_mp), .io_kind0(game_cfg[2][1:0]), .io_kind1(game_cfg[2][3:2]),
    .rom_ofs(rom_ofs), .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),
    .in_coins(in_coins), .in_p1(in_p1), .in_p2(in_p2), .in_buttons(in_buttons), .dsw0(dsw0), .dsw1(dsw1), .dsw2(dsw2),
    .ce_pix(ce_pix), .video_r(sp_r), .video_g(sp_g), .video_b(sp_b), .video_hs(sp_hs), .video_vs(sp_vs),
    .video_hblank(sp_hb), .video_vblank(sp_vb),
    .m6809_0_i(sp_m6809_0_i), .m6809_0_o(m6809_o[0]), .m6809_1_i(sp_m6809_1_i), .m6809_1_o(m6809_o[1]),
    .wsg_i(wsg15_0_i), .wsg_smp(wsg15_0_smp),
    .io0_i(namcoio_i[0]), .io0_o(namcoio_o[0]), .io1_i(namcoio_i[1]), .io1_o(namcoio_o[1]),
    .rom_a_addr(rom_a_addr), .rom_a_q(rom_a_q), .rom_b_addr(rom_b_addr), .rom_b_q(rom_b_q),
    .prom_a_addr(prom_a_addr), .prom_a_q(prom_a_q), .prom_b_addr(prom_addr), .prom_b_q(prom_q), .wave_q(wave_q[3:0]),
    .vram_aa(vram_aa), .vram_da(vram_da), .vram_wa(vram_wa), .vram_qa(vram_qa), .vram_ab(vram_ab), .vram_qb(vram_qb),
    .wram_aa(sp_wram_aa), .wram_da(sp_wram_da), .wram_wa(sp_wram_wa), .wram_qa(sp_wram_qa), .wram_ab(sp_wram_ab),
    .wram_qb(sp_wram_qb),
    .sram_aa(sram_aa), .sram_da(sram_da), .sram_wa(sram_wa), .sram_qa(sram_qa),
    .sram_ab(sram_ab), .sram_db(sram_db), .sram_wb(sram_wb), .sram_qb(sram_qb),
    .lbuf_aa(lbuf_aa), .lbuf_da(lbuf_da), .lbuf_wa(lbuf_wa), .lbuf_ab(lbuf_ab), .lbuf_qb(lbuf_qb),
    .hs_address(hs_address), .hs_data_in(hs_data_in), .hs_data_out(sp_hs_q), .hs_write(hs_write)
);

assign {video_r, video_g, video_b} = (is_sp | is_mp) ? {sp_r, sp_g, sp_b} : 24'd0;
assign {video_hs, video_vs, video_hblank, video_vblank} = {sp_hs, sp_vs, sp_hb, sp_vb};
assign audio       = (is_sp | is_mp) ? wsg15_0_o.sound : 16'sd0;
assign hs_data_out = (is_sp | is_mp) ? sp_hs_q : 8'd0;

endmodule
