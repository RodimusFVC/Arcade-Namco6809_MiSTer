//  Based on MAME skykid.cpp (Manuel Abadia, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module skykid_board #(parameter int RAM_BLOCKS = 6)
(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    input  logic [4:0][16:0] rom_ofs,
    input  logic        crt_flip,
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    input  logic  [7:0] in_system,
    input  logic  [7:0] in_p1,
    input  logic  [7:0] in_p2,
    input  logic  [7:0] in_button2,
    input  logic  [7:0] dswa,
    input  logic  [7:0] dswb,
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

    output chip_pool_pkg::hd63701_i_t mcu_0_i,
    input  chip_pool_pkg::hd63701_o_t mcu_0_o,
    input  logic  [7:0] mcu_rom_q,

    output chip_pool_pkg::cus30_i_t   cus30_0_i,
    input  chip_pool_pkg::cus30_o_t   cus30_0_o,

    output logic [16:0] rom_a_addr,
    input  logic  [7:0] rom_a_q,
    output logic [16:0] rom_b_addr,
    input  logic  [7:0] rom_b_q,
    output logic [10:0] prom_a_addr,
    input  logic  [7:0] prom_a_q,
    output logic [10:0] prom_b_addr,
    input  logic  [7:0] prom_b_q,

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

logic        mcu_rst, mcu_cen, mcu_irq, mcu_wr, mcu_xcs;
logic  [7:0] mcu_xdin, mcu_p1_din, mcu_dout, mcu_p1_dout;
logic [15:0] mcu_addr;
assign mcu_0_i.rst     = mcu_rst;
assign mcu_0_i.cen     = mcu_cen;
assign mcu_0_i.cen_tmr = mcu_cen;
assign mcu_0_i.irq     = mcu_irq;
assign mcu_0_i.nmi     = 1'b0;
assign mcu_0_i.xdin    = mcu_xdin;
assign mcu_0_i.p1_din  = mcu_p1_din;
assign mcu_0_i.p2_din  = 5'h1F;
assign mcu_0_i.p3_din  = 8'hFF;
assign mcu_0_i.p4_din  = 8'hFF;
assign mcu_addr    = mcu_0_o.addr;
assign mcu_dout    = mcu_0_o.dout;
assign mcu_wr      = mcu_0_o.wr;
assign mcu_xcs     = mcu_0_o.x_cs;
assign mcu_p1_dout = mcu_0_o.p1_dout;

logic        c30_cen, c30_bsel, c30_bcs, c30_brnw, c30_scs, c30_srnw;
logic  [9:0] c30_baddr;
logic  [7:0] c30_bdout, c30_sdout, c30_xdin;
logic [15:0] c30_saddr;
assign cus30_0_i.rst   = 1'b0;
assign cus30_0_i.cen   = c30_cen;
assign cus30_0_i.bsel  = c30_bsel;
assign cus30_0_i.bcs   = c30_bcs;
assign cus30_0_i.brnw  = c30_brnw;
assign cus30_0_i.baddr = c30_baddr;
assign cus30_0_i.bdout = c30_bdout;
assign cus30_0_i.scs   = c30_scs;
assign cus30_0_i.srnw  = c30_srnw;
assign cus30_0_i.saddr = c30_saddr;
assign cus30_0_i.sdout = c30_sdout;
assign c30_xdin = cus30_0_o.xdin;

logic [11:0] vram_aa, vram_ab;
logic  [7:0] vram_da, vram_qa, vram_qb;
logic        vram_wa;
logic [2:0][10:0] wram_aa;
logic [2:0] [7:0] wram_da, wram_qa, wram_qb;
logic [2:0]       wram_wa;
logic      [10:0] wram_ab;
logic [10:0] xram_aa, xram_ab;
logic  [7:0] xram_da, xram_qa, xram_qb;
logic        xram_wa;
logic [10:0] sram_aa;
logic  [7:0] sram_da, sram_qa;
logic        sram_wa;

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
assign pr_i[4].b_addr = {5'd0, xram_ab};      assign pr_i[4].b_d = 8'd0;        assign pr_i[4].b_we = 1'b0;
assign xram_qa = pr_o[4].a_q;                 assign xram_qb = pr_o[4].b_q;
assign pr_i[5].a_addr = {5'd0, sram_aa};      assign pr_i[5].a_d = sram_da;     assign pr_i[5].a_we = sram_wa;
assign pr_i[5].b_addr = 16'd0;                assign pr_i[5].b_d = 8'd0;        assign pr_i[5].b_we = 1'b0;
assign sram_qa = pr_o[5].a_q;

// div is never reset: the video counters rely on hcnt[1:0] = div[4:3] (ROM port-A slots).
logic [4:0] div = 5'd0;
always_ff @(posedge clk) div <= div + 5'd1;

// The hiscore borrows the CPU RAM ports while paused; the CPUs stay held 2 clocks longer so their first read sees their own address.
logic [1:0] pause_d = 2'b00;
always_ff @(posedge clk) pause_d <= {pause_d[0], pause};
wire pause_x = pause | (|pause_d);

wire fall_q = (div == 5'd23) & ~pause_x;
wire fall_e = (div == 5'd31) & ~pause_x;
assign mcu_cen  = (div[2:0] == 3'd3) & ~pause_x;
assign c30_cen  = (div[3:0] == 4'd5) & ~pause_x;
assign ce_pix   = div[2:0] == 3'd7;

logic        vblank_start;
logic        flip = 1'b0;
logic  [7:0] pri = 8'd0;
logic  [8:0] scroll_x = 9'd0;
logic  [7:0] scroll_y = 8'd0;
logic [12:0] txt_rom_a, bg_rom_a;
logic [14:0] spr_rom_a;
logic  [8:0] hcnt, vcnt;

skykid_video video
(
    .clk(clk), .div(div), .flip(flip), .crt_flip(crt_flip), .scroll_x(scroll_x), .scroll_y(scroll_y), .pri(pri),
    .h_adj(h_adj), .v_adj(v_adj),
    .hcnt(hcnt), .vcnt(vcnt), .vblank_start(vblank_start),
    .tx_a(xram_ab), .tx_q(xram_qb), .bg_a(vram_ab), .bg_q(vram_qb),
    .spr_a(wram_ab), .spr_q0(wram_qb[0]), .spr_q1(wram_qb[1]), .spr_q2(wram_qb[2]),
    .txt_rom_a(txt_rom_a), .bg_rom_a(bg_rom_a), .tile_rom_q(rom_a_q),
    .spr_rom_a(spr_rom_a), .spr_rom_q(rom_b_q),
    .clut_a(prom_b_addr), .clut_q(prom_b_q), .slut_a(prom_a_addr), .slut_q(prom_a_q),
    .lbuf_wa(lbuf_aa), .lbuf_wd(lbuf_da), .lbuf_we(lbuf_wa), .lbuf_ra(lbuf_ab), .lbuf_rq(lbuf_qb),
    .r(video_r), .g(video_g), .b(video_b), .hs(video_hs), .vs(video_vs),
    .hblank(video_hblank), .vblank(video_vblank)
);

wire [15:0] a   = m6809_0_o.a;
wire  [7:0] do_ = m6809_0_o.dout;
wire        rw  = m6809_0_o.rw;
wire        wr  = fall_e & ~rw;

function automatic [2:0] ram_bank(input [15:0] x);
    if (x[15:12] == 4'h2) ram_bank = 3'd0;
    else case (x[15:11])
        5'b01000: ram_bank = 3'd1;
        5'b01001: ram_bank = 3'd2;
        5'b01010: ram_bank = 3'd3;
        5'b01011: ram_bank = 3'd4;
        default:  ram_bank = 3'd7;
    endcase
endfunction

wire [2:0] bank   = ram_bank(a);
wire cs_rbank = a[15:13] == 3'b000;
wire cs_rom   = a[15];
wire cs_scy   = a[15:8] == 8'h60;
wire cs_scx   = a[15:9] == 7'b0110001;
wire cs_c30   = a[15:10] == 6'b011010;
wire cs_irq   = a[15:12] == 4'h7;
wire cs_mres  = a[15:12] == 4'h8;
wire cs_bank  = a[15:12] == 4'h9;
wire cs_pri   = a[15:1] == 15'h5000;

// CPU reset released at the frame start (beam at line 0): boot code runs without IRQs, a random phase vs vblank kills Pac & Pal's sound CPU.
logic run_ok = 1'b0;
always_ff @(posedge clk) begin
    if (reset)                                           run_ok <= 1'b0;
    else if (ce_pix && hcnt == 9'd383 && vcnt == 9'd263) run_ok <= 1'b1;
end
wire cpu_rst = reset | ~run_ok;

logic main_mask = 1'b0, mcu_mask = 1'b0, mcu_run = 1'b1, rbank = 1'b0;
logic irq_m = 1'b0, irq_u = 1'b0;
wire  mcu_irqw = mcu_xcs && mcu_wr && mcu_addr[15:14] == 2'b01 && mcu_cen;
always_ff @(posedge clk) begin
    if (cpu_rst) begin
        main_mask <= 1'b0;
        mcu_mask  <= 1'b0;
        mcu_run   <= 1'b1;
        rbank     <= 1'b0;
        flip      <= 1'b0;
        pri       <= 8'd0;
    end
    else begin
        if (cs_irq && wr)  main_mask <= ~a[11];
        if (cs_mres && wr) mcu_run   <= ~a[11];
        if (cs_bank && wr) rbank     <= ~a[11];
        if (cs_pri && wr)  begin pri <= do_; flip <= a[0]; end
        if (cs_scx && wr)  scroll_x  <= a[8:0];
        if (cs_scy && wr)  scroll_y  <= a[7:0];
        if (mcu_irqw)      mcu_mask  <= ~mcu_addr[13];
    end
    if (cpu_rst || !main_mask) irq_m <= 1'b0;
    else if (vblank_start)     irq_m <= 1'b1;
    if (cpu_rst || !mcu_mask)  irq_u <= 1'b0;
    else if (vblank_start)     irq_u <= 1'b1;
end

wire [16:0] main_ra = cs_rbank ? {3'b100, rbank, a[12:0]} : {1'b0, a};
wire [16:0] main_pk = main_ra + rom_ofs[0];
wire [16:0] txt_pk  = {4'd0, txt_rom_a} + rom_ofs[1];
wire [16:0] bg_pk   = {4'd0, bg_rom_a} + rom_ofs[3];
logic [7:0] main_rom_q;

always_ff @(posedge clk) begin
    case (div[4:3])
        2'd0:    rom_a_addr <= txt_pk;
        2'd1:    rom_a_addr <= bg_pk;
        default: rom_a_addr <= main_pk;
    endcase
    rom_b_addr <= {2'd0, spr_rom_a} + rom_ofs[4];
    if (div == 5'd30) main_rom_q <= rom_a_q;
end

wire [15:0] pa_x  = pause ? hs_address : a;
wire  [2:0] pa_bk = ram_bank(pa_x);
wire        pa_we = pause ? hs_write : wr;
wire  [7:0] pa_d  = pause ? hs_data_in : do_;

assign vram_aa = pa_x[11:0];
assign vram_da = pa_d;
assign vram_wa = pa_we && pa_bk == 3'd0;
assign xram_aa = pa_x[10:0];
assign xram_da = pa_d;
assign xram_wa = pa_we && pa_bk == 3'd1;
genvar k;
generate
    for (k = 0; k < 3; k = k + 1) begin : g_wram
        assign wram_aa[k] = pa_x[10:0];
        assign wram_da[k] = pa_d;
        assign wram_wa[k] = pa_we && pa_bk == 3'(k + 2);
    end
endgenerate

always_comb begin
    case (pa_bk)
        3'd0:    hs_data_out = vram_qa;
        3'd1:    hs_data_out = xram_qa;
        3'd2:    hs_data_out = wram_qa[0];
        3'd3:    hs_data_out = wram_qa[1];
        3'd4:    hs_data_out = wram_qa[2];
        default: hs_data_out = 8'hFF;
    endcase
end

wire mcu_ram = mcu_addr[15:11] == 5'b11000;
assign sram_aa = mcu_addr[10:0];
assign sram_da = mcu_dout;
assign sram_wa = mcu_xcs && mcu_wr && mcu_ram;

assign c30_bsel  = div[4:2] == 3'b111;
assign c30_bcs   = cs_c30;
assign c30_brnw  = rw;
assign c30_baddr = a[9:0];
assign c30_bdout = do_;
assign c30_scs   = mcu_xcs && mcu_addr[15:10] == 6'b000100;
assign c30_srnw  = ~mcu_wr;
assign c30_saddr = mcu_addr;
assign c30_sdout = mcu_dout;

assign mcu_rst = cpu_rst | ~mcu_run;
assign mcu_irq = irq_u;

always_comb begin
    if (mcu_addr[15:10] == 6'b000100)    mcu_xdin = c30_xdin;
    else if (mcu_addr[15:13] == 3'b100)  mcu_xdin = mcu_rom_q;
    else if (mcu_ram)                    mcu_xdin = sram_qa;
    else                                 mcu_xdin = 8'hFF;
end

logic [2:0] in_sel = 3'd0;
always_ff @(posedge clk) if (mcu_p1_dout[7:5] == 3'b011) in_sel <= mcu_p1_dout[2:0];
always_comb begin
    case (in_sel)
        3'd0:    mcu_p1_din = {3'd0, dswb[7:3]};
        3'd1:    mcu_p1_din = {3'd0, dswb[2:0], dswa[7:6]};
        3'd2:    mcu_p1_din = {3'd0, dswa[5:1]};
        3'd3:    mcu_p1_din = {3'd0, dswa[0], in_button2[3:2], dsw2[1], in_button2[0]};
        3'd4:    mcu_p1_din = in_system;
        3'd5:    mcu_p1_din = in_p2;
        3'd6:    mcu_p1_din = in_p1;
        default: mcu_p1_din = 8'hFF;
    endcase
end

logic [7:0] main_di;
always_comb begin
    if      (cs_rbank || cs_rom) main_di = main_rom_q;
    else if (bank == 3'd0)       main_di = vram_qa;
    else if (bank == 3'd1)       main_di = xram_qa;
    else if (bank == 3'd2)       main_di = wram_qa[0];
    else if (bank == 3'd3)       main_di = wram_qa[1];
    else if (bank == 3'd4)       main_di = wram_qa[2];
    else if (cs_c30)             main_di = c30_xdin;
    else                         main_di = 8'hFF;
end

assign m6809_0_i.reset_n = ~cpu_rst;
assign m6809_0_i.fall_e  = fall_e;
assign m6809_0_i.fall_q  = fall_q;
assign m6809_0_i.irq_n   = ~irq_m;
assign m6809_0_i.firq_n  = 1'b1;
assign m6809_0_i.nmi_n   = 1'b1;
assign m6809_0_i.d       = main_di;

/* verilator lint_off UNUSED */
wire unused = ^rom_ofs[2] ^ m6809_0_o.lic ^ ^mcu_p1_dout[4:3] ^ ^dsw2[7:2] ^ dsw2[0] ^ in_button2[1];
/* verilator lint_on UNUSED */

endmodule
