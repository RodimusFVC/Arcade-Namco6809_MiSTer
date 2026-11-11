//  Based on MAME mappy.cpp, gaplus.cpp (Manuel Abadia, Ernesto Corvi, Nicola Salmoria, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module superpac_board #(parameter int RAM_BLOCKS = 6)
(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    input  logic        mappy,
    input  logic        phozon,
    input  logic        gaplus,
    input  logic  [7:0] opts,                   // index 1 byte 3: [0] no watchdog, [1] 256 sprites, [2] 64 sprite colours
    input  logic  [1:0] io_kind0,
    input  logic  [1:0] io_kind1,
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

    output logic        ce_pix,
    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,

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

    output logic [16:0] rom_a_addr,
    input  logic  [7:0] rom_a_q,
    output logic [16:0] rom_b_addr,
    input  logic  [7:0] rom_b_q,
    output logic [10:0] prom_a_addr,
    input  logic  [7:0] prom_a_q,
    output logic [10:0] prom_b_addr,
    input  logic  [7:0] prom_b_q,
    input  logic  [3:0] wave_q,

    output ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] pr_i,
    input  ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pr_o,
    output logic  [9:0] lbuf_aa,
    output logic  [8:0] lbuf_da,
    output logic        lbuf_wa,
    output logic  [9:0] lbuf_ab,
    input  logic  [8:0] lbuf_qb,

    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write
);

logic [11:0] vram_aa, vram_ab;
logic  [7:0] vram_da, vram_qa, vram_qb;
logic        vram_wa;
logic [2:0][10:0] wram_aa;
logic [2:0] [7:0] wram_da, wram_qa, wram_qb;
logic [2:0]       wram_wa;
logic      [10:0] wram_ab;
logic  [9:0] sram_aa, sram_ab;
logic  [7:0] sram_da, sram_db, sram_qa, sram_qb;
logic        sram_wa, sram_wb;
logic [10:0] xram_aa;
logic  [7:0] xram_da, xram_qa;
logic        xram_wa;

assign pr_i[0].a_addr = {4'd0, vram_aa};      assign pr_i[0].a_d = vram_da;     assign pr_i[0].a_we = vram_wa;
assign pr_i[0].b_addr = {4'd0, vram_ab};      assign pr_i[0].b_d = 8'd0;        assign pr_i[0].b_we = 1'b0;
assign vram_qa = pr_o[0].a_q;                 assign vram_qb = pr_o[0].b_q;
assign pr_i[1].a_addr = {5'd0, wram_aa[0]};   assign pr_i[1].a_d = wram_da[0];  assign pr_i[1].a_we = wram_wa[0];
assign pr_i[1].b_addr = {5'd0, wram_ab};      assign pr_i[1].b_d = 8'd0;        assign pr_i[1].b_we = 1'b0;
assign wram_qa[0] = pr_o[1].a_q;              assign wram_qb[0] = pr_o[1].b_q;
assign pr_i[2].a_addr = {5'd0, wram_aa[1]};   assign pr_i[2].a_d = wram_da[1];  assign pr_i[2].a_we = wram_wa[1];
assign pr_i[2].b_addr = {5'd0, wram_ab};      assign pr_i[2].b_d = 8'd0;        assign pr_i[2].b_we = 1'b0;
assign wram_qa[1] = pr_o[2].a_q;              assign wram_qb[1] = pr_o[2].b_q;
assign pr_i[3].a_addr = {5'd0, wram_aa[2]};   assign pr_i[3].a_d = wram_da[2];  assign pr_i[3].a_we = wram_wa[2];
assign pr_i[3].b_addr = {5'd0, wram_ab};      assign pr_i[3].b_d = 8'd0;        assign pr_i[3].b_we = 1'b0;
assign wram_qa[2] = pr_o[3].a_q;              assign wram_qb[2] = pr_o[3].b_q;
assign pr_i[4].a_addr = {5'd0, xram_aa};      assign pr_i[4].a_d = xram_da;     assign pr_i[4].a_we = xram_wa;
assign pr_i[4].b_addr = 16'd0;                assign pr_i[4].b_d = 8'd0;        assign pr_i[4].b_we = 1'b0;
assign xram_qa = pr_o[4].a_q;
assign pr_i[5].a_addr = {6'd0, sram_aa};      assign pr_i[5].a_d = sram_da;     assign pr_i[5].a_we = sram_wa;
assign pr_i[5].b_addr = {6'd0, sram_ab};      assign pr_i[5].b_d = sram_db;     assign pr_i[5].b_we = sram_wb;
assign sram_qa = pr_o[5].a_q;                 assign sram_qb = pr_o[5].b_q;

// div is never reset: the video counters rely on hcnt[1:0] = div[4:3] (ROM port-A slots).
logic [4:0] div = 5'd0;
always_ff @(posedge clk) div <= div + 5'd1;

// The hiscore borrows the CPU RAM ports while paused; the CPUs stay held 2 clocks longer so their first read sees their own address.
logic [1:0] pause_d = 2'b00;
always_ff @(posedge clk) pause_d <= {pause_d[0], pause};
wire pause_x = pause | (|pause_d);

wire fall_q  = (div == 5'd23) & ~pause_x;
wire fall_e  = (div == 5'd31) & ~pause_x;
wire sfall_q = (div == 5'd7)  & ~pause_x;
wire sfall_e = (div == 5'd15) & ~pause_x;
wire sub_on  = phozon | gaplus;
wire fall_q2 = (div == 5'd15) & ~pause_x & sub_on;
wire fall_e2 = (div == 5'd23) & ~pause_x & sub_on;

logic        vblank_start;
logic        sp_flip = 1'b0;
logic  [7:0] scroll = 8'd0;
wire         flip;
logic [12:0] tile_rom_a;
logic [14:0] spr_rom_a;
logic  [9:0] clut_a;
logic [10:0] slut_a;
logic [11:0] vid_vram_a;
logic [10:0] vid_spr_a;
logic  [9:0] v_lbuf_wa, v_lbuf_ra;
logic  [8:0] v_lbuf_wd;
logic [3:0][7:0] star_ctl = '0;
logic        v_lbuf_we;
logic  [8:0] hcnt, vcnt;
logic  [7:0] main_rom_q, sub_rom_q, sub2_rom_q;

assign ce_pix = div[2:0] == 3'd7;

superpac_video video
(
    .clk(clk), .div(div), .mappy(mappy), .phozon(phozon), .gaplus(gaplus), .star_ctl(star_ctl), .sprbig(opts[1]), .slut64(opts[2]), .flip(flip), .crt_flip(crt_flip), .scroll(scroll), .h_adj(h_adj), .v_adj(v_adj),
    .hcnt(hcnt), .vcnt(vcnt), .vblank_start(vblank_start),
    .vram_a(vid_vram_a), .vram_q(vram_qb),
    .spr_a(vid_spr_a), .spr_q0(wram_qb[0]), .spr_q1(wram_qb[1]), .spr_q2(wram_qb[2]),
    .tile_rom_a(tile_rom_a), .tile_rom_q(rom_a_q),
    .spr_rom_a(spr_rom_a), .spr_rom_q(rom_b_q),
    .clut_a(clut_a), .clut_q(prom_b_q), .slut_a(slut_a), .slut_q(prom_a_q),
    .lbuf_wa(v_lbuf_wa), .lbuf_wd(v_lbuf_wd), .lbuf_we(v_lbuf_we), .lbuf_ra(v_lbuf_ra), .lbuf_rq(lbuf_qb),
    .r(video_r), .g(video_g), .b(video_b), .hs(video_hs), .vs(video_vs),
    .hblank(video_hblank), .vblank(video_vblank)
);

assign vram_ab     = vid_vram_a;
assign wram_ab     = vid_spr_a;
assign lbuf_aa     = v_lbuf_wa;
assign lbuf_da     = v_lbuf_wd;
assign lbuf_wa     = v_lbuf_we;
assign lbuf_ab     = v_lbuf_ra;
assign prom_b_addr = {1'b0, clut_a};
assign prom_a_addr = slut_a;

wire [15:0] a  = m6809_0_o.a;
wire  [7:0] do_ = m6809_0_o.dout;
wire        rw = m6809_0_o.rw;
wire        wr = fall_e & ~rw;

function automatic [2:0] ram_bank(input [15:0] x, input mp);
    if (!mp) ram_bank = (x[15:13] == 3'b000) ? {1'b0, x[12:11]} : 3'd7;
    else if (x[15:12] == 4'h0) ram_bank = 3'd0;
    else case (x[15:11])
        5'b00010: ram_bank = 3'd1;
        5'b00011: ram_bank = 3'd2;
        5'b00100: ram_bank = 3'd3;
        default:  ram_bank = 3'd7;
    endcase
endfunction

wire [2:0] bank     = ram_bank(a, mappy);
wire cs_vram  = bank == 3'd0;
wire cs_wram0 = bank == 3'd1;
wire cs_wram1 = bank == 3'd2;
wire cs_wram2 = bank == 3'd3;
wire cs_flip  = !mappy && !phozon && !gaplus && a[15:11] == 5'b00100;
wire cs_scrl  = mappy && a[15:11] == 5'b00111;
wire cs_sram  = a[15:11] == (gaplus ? 5'b01100 : 5'b01000);
wire cs_io    = a[15:11] == (gaplus ? 5'b01101 : 5'b01001);
wire cs_latch = !gaplus && a[15:11] == 5'b01010;
wire cs_wdr   = gaplus ? a[15:11] == 5'b01111 : phozon ? a[15:11] == 5'b01110 : a[15:11] == 5'b10000;
wire wd_kick  = cs_wdr && (gaplus ? fall_e & rw : wr);
wire g_mirq   = gaplus && a[15:12] == 4'h7 && wr;
wire g_sres   = gaplus && a[15:12] == 4'h8 && wr;
wire g_fres   = gaplus && a[15:12] == 4'h9 && wr;
wire g_star   = gaplus && a[15:11] == 5'b10100 && wr;
wire cs_rom   = (mappy || phozon) ? a[15] : a[15:13] >= 3'b101;

wire [15:0] sa  = m6809_1_o.a;
wire  [7:0] sdo = m6809_1_o.dout;
wire        srw = m6809_1_o.rw;
wire        swr = sfall_e & ~srw;

wire scs_sram  = sa[15:13] == 3'b000;
wire scs_latch = !phozon && !gaplus && sa[15:13] == 3'b001;
wire g_sirq    = gaplus && sa[15:14] == 2'b01 && swr;
wire scs_rom   = sa[15:13] == 3'b111;

wire [15:0] a2  = m6809_2_o.a;
wire  [7:0] do2 = m6809_2_o.dout;
wire        rw2 = m6809_2_o.rw;
wire        wr2 = fall_e2 & ~rw2;

wire [2:0] bank2   = ram_bank(a2, 1'b0);
wire       s2_sram = phozon && a2[15:11] == 5'b01000;
wire       s2_xram = phozon && a2[15:11] == 5'b10100;
wire       s2_rom  = gaplus ? a2[15:13] >= 3'b101 : a2[15:13] == 3'b111;
wire       g_s2irq = gaplus && a2[15:12] == 4'h6 && wr2;
wire       slot2   = sub_on && div[4:3] == 2'd2;

logic  [3:0] wd_cnt  = 4'd0;
logic [11:0] wd_hold = 12'd0;
always_ff @(posedge clk) begin
    if (reset) begin
        wd_cnt  <= 4'd0;
        wd_hold <= 12'd0;
    end
    else begin
        if (wd_hold != 12'd0) wd_hold <= wd_hold - 12'd1;
        if (wd_kick) wd_cnt <= 4'd0;
        else if (vblank_start && !pause && !opts[0]) begin
            if (wd_cnt == 4'd7) begin wd_cnt <= 4'd0; wd_hold <= 12'hFFF; end
            else wd_cnt <= wd_cnt + 4'd1;
        end
    end
end
// CPU reset released at the frame start (beam at line 0): boot code runs without IRQs, a random phase vs vblank kills Pac & Pal's sound CPU.
logic run_ok = 1'b0;
always_ff @(posedge clk) begin
    if (reset)                                         run_ok <= 1'b0;
    else if (ce_pix && hcnt == 9'd383 && vcnt == 9'd263) run_ok <= 1'b1;
end
wire cpu_rst = reset | ~run_ok | (wd_hold != 12'd0);

logic [7:0] latch = 8'h00;
assign flip = mappy ? latch[2] : sp_flip;
logic       irq_m = 1'b0, irq_s = 1'b0, irq_s2 = 1'b0;
always_ff @(posedge clk) begin
    if (cpu_rst) begin
        latch    <= 8'h00;
        sp_flip  <= 1'b0;
        star_ctl <= '0;
    end
    else begin
        if (cs_latch && wr)   latch[a[3:1]]  <= a[0];
        if (scs_latch && swr) latch[sa[3:1]] <= sa[0];
        if (cs_flip && fall_e) sp_flip <= rw ? 1'b1 : do_[0];
        if (cs_scrl && wr)    scroll <= a[10:3];
        if (g_mirq)  latch[1] <= ~a[11];
        if (g_sres)  begin latch[3] <= ~a[11]; latch[5] <= ~a[11]; latch[6] <= ~a[11]; end
        if (g_fres)  latch[4] <= ~a[11];
        if (g_sirq)  latch[0] <= ~sa[13];
        if (g_s2irq) latch[2] <= a2[0];
        if (g_star)  star_ctl[a[1:0]] <= do_;
    end
    if (cpu_rst || !latch[1]) irq_m <= 1'b0;
    else if (vblank_start)    irq_m <= 1'b1;
    if (cpu_rst || !latch[0]) irq_s <= 1'b0;
    else if (vblank_start)    irq_s <= 1'b1;
    if (cpu_rst || !latch[2] || !sub_on) irq_s2 <= 1'b0;
    else if (vblank_start)               irq_s2 <= 1'b1;
end

wire [16:0] main_pk = {1'b0, a}  + rom_ofs[0];
wire [16:0] sub_pk  = {1'b0, sa} + (gaplus ? rom_ofs[2] : rom_ofs[1]);
wire [16:0] sub2_pk = {1'b0, a2} + (gaplus ? rom_ofs[1] : rom_ofs[2]);
wire [16:0] tile_pk = {4'd0, tile_rom_a} + rom_ofs[3];

always_ff @(posedge clk) begin
    case (div[4:3])
        2'd0:    rom_a_addr <= tile_pk;
        2'd1:    rom_a_addr <= sub_pk;
        2'd2:    rom_a_addr <= sub_on ? sub2_pk : main_pk;
        default: rom_a_addr <= main_pk;
    endcase
    rom_b_addr <= {2'd0, spr_rom_a} + rom_ofs[4];
    if (div == 5'd14) sub_rom_q  <= rom_a_q;
    if (div == 5'd22) sub2_rom_q <= rom_a_q;
    if (div == 5'd30) main_rom_q <= rom_a_q;
end

wire [15:0] pa_x  = pause ? hs_address : slot2 ? a2 : a;
wire  [2:0] pa_bk = ram_bank(pa_x, mappy);
wire        pa_we = pause ? hs_write : slot2 ? wr2 : wr;
wire  [7:0] pa_d  = pause ? hs_data_in : slot2 ? do2 : do_;

assign vram_aa = mappy ? pa_x[11:0] : {1'b0, pa_x[10:0]};
assign vram_da = pa_d;
assign vram_wa = pa_we && pa_bk == 3'd0;
genvar k;
generate
    for (k = 0; k < 3; k = k + 1) begin : g_wram
        assign wram_aa[k] = pa_x[10:0];
        assign wram_da[k] = pa_d;
        assign wram_wa[k] = pa_we && pa_bk == 3'(k + 1);
    end
endgenerate

always_comb begin
    case (pa_bk)
        3'd0:    hs_data_out = vram_qa;
        3'd1:    hs_data_out = wram_qa[0];
        3'd2:    hs_data_out = wram_qa[1];
        3'd3:    hs_data_out = wram_qa[2];
        default: hs_data_out = 8'hFF;
    endcase
end

wire   slot2s  = slot2 && phozon;
assign sram_aa = slot2s ? a2[9:0] : a[9:0];
assign sram_da = slot2s ? do2 : do_;
assign sram_wa = slot2s ? s2_sram && wr2 : cs_sram && wr;
assign sram_ab = sa[9:0];
assign sram_db = sdo;
assign sram_wb = scs_sram && swr;

assign xram_aa = a2[10:0];
assign xram_da = do2;
assign xram_wa = s2_xram && wr2;

logic [10:0] smp_div = 11'd0;
always_ff @(posedge clk) smp_div <= smp_div + 11'd1;
assign wsg15_0_smp = smp_div == 11'd0 && !pause;

wire wsg_mw = cs_sram && wr && a[9:6] == 4'd0;
wire wsg_2w = s2_sram && wr2 && a2[9:6] == 4'd0;
assign wsg15_0_i.sound_en = latch[3];
assign wsg15_0_i.dac_mode = (mappy || phozon || gaplus) ? 2'd1 : 2'd0;
// 15XX register writes are snooped from every CPU; never on the same clock (E falls at div 31 / 15 / 23).
assign wsg15_0_i.reg_wr   = wsg_mw || wsg_2w || (scs_sram && swr && sa[9:6] == 4'd0);
assign wsg15_0_i.reg_addr = wsg_mw ? a[5:0] : wsg_2w ? a2[5:0] : sa[5:0];
assign wsg15_0_i.reg_din  = wsg_mw ? do_ : wsg_2w ? do2 : sdo;
assign wsg15_0_i.wave_d   = wave_q;

logic [11:0] run_cnt = 12'd0;
always_ff @(posedge clk) begin
    if (vblank_start)                   run_cnt <= 12'd2458;
    else if (run_cnt != 12'd0 && !pause) run_cnt <= run_cnt - 12'd1;
end
wire io_run = run_cnt == 12'd1 && !pause;

wire io_wr0 = cs_io && wr && a[5:4] == 2'd0;
wire io_wr1 = cs_io && wr && a[5:4] == 2'd1;

assign namcoio_0_i.kind    = io_kind0;
assign namcoio_0_i.reset_n = latch[4];
assign namcoio_0_i.run     = io_run;
assign namcoio_0_i.wr      = io_wr0;
assign namcoio_0_i.addr    = a[3:0];
assign namcoio_0_i.din     = do_[3:0];
assign namcoio_0_i.in      = {in_buttons[3:0], in_p2[3:0], in_p1[3:0], in_coins[3:0]};
assign namcoio_1_i.kind    = io_kind1;
assign namcoio_1_i.reset_n = latch[4];
assign namcoio_1_i.run     = io_run;
assign namcoio_1_i.wr      = io_wr1;
assign namcoio_1_i.addr    = a[3:0];
assign namcoio_1_i.din     = do_[3:0];
assign namcoio_1_i.in      = {dsw0[3:0], dsw1[7:4], dsw1[3:0], gaplus ? dsw0[7:4] : namcoio_1_o.out[0] ? dsw2[7:4] : dsw2[3:0]};

logic [15:0][3:0] cio3 = '0;
logic  [7:0] c62 = 8'd0;
always_ff @(posedge clk) c62 <= (c62 == 8'd191) ? 8'd0 : c62 + 8'd1;

wire  [3:0] m62_p0 = n62_0_o.r_out[3:0];
wire  [3:0] m62_p1 = n62_0_o.r_out[7:4];
wire  [2:0] m62_p2 = n62_0_o.r_out[10:8];
wire        m62_gnt = !m62_p2[0];
logic [3:0] m62_p1d = 4'hF;
wire        m62_wr = gaplus && m62_gnt && !m62_p1[3] && m62_p1 != m62_p1d;
always_ff @(posedge clk) begin
    m62_p1d <= m62_p1;
    if (m62_wr) cio3[{1'b0, m62_p1[2:0]}] <= m62_p0;
    if (gaplus && cs_io && wr && a[5:4] == 2'd2) cio3[a[3:0]] <= do_[3:0];
end
wire [7:0] cio3_q = {4'hF, cio3[a[3:0]]};

assign n62_0_i.ena     = gaplus && c62 == 8'd0 && !pause;
assign n62_0_i.reset_n = gaplus && latch[4];
assign n62_0_i.k       = dsw2[3:0];
assign n62_0_i.r_ext   = {!video_vblank, !m62_gnt, 1'b1,
                          4'hF,
                          (m62_gnt && m62_p1[3]) ? cio3[{1'b1, m62_p1[2:0]}] : 4'hF};

logic [7:0] main_di;
always_comb begin
    if      (cs_rom)   main_di = main_rom_q;
    else if (cs_vram)  main_di = vram_qa;
    else if (cs_wram0) main_di = wram_qa[0];
    else if (cs_wram1) main_di = wram_qa[1];
    else if (cs_wram2) main_di = wram_qa[2];
    else if (cs_sram)  main_di = sram_qa;
    else if (cs_io)    main_di = (gaplus && a[5:4] == 2'd2) ? cio3_q : a[5] ? 8'hFF : {4'hF, a[4] ? namcoio_1_o.dout : namcoio_0_o.dout};
    else               main_di = 8'hFF;
end
wire [7:0] sub_di = scs_rom ? sub_rom_q : scs_sram ? sram_qb : 8'hFF;

logic [7:0] sub2_di;
always_comb begin
    if      (s2_rom)          sub2_di = sub2_rom_q;
    else if (bank2 == 3'd0)   sub2_di = vram_qa;
    else if (bank2 == 3'd1)   sub2_di = wram_qa[0];
    else if (bank2 == 3'd2)   sub2_di = wram_qa[1];
    else if (bank2 == 3'd3)   sub2_di = wram_qa[2];
    else if (s2_sram)         sub2_di = sram_qa;
    else if (s2_xram)         sub2_di = xram_qa;
    else                      sub2_di = 8'hFF;
end

assign m6809_0_i.reset_n = ~cpu_rst;
assign m6809_0_i.fall_e  = fall_e;
assign m6809_0_i.fall_q  = fall_q;
assign m6809_0_i.irq_n   = ~irq_m;
assign m6809_0_i.firq_n  = 1'b1;
assign m6809_0_i.nmi_n   = 1'b1;
assign m6809_0_i.d       = main_di;

assign m6809_1_i.reset_n = ~cpu_rst & latch[5];
assign m6809_1_i.fall_e  = sfall_e;
assign m6809_1_i.fall_q  = sfall_q;
assign m6809_1_i.irq_n   = ~irq_s;
assign m6809_1_i.firq_n  = 1'b1;
assign m6809_1_i.nmi_n   = 1'b1;
assign m6809_1_i.d       = sub_di;

assign m6809_2_i.reset_n = ~cpu_rst & latch[6] & sub_on;
assign m6809_2_i.fall_e  = fall_e2;
assign m6809_2_i.fall_q  = fall_q2;
assign m6809_2_i.irq_n   = ~irq_s2;
assign m6809_2_i.firq_n  = 1'b1;
assign m6809_2_i.nmi_n   = 1'b1;
assign m6809_2_i.d       = sub2_di;

/* verilator lint_off UNUSED */
wire unused = ^hcnt | ^vcnt | ^m6809_0_o.lic | ^m6809_1_o.lic | ^m6809_2_o.lic | ^namcoio_0_o.out | ^namcoio_1_o.out[7:1];
/* verilator lint_on UNUSED */

endmodule
