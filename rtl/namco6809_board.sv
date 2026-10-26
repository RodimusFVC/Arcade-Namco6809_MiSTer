//============================================================================
//
//  Namco6809 — board top (dispatcher): shared CPU / sound / ROM / RAM pools and the two board modules.
//  Copyright (C) 2026 Rodimus
//
//  One rbf for the Namco 6809 / 15XX family (MAME namco/mappy.cpp + gaplus.cpp). Variant (MRA index 1 byte 0):
//    0  Super Pac-Man board  (superpac, superpacm, pacnpal, pacnpal2, pacnchmp, grobda, grobda2, grobda3)
//    1  Phozon board         (phozon, phozons)                       third 6809, 8x8 sprites, RGB PROMs
//    2  Mappy board          (mappy, mappyj, todruaga*, digdug2*, motos)   17XX scroll, 4bpp sprites, 99XX DAC
//    3  Gaplus board         (gaplus*, galaga3*)                      3x 6809, CUS26 stars, 62XX (MB8843)
//    4  Sky Kid board        (skykid*, drgnbstr; skykid.cpp)          6809 + HD63701 MCU, CUS30, scroll + text layers
//  The board not selected is held in reset. Boards come later as rtl/boards/<board>_board.sv and drive the pools
//  below through bus ports (rtl/chip_pool_pkg.sv); they never instance their own CPU / WSG / ROM / RAM.
//
//  ioctl index 0 (linear, variant-free load decode: index 1 arrives after the ROMs):
//    0x00000-0x17FFF  packed ROM store, 12 x 8K banks: each set's maincpu / sub / sub2 / tiles / sprites regions
//                     back to back, each 256-byte aligned; per-region offsets come from index 1 bytes 72-81
//                     (rom_ofs; regions 0 maincpu, 1 sub, 2 sub2, 3 tiles, 4 sprites; MAME ROM_FILLs not stored)
//    0x18000-0x187FF  colour PROMs (MAME "proms" region as dumped; decoded on read per variant)
//    0x18800-0x188FF  15XX waveform PROM (MAME "namco")
//    0x19000-0x1CFFF  MCU ROM block, 16K: Gaplus 62XX (namco62.zip) at 0000-07FF; Sky Kid HD63701 sub program
//                     ("mcusub", CPU 8000-9FFF) at 0000-1FFF and internal ROM ("mcu", CPU F000-FFFF) at 3000-3FFF
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
wire is_sk = variant == 8'd4;
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

chip_pool_pkg::m6809r_i_t sp_m6809_0_i, sp_m6809_1_i, sp_m6809_2_i, sk_m6809_0_i;
assign m6809_i[0] = is_sk ? sk_m6809_0_i : sp_m6809_0_i;
assign m6809_i[1] = sp_m6809_1_i;
assign m6809_i[2] = sp_m6809_2_i;            // Phozon sub CPU (Gaplus: later)

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
logic  [7:0] mcu_rom_q;                      // MCU ROM block (below)
chip_pool_pkg::mb88_i_t sp_mb88_i;           // driven by the board (Gaplus 62XX), ROM from the MCU ROM block
assign mb88_0_i.ena     = sp_mb88_i.ena;
assign mb88_0_i.reset_n = sp_mb88_i.reset_n;
assign mb88_0_i.k       = sp_mb88_i.k;
assign mb88_0_i.r_in    = sp_mb88_i.r_in;
assign mb88_0_i.irq_n   = sp_mb88_i.irq_n;
assign mb88_0_i.tc_n    = sp_mb88_i.tc_n;
assign mb88_0_i.si_n    = sp_mb88_i.si_n;
assign mb88_0_i.rom_d   = mcu_rom_q;

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

// HD63701 x1: Sky Kid MCU. jotego jtframe_6801mcu + jt680x (jtcores, GPL; 6301 microcode generated into
// rtl/cpu/jt680x/6801.*), mode 6: ROM external (MCU ROM block), crystal clock enable from the board.
logic        sk_mcu_rst, sk_mcu_cen, sk_mcu_irq, mcu_wr, mcu_xcs;
logic  [7:0] sk_mcu_xdin, sk_mcu_p1_din, mcu_dout, mcu_p1_dout;
logic [15:0] mcu_addr;
jtframe_6801mcu #(.ROMW(12), .MODEL("HD63701V")) mcu63
(
    .rst(reset | ~is_sk | sk_mcu_rst), .clk(clk), .cen(sk_mcu_cen), .cen_tmr(sk_mcu_cen),
    .irq(sk_mcu_irq), .nmi(1'b0),
    .addr(mcu_addr), .xdin(sk_mcu_xdin), .dout(mcu_dout), .wr(mcu_wr), .x_cs(mcu_xcs), .ba(),
    .p1_din(sk_mcu_p1_din), .p3_din(8'hFF), .p4_din(8'hFF), .p1_dout(mcu_p1_dout), .p3_dout(), .p4_dout(),
    .p2_din(5'h1F), .p2_dout(),
    .rom_addr(), .rom_data(mcu_rom_q), .rom_cs()
);

// CUS30 x1: Sky Kid sound. jotego jtcus30 (jtcores, GPL; waveform / register RAM inside, two CPU buses by bsel)
logic        sk_c30_cen, sk_c30_bsel, sk_c30_bcs, sk_c30_brnw, sk_c30_scs, sk_c30_srnw;
logic  [9:0] sk_c30_baddr;
logic  [7:0] sk_c30_bdout, sk_c30_sdout, c30_xdin;
logic [15:0] sk_c30_saddr;
logic signed [12:0] c30_snd;
jtcus30 c30
(
    .rst(reset | ~is_sk), .clk(clk), .bsel(sk_c30_bsel), .cen(sk_c30_cen), .xdin(c30_xdin),
    .bcs(sk_c30_bcs), .brnw(sk_c30_brnw), .baddr(sk_c30_baddr), .bdout(sk_c30_bdout),
    .scs(sk_c30_scs), .srnw(sk_c30_srnw), .saddr(sk_c30_saddr), .sdout(sk_c30_sdout),
    .sample(), .snd_l(c30_snd), .snd_r(), .debug_bus(8'd0)
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////

// Packed store: 12 x 8K banks = 96K (max per-set total of the five regions: Gaplus 0x18000). Linear load,
// index 0 byte n -> bank n[16:13]. Two read ports, both 17-bit packed addresses: packed = (region address +
// rom_ofs[region]) mod 2^17, where region address = the MAME region offset (CPU address for the CPU regions).
// Port A = CPU side (the board time-slices its 6809s), port B = video side (tiles / sprites).
// Same latency as one RAM: the bank select is registered alongside the address.
localparam NBANK = 12;

logic [16:0] rom_a_addr, rom_b_addr, sp_rom_a_addr, sp_rom_b_addr, sk_rom_a_addr, sk_rom_b_addr;
logic  [7:0] rom_a_q, rom_b_q;
// driven by the board (region address + rom_ofs[region])
assign rom_a_addr = is_sk ? sk_rom_a_addr : sp_rom_a_addr;
assign rom_b_addr = is_sk ? sk_rom_b_addr : sp_rom_b_addr;

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

// Colour PROMs (2K window: port B, and port A once loaded), 15XX waveform PROM, MCU ROM block: fixed windows
logic [10:0] prom_addr, prom_a_addr, sp_prom_addr, sp_prom_a_addr, sk_prom_addr, sk_prom_a_addr;
logic  [7:0] wave_addr;
logic [13:0] mcu_rom_addr;
assign prom_addr   = is_sk ? sk_prom_addr : sp_prom_addr;
assign prom_a_addr = is_sk ? sk_prom_a_addr : sp_prom_a_addr;
logic  [7:0] prom_q, prom_a_q;
/* verilator lint_off UNUSED */
logic  [7:0] wave_q;
/* verilator lint_on UNUSED */
assign wave_addr  = wsg15_0_o.wave_a;
// HD63701: sub ROM 8000-9FFF at 0000, internal ROM F000-FFFF at 3000; 62XX: 0000-07FF
assign mcu_rom_addr = !is_sk ? {3'd0, mb88_0_o.rom_a} :
                      (mcu_addr[15:12] == 4'hF) ? {2'b11, mcu_addr[11:0]} : {1'b0, mcu_addr[12:0]};

wire ld_prom  = ioctl_wr0 && ioctl_addr[24:11] == 14'(25'h18000 >> 11);
wire ld_wave  = ioctl_wr0 && ioctl_addr[24:8]  == 17'(25'h18800 >> 8);
wire ld_mcu   = ioctl_wr0 && ioctl_addr >= 25'h19000 && ioctl_addr < 25'h1D000;
wire [24:0] mcu_ld_a = ioctl_addr - 25'h19000;

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
dpram_dc #(.widthad_a(14)) mcu_rom
(
    .clock_a(clk), .address_a(mcu_ld_a[13:0]), .data_a(ioctl_dout), .wren_a(ld_mcu), .byteena_a(1'b1), .q_a(),
    .clock_b(clk), .address_b(mcu_rom_addr), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(mcu_rom_q)
);

/////////////////////////////  Shared RAM pool  /////////////////////////////

// Sizes = max over the sets (MAME memory maps):
//   vram    4K   tilemap RAM (Mappy family 0000-0FFF code+colour; Super Pac / Phozon / Gaplus use 2K)
//   wram[3] 3x2K work RAM with embedded sprite registers (x780-x7FF of each: number/colour, x/y, x-msb/flip/size)
//   xram    2K   Phozon sub2 private RAM (A000-A7FF); Sky Kid text RAM (4000-47FF, port B = video)
//   sram    2K   15XX shared sound RAM (registers = first 64 bytes; 1K); Sky Kid MCU RAM (C000-C7FF)
//   lbuf    1K   sprite line buffer, ping-pong by line parity (2 x 512 x 9; bit 8 = Gaplus star)
// Port A = CPU side (board arbitrates its CPUs), port B = video side / hiscore.
logic [11:0] vram_aa, vram_ab;  logic [7:0] vram_da, vram_qa, vram_qb;  logic vram_wa;
logic [10:0] xram_aa, xram_ab;  logic [7:0] xram_da, xram_qa, xram_qb;  logic xram_wa;
logic [10:0] sram_aa, sram_ab;  logic [7:0] sram_da, sram_db, sram_qa, sram_qb;  logic sram_wa, sram_wb;
logic  [9:0] lbuf_aa, lbuf_ab;  logic [8:0] lbuf_da, lbuf_qa, lbuf_qb;  logic lbuf_wa;

// board-side nets, muxed onto the pools by variant
logic [11:0] sp_vram_aa, sp_vram_ab, sk_vram_aa, sk_vram_ab;  logic [7:0] sp_vram_da, sk_vram_da;  logic sp_vram_wa, sk_vram_wa;
logic [10:0] sp_xram_aa, sk_xram_aa, sk_xram_ab;              logic [7:0] sp_xram_da, sk_xram_da;  logic sp_xram_wa, sk_xram_wa;
logic  [9:0] sp_sram_aa, sp_sram_ab;  logic [10:0] sk_sram_aa;
logic  [7:0] sp_sram_da, sp_sram_db, sk_sram_da;              logic sp_sram_wa, sp_sram_wb, sk_sram_wa;
logic  [9:0] sp_lbuf_aa, sp_lbuf_ab, sk_lbuf_aa, sk_lbuf_ab;  logic [8:0] sp_lbuf_da, sk_lbuf_da;  logic sp_lbuf_wa, sk_lbuf_wa;
assign vram_aa = is_sk ? sk_vram_aa : sp_vram_aa;
assign vram_da = is_sk ? sk_vram_da : sp_vram_da;
assign vram_wa = is_sk ? sk_vram_wa : sp_vram_wa;
assign vram_ab = is_sk ? sk_vram_ab : sp_vram_ab;
assign xram_aa = is_sk ? sk_xram_aa : sp_xram_aa;
assign xram_da = is_sk ? sk_xram_da : sp_xram_da;
assign xram_wa = is_sk ? sk_xram_wa : sp_xram_wa;
assign xram_ab = sk_xram_ab;
assign sram_aa = is_sk ? sk_sram_aa : {1'b0, sp_sram_aa};
assign sram_da = is_sk ? sk_sram_da : sp_sram_da;
assign sram_wa = is_sk ? sk_sram_wa : sp_sram_wa;
assign sram_ab = {1'b0, sp_sram_ab};
assign sram_db = sp_sram_db;
assign sram_wb = !is_sk && sp_sram_wb;
assign lbuf_aa = is_sk ? sk_lbuf_aa : sp_lbuf_aa;
assign lbuf_da = is_sk ? sk_lbuf_da : sp_lbuf_da;
assign lbuf_wa = is_sk ? sk_lbuf_wa : sp_lbuf_wa;
assign lbuf_ab = is_sk ? sk_lbuf_ab : sp_lbuf_ab;
logic [10:0] wram_aa[3], wram_ab[3];
logic  [7:0] wram_da[3], wram_qa[3], wram_qb[3];
logic        wram_wa[3];

// driven by the board (xram: Phozon sub CPU private RAM)
logic [2:0][10:0] sp_wram_aa, sk_wram_aa;
logic [2:0] [7:0] sp_wram_da, sp_wram_qa, sp_wram_qb, sk_wram_da;
logic [2:0]       sp_wram_wa, sk_wram_wa;
logic      [10:0] sp_wram_ab, sk_wram_ab;

dpram_dc #(.widthad_a(12)) vram
(
    .clock_a(clk), .address_a(vram_aa), .data_a(vram_da), .wren_a(vram_wa), .byteena_a(1'b1), .q_a(vram_qa),
    .clock_b(clk), .address_b(vram_ab), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(vram_qb)
);
generate
    for (ci = 0; ci < 3; ci = ci + 1) begin : g_wram
        assign wram_aa[ci] = is_sk ? sk_wram_aa[ci] : sp_wram_aa[ci];
        assign wram_ab[ci] = is_sk ? sk_wram_ab : sp_wram_ab;
        assign wram_da[ci] = is_sk ? sk_wram_da[ci] : sp_wram_da[ci];
        assign wram_wa[ci] = is_sk ? sk_wram_wa[ci] : sp_wram_wa[ci];
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
    .clock_b(clk), .address_b(xram_ab), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(xram_qb)
);
dpram_dc #(.widthad_a(11)) sram
(
    .clock_a(clk), .address_a(sram_aa), .data_a(sram_da), .wren_a(sram_wa), .byteena_a(1'b1), .q_a(sram_qa),
    .clock_b(clk), .address_b(sram_ab), .data_b(sram_db), .wren_b(sram_wb), .byteena_b(1'b1), .q_b(sram_qb)
);
dpram_dc #(.widthad_a(10), .width_a(9)) lbuf      // 9 bits: Gaplus star flag (1K x 9 = one M10K, as 1K x 8)
(
    .clock_a(clk), .address_a(lbuf_aa), .data_a(lbuf_da), .wren_a(lbuf_wa), .byteena_a(1'b1), .q_a(lbuf_qa),
    .clock_b(clk), .address_b(lbuf_ab), .data_b(9'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(lbuf_qb)
);

/////////////////////////////  Boards  /////////////////////////////

// Super Pac-Man (variant 0), Phozon (variant 1), Mappy (variant 2) and Gaplus (variant 3) boards: one module, deltas gated.
logic [7:0] sp_r, sp_g, sp_b, sp_hs_q, sk_r, sk_g, sk_b, sk_hs_q;
logic       sp_hs, sp_vs, sp_hb, sp_vb, sp_ce, sk_hs, sk_vs, sk_hb, sk_vb, sk_ce;

superpac_board superpac
(
    .clk(clk), .reset(reset | ~(is_sp | is_ph | is_mp | is_gp)), .pause(pause), .mappy(is_mp), .phozon(is_ph), .gaplus(is_gp), .opts(game_cfg[3]), .io_kind0(game_cfg[2][1:0]), .io_kind1(game_cfg[2][3:2]),
    .rom_ofs(rom_ofs), .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),
    .in_coins(in_coins), .in_p1(in_p1), .in_p2(in_p2), .in_buttons(in_buttons), .dsw0(dsw0), .dsw1(dsw1), .dsw2(dsw2),
    .ce_pix(sp_ce), .video_r(sp_r), .video_g(sp_g), .video_b(sp_b), .video_hs(sp_hs), .video_vs(sp_vs),
    .video_hblank(sp_hb), .video_vblank(sp_vb),
    .m6809_0_i(sp_m6809_0_i), .m6809_0_o(m6809_o[0]), .m6809_1_i(sp_m6809_1_i), .m6809_1_o(m6809_o[1]),
    .m6809_2_i(sp_m6809_2_i), .m6809_2_o(m6809_o[2]),
    .wsg_i(wsg15_0_i), .wsg_smp(wsg15_0_smp),
    .io0_i(namcoio_i[0]), .io0_o(namcoio_o[0]), .io1_i(namcoio_i[1]), .io1_o(namcoio_o[1]),
    .mb88_i(sp_mb88_i), .mb88_o(mb88_0_o),
    .rom_a_addr(sp_rom_a_addr), .rom_a_q(rom_a_q), .rom_b_addr(sp_rom_b_addr), .rom_b_q(rom_b_q),
    .prom_a_addr(sp_prom_a_addr), .prom_a_q(prom_a_q), .prom_b_addr(sp_prom_addr), .prom_b_q(prom_q), .wave_q(wave_q[3:0]),
    .vram_aa(sp_vram_aa), .vram_da(sp_vram_da), .vram_wa(sp_vram_wa), .vram_qa(vram_qa), .vram_ab(sp_vram_ab), .vram_qb(vram_qb),
    .wram_aa(sp_wram_aa), .wram_da(sp_wram_da), .wram_wa(sp_wram_wa), .wram_qa(sp_wram_qa), .wram_ab(sp_wram_ab),
    .wram_qb(sp_wram_qb),
    .sram_aa(sp_sram_aa), .sram_da(sp_sram_da), .sram_wa(sp_sram_wa), .sram_qa(sram_qa),
    .sram_ab(sp_sram_ab), .sram_db(sp_sram_db), .sram_wb(sp_sram_wb), .sram_qb(sram_qb),
    .xram_aa(sp_xram_aa), .xram_da(sp_xram_da), .xram_wa(sp_xram_wa), .xram_qa(xram_qa),
    .lbuf_aa(sp_lbuf_aa), .lbuf_da(sp_lbuf_da), .lbuf_wa(sp_lbuf_wa), .lbuf_ab(sp_lbuf_ab), .lbuf_qb(lbuf_qb),
    .hs_address(hs_address), .hs_data_in(hs_data_in), .hs_data_out(sp_hs_q), .hs_write(hs_write)
);

// Sky Kid board (variant 4)
skykid_board skykid
(
    .clk(clk), .reset(reset | ~is_sk), .pause(pause), .rom_ofs(rom_ofs), .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),
    .in_system(in_coins), .in_p1(in_p1), .in_p2(in_p2), .in_button2(in_buttons), .dswa(dsw0), .dswb(dsw1), .dsw2(dsw2),
    .ce_pix(sk_ce), .video_r(sk_r), .video_g(sk_g), .video_b(sk_b), .video_hs(sk_hs), .video_vs(sk_vs),
    .video_hblank(sk_hb), .video_vblank(sk_vb),
    .m6809_0_i(sk_m6809_0_i), .m6809_0_o(m6809_o[0]),
    .mcu_rst(sk_mcu_rst), .mcu_cen(sk_mcu_cen), .mcu_irq(sk_mcu_irq), .mcu_xdin(sk_mcu_xdin), .mcu_p1_din(sk_mcu_p1_din),
    .mcu_addr(mcu_addr), .mcu_dout(mcu_dout), .mcu_wr(mcu_wr), .mcu_xcs(mcu_xcs), .mcu_p1_dout(mcu_p1_dout),
    .mcu_rom_q(mcu_rom_q),
    .c30_cen(sk_c30_cen), .c30_bsel(sk_c30_bsel), .c30_bcs(sk_c30_bcs), .c30_brnw(sk_c30_brnw), .c30_baddr(sk_c30_baddr),
    .c30_bdout(sk_c30_bdout), .c30_scs(sk_c30_scs), .c30_srnw(sk_c30_srnw), .c30_saddr(sk_c30_saddr),
    .c30_sdout(sk_c30_sdout), .c30_xdin(c30_xdin),
    .rom_a_addr(sk_rom_a_addr), .rom_a_q(rom_a_q), .rom_b_addr(sk_rom_b_addr), .rom_b_q(rom_b_q),
    .prom_a_addr(sk_prom_a_addr), .prom_a_q(prom_a_q), .prom_b_addr(sk_prom_addr), .prom_b_q(prom_q),
    .vram_aa(sk_vram_aa), .vram_da(sk_vram_da), .vram_wa(sk_vram_wa), .vram_qa(vram_qa), .vram_ab(sk_vram_ab), .vram_qb(vram_qb),
    .wram_aa(sk_wram_aa), .wram_da(sk_wram_da), .wram_wa(sk_wram_wa), .wram_qa(sp_wram_qa), .wram_ab(sk_wram_ab),
    .wram_qb(sp_wram_qb),
    .xram_aa(sk_xram_aa), .xram_da(sk_xram_da), .xram_wa(sk_xram_wa), .xram_qa(xram_qa), .xram_ab(sk_xram_ab), .xram_qb(xram_qb),
    .sram_aa(sk_sram_aa), .sram_da(sk_sram_da), .sram_wa(sk_sram_wa), .sram_qa(sram_qa),
    .lbuf_aa(sk_lbuf_aa), .lbuf_da(sk_lbuf_da), .lbuf_wa(sk_lbuf_wa), .lbuf_ab(sk_lbuf_ab), .lbuf_qb(lbuf_qb),
    .hs_address(hs_address), .hs_data_in(hs_data_in), .hs_data_out(sk_hs_q), .hs_write(hs_write)
);

assign ce_pix = is_sk ? sk_ce : sp_ce;
assign {video_r, video_g, video_b} = is_sk ? {sk_r, sk_g, sk_b} : (is_sp | is_ph | is_mp | is_gp) ? {sp_r, sp_g, sp_b} : 24'd0;
assign {video_hs, video_vs, video_hblank, video_vblank} = is_sk ? {sk_hs, sk_vs, sk_hb, sk_vb} : {sp_hs, sp_vs, sp_hb, sp_vb};
// Gaplus: 62XX explosion (two DACs + band-pass filters) summed with the 15XX / 99XX
logic signed [15:0] boom;
gaplus_boom boom_0(.clk(clk), .reset(reset | ~is_gp), .smp(wsg15_0_smp), .o(mb88_0_o.o), .sound(boom));
wire  signed [16:0] mix = 17'($signed(wsg15_0_o.sound)) + 17'(boom);
wire  signed [15:0] mix_s = (mix > 17'sd32767) ? 16'sh7FFF : (mix < -17'sd32768) ? -16'sh8000 : mix[15:0];
wire  signed [17:0] c30_x32 = 18'(c30_snd) <<< 5;      // CUS30 (13-bit, DC removed) x32 = MAME's level (Dragon Buster sim 2026-10-25)
wire  signed [15:0] c30_out = (c30_x32 > 18'sd32767) ? 16'sh7FFF : (c30_x32 < -18'sd32768) ? -16'sh8000 : c30_x32[15:0];
assign audio       = (is_sp | is_ph | is_mp) ? wsg15_0_o.sound : is_gp ? mix_s : is_sk ? c30_out : 16'sd0;
assign hs_data_out = is_sk ? sk_hs_q : (is_sp | is_ph | is_mp | is_gp) ? sp_hs_q : 8'd0;

endmodule
