//============================================================================
//
//  Sky Kid / Dragon Buster board (MAME namco/skykid.cpp): MC6809E main CPU, HD63701 MCU (I/O + sound driver),
//  CUS30 8-voice waveform sound (RAM shared by both CPUs), video in skykid_video.sv.
//  Copyright (C) 2026 Rodimus
//
//  Main CPU (pool m6809_0, E at div 31): 0000-1FFF ROM bank (two 8K pages of region 10000), 2000-2FFF background
//    RAM (pool vram), 4000-47FF text RAM (pool xram), 4800-5FFF sprite RAM (pool wram 0-2), 6000-60FF scroll y and
//    6200-63FF scroll x (= the written address), 6800-6BFF CUS30, 7000 / 7800 IRQ enable (data in A11), 7800 read
//    watchdog (MAME: none), 8000 / 8800 MCU run / reset, 9000 / 9800 ROM bank 1 / 0, A000-A001 priority (data) +
//    flip (A0), 8000-FFFF ROM.
//  MCU (pool mcu6801, HD63701 mode 6, crystal 6.144 MHz = div / 8): 1000-13FF CUS30, 2000-3FFF watchdog (ignored),
//    4000 / 6000 IRQ enable (data in A13), 8000-9FFF sub ROM and F000-FFFF internal ROM (dispatcher MCU ROM block),
//    C000-C7FF RAM (pool sram). Port 1: input select (write 011x xsss) and the selected input (MAME inputport_r).
//  CUS30 RAM: the main CPU owns it at div 28-31 (its E falls at 31), the MCU (clocked at div 3 / 11 / 19 / 27) the
//    rest of the time, so each sees its own data at its sampling clock.
//  ROM store port A: slot 0 text tiles, slot 1 background tiles, slots 2-3 main CPU (captured at div 30).
//
//============================================================================

module skykid_board
(
    input  logic        clk,                    // 49.152 MHz
    input  logic        reset,
    input  logic        pause,
    input  logic [4:0][16:0] rom_ofs,           // 0 maincpu, 1 chars, 3 tiles, 4 sprites
    input  logic        crt_flip,
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    input  logic  [7:0] in_system,              // MAME ports (active low): SYSTEM, P1, P2, BUTTON2, DSWA, DSWB
    input  logic  [7:0] in_p1,
    input  logic  [7:0] in_p2,
    input  logic  [7:0] in_button2,
    input  logic  [7:0] dswa,
    input  logic  [7:0] dswb,
    input  logic  [7:0] dsw2,                   // bit 1: Dragon Buster Cabinet DIP (MAME: in BUTTON2; gen_mra moves it here)

    output logic        ce_pix,
    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,

    // pools (rtl/namco6809_board.sv)
    output chip_pool_pkg::m6809r_i_t  m6809_0_i,
    input  chip_pool_pkg::m6809r_o_t  m6809_0_o,

    output logic        mcu_rst,
    output logic        mcu_cen,
    output logic        mcu_irq,
    output logic  [7:0] mcu_xdin,
    output logic  [7:0] mcu_p1_din,
    input  logic [15:0] mcu_addr,
    input  logic  [7:0] mcu_dout,
    input  logic        mcu_wr,
    input  logic        mcu_xcs,
    input  logic  [7:0] mcu_p1_dout,
    input  logic  [7:0] mcu_rom_q,              // MCU ROM block at mcu_addr (sub ROM / internal ROM)

    output logic        c30_cen,
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

    output logic [16:0] rom_a_addr,
    input  logic  [7:0] rom_a_q,
    output logic [16:0] rom_b_addr,
    input  logic  [7:0] rom_b_q,
    output logic [10:0] prom_a_addr,
    input  logic  [7:0] prom_a_q,
    output logic [10:0] prom_b_addr,
    input  logic  [7:0] prom_b_q,

    output logic [11:0] vram_aa,
    output logic  [7:0] vram_da,
    output logic        vram_wa,
    input  logic  [7:0] vram_qa,
    output logic [11:0] vram_ab,
    input  logic  [7:0] vram_qb,
    output logic [2:0][10:0] wram_aa,
    output logic [2:0] [7:0] wram_da,
    output logic [2:0]       wram_wa,
    input  logic [2:0] [7:0] wram_qa,
    output logic      [10:0] wram_ab,
    input  logic [2:0] [7:0] wram_qb,
    output logic [10:0] xram_aa,
    output logic  [7:0] xram_da,
    output logic        xram_wa,
    input  logic  [7:0] xram_qa,
    output logic [10:0] xram_ab,
    input  logic  [7:0] xram_qb,
    output logic [10:0] sram_aa,
    output logic  [7:0] sram_da,
    output logic        sram_wa,
    input  logic  [7:0] sram_qa,
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

/////////////////////////////  Clocks  /////////////////////////////

logic [4:0] div = 5'd0;                         // never reset: hcnt[1:0] = div[4:3] (ROM port-A slots)
always_ff @(posedge clk) div <= div + 5'd1;

logic [1:0] pause_d = 2'b00;                    // hiscore borrows the RAM ports while paused (+2 clocks)
always_ff @(posedge clk) pause_d <= {pause_d[0], pause};
wire pause_x = pause | (|pause_d);

wire fall_q = (div == 5'd23) & ~pause_x;        // main CPU, 1.536 MHz
wire fall_e = (div == 5'd31) & ~pause_x;
assign mcu_cen  = (div[2:0] == 3'd3) & ~pause_x;    // HD63701 crystal 6.144 MHz (E = 1.536 MHz)
assign c30_cen  = (div[3:0] == 4'd5) & ~pause_x;    // CUS30 3.072 MHz (jtcus30: 48 kHz voice steps)
assign ce_pix   = div[2:0] == 3'd7;

/////////////////////////////  Video  /////////////////////////////

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

/////////////////////////////  Main CPU  /////////////////////////////

wire [15:0] a   = m6809_0_o.a;
wire  [7:0] do_ = m6809_0_o.dout;
wire        rw  = m6809_0_o.rw;
wire        wr  = fall_e & ~rw;

// RAM decode for an address (CPU or hiscore): 0 background, 1 text, 2-4 sprite banks, 7 none
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
wire cs_pri   = a[15:1] == 15'h5000;            // A000-A001

/////////////////////////////  Control, IRQs, reset  /////////////////////////////

// Reset release synchronised to the frame start (as the Super Pac board: MAME starts with the beam on line 0)
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
        mcu_run   <= 1'b1;                       // MAME: the MCU runs from power-on until 8800 is written
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

/////////////////////////////  ROM store  /////////////////////////////

// main CPU region address: 0000-1FFF = bank page at 10000 / 12000, 8000-FFFF as is
wire [16:0] main_ra = cs_rbank ? {3'b100, rbank, a[12:0]} : {1'b0, a};
wire [16:0] main_pk = main_ra + rom_ofs[0];
wire [16:0] txt_pk  = {4'd0, txt_rom_a} + rom_ofs[1];
wire [16:0] bg_pk   = {4'd0, bg_rom_a} + rom_ofs[3];
logic [7:0] main_rom_q;

always_ff @(posedge clk) begin
    case (div[4:3])
        2'd0:    rom_a_addr <= txt_pk;          // video reads at div 6 / 14
        2'd1:    rom_a_addr <= bg_pk;
        default: rom_a_addr <= main_pk;
    endcase
    rom_b_addr <= {2'd0, spr_rom_a} + rom_ofs[4];
    if (div == 5'd30) main_rom_q <= rom_a_q;
end

/////////////////////////////  RAMs  /////////////////////////////

// port A: main CPU, or the hiscore system while paused
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

// MCU RAM C000-C7FF
wire mcu_ram = mcu_addr[15:11] == 5'b11000;
assign sram_aa = mcu_addr[10:0];
assign sram_da = mcu_dout;
assign sram_wa = mcu_xcs && mcu_wr && mcu_ram;

/////////////////////////////  CUS30  /////////////////////////////

assign c30_bsel  = div[4:2] == 3'b111;          // main CPU at div 28-31
assign c30_bcs   = cs_c30;
assign c30_brnw  = rw;
assign c30_baddr = a[9:0];
assign c30_bdout = do_;
assign c30_scs   = mcu_xcs && mcu_addr[15:10] == 6'b000100;
assign c30_srnw  = ~mcu_wr;
assign c30_saddr = mcu_addr;
assign c30_sdout = mcu_dout;

/////////////////////////////  MCU  /////////////////////////////

assign mcu_rst = cpu_rst | ~mcu_run;
assign mcu_irq = irq_u;

always_comb begin
    if (mcu_addr[15:10] == 6'b000100)    mcu_xdin = c30_xdin;
    else if (mcu_addr[15:13] == 3'b100)  mcu_xdin = mcu_rom_q;
    else if (mcu_ram)                    mcu_xdin = sram_qa;
    else                                 mcu_xdin = 8'hFF;
end

// port 1: written 011x xsss selects the input (11 0x xxxx = coin lockout / counters, not modelled)
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

/////////////////////////////  CPU bus  /////////////////////////////

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
