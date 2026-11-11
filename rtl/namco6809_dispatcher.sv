//============================================================================
//
//  Namco6809 dispatcher: shared CPU / sound / ROM / RAM pools and the board modules.
//  Copyright (C) 2026 Rodimus
//
//  Variant (index 1 byte 0):
//    0  Super Pac-Man board  (superpac, superpacm, pacnpal, pacnpal2, pacnchmp, grobda, grobda2, grobda3)
//    1  Phozon board         (phozon, phozons)
//    2  Mappy board          (mappy, mappyj, todruaga*, digdug2*, motos)
//    3  Gaplus board         (gaplus*, galaga3*)
//    4  Sky Kid board        (skykid*, drgnbstr)
//  Variants 0-3 run on rtl/boards/superpac/, variant 4 on rtl/boards/skykid/. The board not selected is held in reset.
//
//  ioctl index 0 (linear, variant-free load decode):
//    0x00000-0x17FFF  packed ROM store, 12 x 8K banks; per-region offsets from index 1 bytes 72-81
//                     (rom_ofs; regions 0 maincpu, 1 sub, 2 sub2, 3 tiles, 4 sprites)
//    0x18000-0x187FF  colour PROMs
//    0x18800-0x188FF  15XX waveform PROM
//    0x19000-0x1CFFF  MCU ROM block, 16K: 62XX at 0000-07FF; HD63701 sub program (8000-9FFF) at 0000-1FFF and
//                     internal ROM (F000-FFFF) at 3000-3FFF
//
//============================================================================

module namco6809_dispatcher
(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    input  logic  [7:0] variant,
    input  logic [15:0][7:0] game_cfg,
    input  logic [4:0][16:0] rom_ofs,
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

wire is_sp = variant == 8'd0;
wire is_ph = variant == 8'd1;
wire is_mp = variant == 8'd2;
wire is_gp = variant == 8'd3;
wire is_sk = variant == 8'd4;

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

// m6809_0: main CPU, every board
// m6809_1: Super Pac-Man / Mappy / Phozon sound CPU, Gaplus sub CPU
// m6809_2: Phozon sub2 CPU, Gaplus sound CPU
chip_pool_pkg::m6809r_i_t m6809_0_i, m6809_1_i, m6809_2_i;
chip_pool_pkg::m6809r_o_t m6809_0_o, m6809_1_o, m6809_2_o;

chip_pool_pkg::m6809r_i_t sp_m6809_0_i, sp_m6809_1_i, sp_m6809_2_i, sk_m6809_0_i;
assign m6809_0_i = is_sk ? sk_m6809_0_i : sp_m6809_0_i;
assign m6809_1_i = sp_m6809_1_i;
assign m6809_2_i = sp_m6809_2_i;

wire [15:0] m6809_0_a, m6809_1_a, m6809_2_a;
wire  [7:0] m6809_0_do, m6809_1_do, m6809_2_do;
wire        m6809_0_rw, m6809_1_rw, m6809_2_rw, m6809_0_lic, m6809_1_lic, m6809_2_lic;
mc6809is m6809_0
(
    .CLK(clk), .fallE_en(m6809_0_i.fall_e), .fallQ_en(m6809_0_i.fall_q), .D(m6809_0_i.d), .DOut(m6809_0_do),
    .ADDR(m6809_0_a), .RnW(m6809_0_rw), .BS(), .BA(), .nIRQ(m6809_0_i.irq_n), .nFIRQ(m6809_0_i.firq_n),
    .nNMI(m6809_0_i.nmi_n), .AVMA(), .BUSY(), .LIC(m6809_0_lic), .nHALT(1'b1),
    .nRESET(~reset & m6809_0_i.reset_n), .nDMABREQ(1'b1), .RegData()
);
mc6809is m6809_1
(
    .CLK(clk), .fallE_en(m6809_1_i.fall_e), .fallQ_en(m6809_1_i.fall_q), .D(m6809_1_i.d), .DOut(m6809_1_do),
    .ADDR(m6809_1_a), .RnW(m6809_1_rw), .BS(), .BA(), .nIRQ(m6809_1_i.irq_n), .nFIRQ(m6809_1_i.firq_n),
    .nNMI(m6809_1_i.nmi_n), .AVMA(), .BUSY(), .LIC(m6809_1_lic), .nHALT(1'b1),
    .nRESET(~reset & m6809_1_i.reset_n), .nDMABREQ(1'b1), .RegData()
);
mc6809is m6809_2
(
    .CLK(clk), .fallE_en(m6809_2_i.fall_e), .fallQ_en(m6809_2_i.fall_q), .D(m6809_2_i.d), .DOut(m6809_2_do),
    .ADDR(m6809_2_a), .RnW(m6809_2_rw), .BS(), .BA(), .nIRQ(m6809_2_i.irq_n), .nFIRQ(m6809_2_i.firq_n),
    .nNMI(m6809_2_i.nmi_n), .AVMA(), .BUSY(), .LIC(m6809_2_lic), .nHALT(1'b1),
    .nRESET(~reset & m6809_2_i.reset_n), .nDMABREQ(1'b1), .RegData()
);
assign m6809_0_o.a = m6809_0_a;  assign m6809_0_o.dout = m6809_0_do;  assign m6809_0_o.rw = m6809_0_rw;  assign m6809_0_o.lic = m6809_0_lic;
assign m6809_1_o.a = m6809_1_a;  assign m6809_1_o.dout = m6809_1_do;  assign m6809_1_o.rw = m6809_1_rw;  assign m6809_1_o.lic = m6809_1_lic;
assign m6809_2_o.a = m6809_2_a;  assign m6809_2_o.dout = m6809_2_do;  assign m6809_2_o.rw = m6809_2_rw;  assign m6809_2_o.lic = m6809_2_lic;

// wsg15_0: Super Pac-Man / Phozon / Mappy / Gaplus
chip_pool_pkg::wsg15_i_t wsg15_0_i;
chip_pool_pkg::wsg15_o_t wsg15_0_o;
logic wsg15_0_smp;
namco_15xx wsg15_0(.clk(clk), .reset(reset), .smp(wsg15_0_smp), .i(wsg15_0_i), .o(wsg15_0_o));

// namcoio_0, namcoio_1: Super Pac-Man / Phozon / Mappy / Gaplus (kind per set: index 1 byte 2)
chip_pool_pkg::namcoio_i_t namcoio_0_i, namcoio_1_i;
chip_pool_pkg::namcoio_o_t namcoio_0_o, namcoio_1_o;
namco_io namcoio_0(.clk(clk), .reset(reset), .i(namcoio_0_i), .o(namcoio_0_o));
namco_io namcoio_1(.clk(clk), .reset(reset), .i(namcoio_1_i), .o(namcoio_1_o));

// n62_0: Gaplus 62XX (namco_62xx on mb88_0; mask ROM from the MCU ROM block)
chip_pool_pkg::mb88_i_t mb88_0_i;
chip_pool_pkg::mb88_o_t mb88_0_o;
logic  [7:0] mcu_rom_q;
chip_pool_pkg::namco_62xx_i_t n62_0_i;
chip_pool_pkg::namco_62xx_o_t n62_0_o;
wire  [10:0] n62_0_rom_a;
namco_62xx n62_0(.i(n62_0_i), .o(n62_0_o), .rom_a(n62_0_rom_a), .rom_d(mcu_rom_q), .mb88_i(mb88_0_i), .mb88_o(mb88_0_o));

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

// mcu_0: Sky Kid HD63701 (mode 6, ROM external: MCU ROM block)
chip_pool_pkg::hd63701_i_t mcu_0_i;
chip_pool_pkg::hd63701_o_t mcu_0_o;
jtframe_6801mcu #(.ROMW(12), .MODEL("HD63701V")) mcu_0
(
    .rst(reset | ~is_sk | mcu_0_i.rst), .clk(clk), .cen(mcu_0_i.cen), .cen_tmr(mcu_0_i.cen_tmr),
    .irq(mcu_0_i.irq), .nmi(mcu_0_i.nmi),
    .addr(mcu_0_o.addr), .xdin(mcu_0_i.xdin), .dout(mcu_0_o.dout), .wr(mcu_0_o.wr), .x_cs(mcu_0_o.x_cs), .ba(mcu_0_o.ba),
    .p1_din(mcu_0_i.p1_din), .p3_din(mcu_0_i.p3_din), .p4_din(mcu_0_i.p4_din),
    .p1_dout(mcu_0_o.p1_dout), .p3_dout(mcu_0_o.p3_dout), .p4_dout(mcu_0_o.p4_dout),
    .p2_din(mcu_0_i.p2_din), .p2_dout(mcu_0_o.p2_dout),
    .rom_addr(), .rom_data(mcu_rom_q), .rom_cs()
);

// cus30_0: Sky Kid CUS30
chip_pool_pkg::cus30_i_t cus30_0_i;
chip_pool_pkg::cus30_o_t cus30_0_o;
logic signed [12:0] c30_snd;
jtcus30 cus30_0
(
    .rst(reset | ~is_sk | cus30_0_i.rst), .clk(clk), .bsel(cus30_0_i.bsel), .cen(cus30_0_i.cen), .xdin(cus30_0_o.xdin),
    .bcs(cus30_0_i.bcs), .brnw(cus30_0_i.brnw), .baddr(cus30_0_i.baddr), .bdout(cus30_0_i.bdout),
    .scs(cus30_0_i.scs), .srnw(cus30_0_i.srnw), .saddr(cus30_0_i.saddr), .sdout(cus30_0_i.sdout),
    .sample(cus30_0_o.sample), .snd_l(cus30_0_o.snd_l), .snd_r(cus30_0_o.snd_r), .debug_bus(8'd0)
);
assign c30_snd = cus30_0_o.snd_l;

/////////////////////////////  Shared ROM blocks  /////////////////////////////

//   rom_a / rom_b   packed store 96K (12 x 8K): port A CPU side, port B video side (region address + rom_ofs)
//   prom_ram        colour PROMs 2K: port B video, port A after the load
//   wave_rom        15XX waveform PROM 256 B
//   mcu_rom         MCU ROM block 16K: n62_0 / mcu_0

localparam NBANK = 12;

logic [16:0] rom_a_addr, rom_b_addr, sp_rom_a_addr, sp_rom_b_addr, sk_rom_a_addr, sk_rom_b_addr;
logic  [7:0] rom_a_q, rom_b_q;
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
assign mcu_rom_addr = !is_sk ? {3'd0, n62_0_rom_a} :
                      (mcu_0_o.addr[15:12] == 4'hF) ? {2'b11, mcu_0_o.addr[11:0]} : {1'b0, mcu_0_o.addr[12:0]};

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

//   blk  size  superpac board (variants 0-3)                    skykid board (variant 4)
//   0    4K    tilemap RAM (A CPU / hiscore, B video)            background RAM (A CPU / hiscore, B video)
//   1    2K    work RAM 0800 + sprite regs (A CPU, B sprites)    work RAM 0 + sprite regs (A CPU, B sprites)
//   2    2K    work RAM 1000 + sprite regs (A CPU, B sprites)    work RAM 1 + sprite regs (A CPU, B sprites)
//   3    2K    work RAM 1800 + sprite regs (A CPU, B sprites)    work RAM 2 + sprite regs (A CPU, B sprites)
//   4    2K    Phozon sub2 RAM A000-A7FF (A)                     text RAM (A CPU, B video)
//   5    2K    15XX shared sound RAM 1K (A main / sub2, B sound)  MCU RAM C000-C7FF (A)
localparam int RAM_BLOCKS = 6;
function automatic int ram_aw(input int n);
    return (n == 0) ? 12 : 11;
endfunction

ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] pool_i, sp_pr_i, sk_pr_i;
ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pool_o;
assign pool_i = is_sk ? sk_pr_i : sp_pr_i;

genvar ri;
generate
    for (ri = 0; ri < RAM_BLOCKS; ri = ri + 1) begin : rpool
        localparam int AW = ram_aw(ri);
        dpram_dc #(.widthad_a(AW)) ram
        (
            .clock_a(clk), .address_a(pool_i[ri].a_addr[AW-1:0]), .data_a(pool_i[ri].a_d), .wren_a(pool_i[ri].a_we),
            .byteena_a(1'b1), .q_a(pool_o[ri].a_q),
            .clock_b(clk), .address_b(pool_i[ri].b_addr[AW-1:0]), .data_b(pool_i[ri].b_d), .wren_b(pool_i[ri].b_we),
            .byteena_b(1'b1), .q_b(pool_o[ri].b_q)
        );
    end
endgenerate

logic  [9:0] lbuf_aa, lbuf_ab, sp_lbuf_aa, sp_lbuf_ab, sk_lbuf_aa, sk_lbuf_ab;
logic  [8:0] lbuf_da, lbuf_qa, lbuf_qb, sp_lbuf_da, sk_lbuf_da;
logic        lbuf_wa, sp_lbuf_wa, sk_lbuf_wa;
assign lbuf_aa = is_sk ? sk_lbuf_aa : sp_lbuf_aa;
assign lbuf_da = is_sk ? sk_lbuf_da : sp_lbuf_da;
assign lbuf_wa = is_sk ? sk_lbuf_wa : sp_lbuf_wa;
assign lbuf_ab = is_sk ? sk_lbuf_ab : sp_lbuf_ab;
dpram_dc #(.widthad_a(10), .width_a(9)) lbuf      // POOL-EXCEPTION: 9 bits wide (bit 8 = Gaplus star flag); pool blocks are 8-bit
(
    .clock_a(clk), .address_a(lbuf_aa), .data_a(lbuf_da), .wren_a(lbuf_wa), .byteena_a(1'b1), .q_a(lbuf_qa),
    .clock_b(clk), .address_b(lbuf_ab), .data_b(9'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(lbuf_qb)
);

/////////////////////////////  Boards  /////////////////////////////

logic [7:0] sp_r, sp_g, sp_b, sp_hs_q, sk_r, sk_g, sk_b, sk_hs_q;
logic       sp_hs, sp_vs, sp_hb, sp_vb, sp_ce, sk_hs, sk_vs, sk_hb, sk_vb, sk_ce;

superpac_board #(.RAM_BLOCKS(RAM_BLOCKS)) superpac
(
    .clk(clk), .reset(reset | ~(is_sp | is_ph | is_mp | is_gp)), .pause(pause), .mappy(is_mp), .phozon(is_ph), .gaplus(is_gp), .opts(game_cfg[3]), .io_kind0(game_cfg[2][1:0]), .io_kind1(game_cfg[2][3:2]),
    .rom_ofs(rom_ofs), .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),
    .in_coins(in_coins), .in_p1(in_p1), .in_p2(in_p2), .in_buttons(in_buttons), .dsw0(dsw0), .dsw1(dsw1), .dsw2(dsw2),
    .ce_pix(sp_ce), .video_r(sp_r), .video_g(sp_g), .video_b(sp_b), .video_hs(sp_hs), .video_vs(sp_vs),
    .video_hblank(sp_hb), .video_vblank(sp_vb),
    .m6809_0_i(sp_m6809_0_i), .m6809_0_o(m6809_0_o), .m6809_1_i(sp_m6809_1_i), .m6809_1_o(m6809_1_o),
    .m6809_2_i(sp_m6809_2_i), .m6809_2_o(m6809_2_o),
    .wsg15_0_i(wsg15_0_i), .wsg15_0_smp(wsg15_0_smp),
    .namcoio_0_i(namcoio_0_i), .namcoio_0_o(namcoio_0_o), .namcoio_1_i(namcoio_1_i), .namcoio_1_o(namcoio_1_o),
    .n62_0_i(n62_0_i), .n62_0_o(n62_0_o),
    .rom_a_addr(sp_rom_a_addr), .rom_a_q(rom_a_q), .rom_b_addr(sp_rom_b_addr), .rom_b_q(rom_b_q),
    .prom_a_addr(sp_prom_a_addr), .prom_a_q(prom_a_q), .prom_b_addr(sp_prom_addr), .prom_b_q(prom_q), .wave_q(wave_q[3:0]),
    .pr_i(sp_pr_i), .pr_o(pool_o),
    .lbuf_aa(sp_lbuf_aa), .lbuf_da(sp_lbuf_da), .lbuf_wa(sp_lbuf_wa), .lbuf_ab(sp_lbuf_ab), .lbuf_qb(lbuf_qb),
    .hs_address(hs_address), .hs_data_in(hs_data_in), .hs_data_out(sp_hs_q), .hs_write(hs_write)
);

skykid_board #(.RAM_BLOCKS(RAM_BLOCKS)) skykid
(
    .clk(clk), .reset(reset | ~is_sk), .pause(pause), .rom_ofs(rom_ofs), .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj),
    .in_system(in_coins), .in_p1(in_p1), .in_p2(in_p2), .in_button2(in_buttons), .dswa(dsw0), .dswb(dsw1), .dsw2(dsw2),
    .ce_pix(sk_ce), .video_r(sk_r), .video_g(sk_g), .video_b(sk_b), .video_hs(sk_hs), .video_vs(sk_vs),
    .video_hblank(sk_hb), .video_vblank(sk_vb),
    .m6809_0_i(sk_m6809_0_i), .m6809_0_o(m6809_0_o),
    .mcu_0_i(mcu_0_i), .mcu_0_o(mcu_0_o), .mcu_rom_q(mcu_rom_q),
    .cus30_0_i(cus30_0_i), .cus30_0_o(cus30_0_o),
    .rom_a_addr(sk_rom_a_addr), .rom_a_q(rom_a_q), .rom_b_addr(sk_rom_b_addr), .rom_b_q(rom_b_q),
    .prom_a_addr(sk_prom_a_addr), .prom_a_q(prom_a_q), .prom_b_addr(sk_prom_addr), .prom_b_q(prom_q),
    .pr_i(sk_pr_i), .pr_o(pool_o),
    .lbuf_aa(sk_lbuf_aa), .lbuf_da(sk_lbuf_da), .lbuf_wa(sk_lbuf_wa), .lbuf_ab(sk_lbuf_ab), .lbuf_qb(lbuf_qb),
    .hs_address(hs_address), .hs_data_in(hs_data_in), .hs_data_out(sk_hs_q), .hs_write(hs_write)
);

assign ce_pix = is_sk ? sk_ce : sp_ce;
assign {video_r, video_g, video_b} = is_sk ? {sk_r, sk_g, sk_b} : (is_sp | is_ph | is_mp | is_gp) ? {sp_r, sp_g, sp_b} : 24'd0;
assign {video_hs, video_vs, video_hblank, video_vblank} = is_sk ? {sk_hs, sk_vs, sk_hb, sk_vb} : {sp_hs, sp_vs, sp_hb, sp_vb};
logic signed [15:0] boom;
gaplus_boom boom_0(.clk(clk), .reset(reset | ~is_gp), .smp(wsg15_0_smp), .o(n62_0_o.o), .sound(boom));
wire  signed [16:0] mix = 17'($signed(wsg15_0_o.sound)) + 17'(boom);
wire  signed [15:0] mix_s = (mix > 17'sd32767) ? 16'sh7FFF : (mix < -17'sd32768) ? -16'sh8000 : mix[15:0];
wire  signed [17:0] c30_x32 = 18'(c30_snd) <<< 5;
wire  signed [15:0] c30_out = (c30_x32 > 18'sd32767) ? 16'sh7FFF : (c30_x32 < -18'sd32768) ? -16'sh8000 : c30_x32[15:0];
assign audio       = (is_sp | is_ph | is_mp) ? wsg15_0_o.sound : is_gp ? mix_s : is_sk ? c30_out : 16'sd0;
assign hs_data_out = is_sk ? sk_hs_q : (is_sp | is_ph | is_mp | is_gp) ? sp_hs_q : 8'd0;

endmodule
