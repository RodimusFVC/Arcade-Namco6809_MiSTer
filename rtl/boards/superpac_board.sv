//============================================================================
//
//  Namco Super Pac-Man board (CPU A084-91434 / video A084-91435): superpac, superpacm (variant 0, mappy = 0)
//  Namco Mappy board (CPU A084-91479 / video A084-91480): mappy, mappyj (variant 2, mappy = 1)
//  Copyright (C) 2026 Rodimus
//
//  Written from the Super Pac-Man schematics (Bally Midway manual section 9), the Mappy schematics and MAME
//  namco/mappy.cpp (Nicola Salmoria). The Mappy board is the Super Pac-Man board with more tilemap RAM, the 17XX
//  scroll, 4bpp sprites, flip on the LS259 and the 99XX DAC; every difference is gated by mappy.
//  Main and sound CPU: MC6809E @ 1.536 MHz (pool m6809_0 / m6809_1, mc6809is), the sound CPU on the opposite
//  E phase. 15XX WSG, two custom I/O chips, packed ROM store, colour PROMs and RAMs: pools in the dispatcher.
//
//  Main CPU (PALs SPC-5 / SPC-6; MAME maps)                        Sound CPU (both):
//               Super Pac                  Mappy                     0000-03FF  sound RAM (mirrored to 1FFF)
//    tilemap    0000-07FF                  0000-0FFF                 2000-200F  LS259 (mirrored to 3FFF)
//    work RAM   0800 / 1000 / 1800 (2K     1000 / 1800 / 2000        E000-FFFF  program ROM 1K
//               each, sprite registers at x780-x7FF of each)
//    flip       2000 (read sets it)        LS259 Q2
//    scroll     -                          3800-3FFF (write: scroll = A10-A3)
//    4000-43FF  sound RAM 3K/3L (15XX registers 00-3F), shared with the sound CPU, mirrored to 47FF
//    4800-481F  16XX: I/O chip #0 (4800), #1 (4810)
//    5000-500F  LS259 2M: bit = A3-A1, data = A0
//    8000       watchdog reset (write)
//    ROM        A000-FFFF                  8000-FFFF
//  LS259 2M: Q0 sound CPU IRQ enable, Q1 main IRQ enable, Q2 flip (Mappy), Q3 SOUND ON, Q4 I/O chips run,
//  Q5 sound CPU run.
//  ROM store port A is time-sliced on div[4:3]: 0 tiles (video), 1 sound CPU, 2-3 main CPU.
//
//============================================================================

module superpac_board
(
    input  logic        clk,                    // 49.152 MHz
    input  logic        reset,
    input  logic        pause,
    input  logic        mappy,                  // Mappy board deltas
    input  logic  [1:0] io_kind0,
    input  logic  [1:0] io_kind1,
    input  logic [4:0][16:0] rom_ofs,           // packed-store offset per region: 0 maincpu, 1 sub, 3 tiles, 4 sprites
    input  logic        crt_flip,
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    input  logic  [7:0] in_coins,               // MAME ports (active low): COINS, P1, P2, BUTTONS, DSW0-2
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

    // pools (rtl/namco6809_board.sv)
    output chip_pool_pkg::m6809r_i_t  m6809_0_i,
    input  chip_pool_pkg::m6809r_o_t  m6809_0_o,
    output chip_pool_pkg::m6809r_i_t  m6809_1_i,
    input  chip_pool_pkg::m6809r_o_t  m6809_1_o,
    output chip_pool_pkg::wsg15_i_t   wsg_i,
    output logic                      wsg_smp,
    output chip_pool_pkg::namcoio_i_t io0_i,
    input  chip_pool_pkg::namcoio_o_t io0_o,
    output chip_pool_pkg::namcoio_i_t io1_i,
    input  chip_pool_pkg::namcoio_o_t io1_o,

    output logic [16:0] rom_a_addr,             // packed ROM store
    input  logic  [7:0] rom_a_q,
    output logic [16:0] rom_b_addr,
    input  logic  [7:0] rom_b_q,
    output logic [10:0] prom_a_addr,            // colour PROM window
    input  logic  [7:0] prom_a_q,
    output logic [10:0] prom_b_addr,
    input  logic  [7:0] prom_b_q,
    input  logic  [3:0] wave_q,                 // 15XX waveform PROM at wsg_o.wave_a (dispatcher)

    output logic [11:0] vram_aa,                // RAM pool: port A = CPU / hiscore, port B = video / sound CPU
    output logic  [7:0] vram_da,
    output logic        vram_wa,
    input  logic  [7:0] vram_qa,
    output logic [11:0] vram_ab,
    input  logic  [7:0] vram_qb,
    output logic [2:0][10:0] wram_aa,           // work RAMs 0800 / 1000 / 1800
    output logic [2:0] [7:0] wram_da,
    output logic [2:0]       wram_wa,
    input  logic [2:0] [7:0] wram_qa,
    output logic      [10:0] wram_ab,
    input  logic [2:0] [7:0] wram_qb,
    output logic  [9:0] sram_aa,
    output logic  [7:0] sram_da,
    output logic        sram_wa,
    input  logic  [7:0] sram_qa,
    output logic  [9:0] sram_ab,
    output logic  [7:0] sram_db,
    output logic        sram_wb,
    input  logic  [7:0] sram_qb,
    output logic  [9:0] lbuf_aa,
    output logic  [7:0] lbuf_da,
    output logic        lbuf_wa,
    output logic  [9:0] lbuf_ab,
    input  logic  [7:0] lbuf_qb,

    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write
);

/////////////////////////////  Clocks  /////////////////////////////

// 18.432 MHz / 3 = 6.144 MHz pixel = 49.152 / 8; 6809 E = 1.536 MHz = 49.152 / 32. Never reset: the video
// counters rely on hcnt[1:0] = div[4:3] (ROM port-A slots).
logic [4:0] div = 5'd0;
always_ff @(posedge clk) div <= div + 5'd1;

// The hiscore system borrows the CPU RAM ports while paused; pause_x holds the CPUs two clocks longer so their
// first read after a pause sees their own address again.
logic [1:0] pause_d = 2'b00;
always_ff @(posedge clk) pause_d <= {pause_d[0], pause};
wire pause_x = pause | (|pause_d);

wire fall_q  = (div == 5'd23) & ~pause_x;      // main CPU
wire fall_e  = (div == 5'd31) & ~pause_x;
wire sfall_q = (div == 5'd7)  & ~pause_x;      // sound CPU: opposite E phase
wire sfall_e = (div == 5'd15) & ~pause_x;

/////////////////////////////  Video  /////////////////////////////

logic        vblank_start;
logic        sp_flip = 1'b0;
logic  [7:0] scroll = 8'd0;
wire         flip;
logic [11:0] tile_rom_a;
logic [13:0] spr_rom_a;
logic  [8:0] clut_a;
logic  [7:0] slut_a;
logic [11:0] vid_vram_a;
logic [10:0] vid_spr_a;
logic  [9:0] v_lbuf_wa, v_lbuf_ra;
logic  [7:0] v_lbuf_wd;
logic        v_lbuf_we;
logic  [8:0] hcnt, vcnt;
logic  [7:0] main_rom_q, sub_rom_q;

assign ce_pix = div[2:0] == 3'd7;

superpac_video video
(
    .clk(clk), .div(div), .mappy(mappy), .flip(flip), .crt_flip(crt_flip), .scroll(scroll), .h_adj(h_adj), .v_adj(v_adj),
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
assign prom_b_addr = {2'b00, clut_a};
assign prom_a_addr = 11'h120 + {3'b000, slut_a};

/////////////////////////////  Main CPU  /////////////////////////////

wire [15:0] a  = m6809_0_o.a;
wire  [7:0] do_ = m6809_0_o.dout;
wire        rw = m6809_0_o.rw;
wire        wr = fall_e & ~rw;

// RAM decode for an address (CPU or hiscore): bank 0 = tilemap RAM, 1-3 = work RAMs, 7 = none
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
wire cs_flip  = !mappy && a[15:11] == 5'b00100;
wire cs_scrl  = mappy && a[15:11] == 5'b00111;
wire cs_sram  = a[15:11] == 5'b01000;
wire cs_io    = a[15:11] == 5'b01001;
wire cs_latch = a[15:11] == 5'b01010;
wire cs_wdr   = a[15:11] == 5'b10000;
wire cs_rom   = mappy ? a[15] : a[15:13] >= 3'b101;

/////////////////////////////  Sound CPU  /////////////////////////////

wire [15:0] sa  = m6809_1_o.a;
wire  [7:0] sdo = m6809_1_o.dout;
wire        srw = m6809_1_o.rw;
wire        swr = sfall_e & ~srw;

wire scs_sram  = sa[15:13] == 3'b000;
wire scs_latch = sa[15:13] == 3'b001;
wire scs_rom   = sa[15:13] == 3'b111;

/////////////////////////////  Watchdog, LS259, IRQs, flip  /////////////////////////////

// Watchdog (MAME: 8 vblanks without a write to 8000 reset the machine); frozen while paused. The reset is
// held for 4096 clocks (128 E cycles).
logic  [3:0] wd_cnt  = 4'd0;
logic [11:0] wd_hold = 12'd0;
always_ff @(posedge clk) begin
    if (reset) begin
        wd_cnt  <= 4'd0;
        wd_hold <= 12'd0;
    end
    else begin
        if (wd_hold != 12'd0) wd_hold <= wd_hold - 12'd1;
        if (cs_wdr && wr) wd_cnt <= 4'd0;
        else if (vblank_start && !pause) begin
            if (wd_cnt == 4'd7) begin wd_cnt <= 4'd0; wd_hold <= 12'hFFF; end
            else wd_cnt <= wd_cnt + 4'd1;
        end
    end
end
// Reset release synchronised to the frame start (beam at line 0, as MAME's power-on): the boot code runs without
// interrupts, so the main CPU's phase against vblank is set here once. A random phase let Pac & Pal's main CPU clear
// the shared RAM (43F0-43FF) inside the sound CPU's 1 ms vblank handler, wiping its RTI frame (sim 2026-10-25).
logic run_ok = 1'b0;
always_ff @(posedge clk) begin
    if (reset)                                         run_ok <= 1'b0;
    else if (ce_pix && hcnt == 9'd383 && vcnt == 9'd263) run_ok <= 1'b1;
end
wire cpu_rst = reset | ~run_ok | (wd_hold != 12'd0);

logic [7:0] latch = 8'h00;
assign flip = mappy ? latch[2] : sp_flip;
logic       irq_m = 1'b0, irq_s = 1'b0;
always_ff @(posedge clk) begin
    if (cpu_rst) begin
        latch   <= 8'h00;
        sp_flip <= 1'b0;
    end
    else begin
        if (cs_latch && wr)   latch[a[3:1]]  <= a[0];
        if (scs_latch && swr) latch[sa[3:1]] <= sa[0];
        if (cs_flip && fall_e) sp_flip <= rw ? 1'b1 : do_[0];
        if (cs_scrl && wr)    scroll <= a[10:3];
    end
    // IRQ on vblank while enabled, held until the enable bit is cleared
    if (cpu_rst || !latch[1]) irq_m <= 1'b0;
    else if (vblank_start)    irq_m <= 1'b1;
    if (cpu_rst || !latch[0]) irq_s <= 1'b0;
    else if (vblank_start)    irq_s <= 1'b1;
end

/////////////////////////////  ROM store port A slots  /////////////////////////////

wire [16:0] main_pk = {1'b0, a}  + rom_ofs[0];
wire [16:0] sub_pk  = {1'b0, sa} + rom_ofs[1];
wire [16:0] tile_pk = {5'd0, tile_rom_a} + rom_ofs[3];

always_ff @(posedge clk) begin
    case (div[4:3])
        2'd0:    rom_a_addr <= tile_pk;        // video reads at div 6
        2'd1:    rom_a_addr <= sub_pk;
        default: rom_a_addr <= main_pk;
    endcase
    rom_b_addr <= {3'd0, spr_rom_a} + rom_ofs[4];
    if (div == 5'd14) sub_rom_q  <= rom_a_q;
    if (div == 5'd30) main_rom_q <= rom_a_q;
end

/////////////////////////////  RAMs  /////////////////////////////

// port A: main CPU, or the hiscore system while paused
wire [15:0] pa_x  = pause ? hs_address : a;
wire  [2:0] pa_bk = ram_bank(pa_x, mappy);
wire        pa_we = pause ? hs_write : wr;
wire  [7:0] pa_d  = pause ? hs_data_in : do_;

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

// sound RAM: main CPU on port A, sound CPU on port B
assign sram_aa = a[9:0];
assign sram_da = do_;
assign sram_wa = cs_sram && wr;
assign sram_ab = sa[9:0];
assign sram_db = sdo;
assign sram_wb = scs_sram && swr;

/////////////////////////////  15XX  /////////////////////////////

// register writes snooped from both CPUs (never on the same clock: opposite E phases)
logic [10:0] smp_div = 11'd0;
always_ff @(posedge clk) smp_div <= smp_div + 11'd1;
assign wsg_smp = smp_div == 11'd0 && !pause;   // 24 kHz

wire wsg_mw = cs_sram && wr && a[9:6] == 4'd0;
assign wsg_i.sound_en = latch[3];
assign wsg_i.dac_mode = mappy ? 2'd1 : 2'd0;    // 99XX : LS273 + 4066 ladder
assign wsg_i.reg_wr   = wsg_mw || (scs_sram && swr && sa[9:6] == 4'd0);
assign wsg_i.reg_addr = wsg_mw ? a[5:0] : sa[5:0];
assign wsg_i.reg_din  = wsg_mw ? do_ : sdo;
assign wsg_i.wave_d   = wave_q;

/////////////////////////////  56XX x2  /////////////////////////////

// command run 50 us (2458 clocks) after vblank starts (MAME), while not paused
logic [11:0] run_cnt = 12'd0;
always_ff @(posedge clk) begin
    if (vblank_start)                   run_cnt <= 12'd2458;
    else if (run_cnt != 12'd0 && !pause) run_cnt <= run_cnt - 12'd1;
end
wire io_run = run_cnt == 12'd1 && !pause;

wire io_wr0 = cs_io && wr && a[5:4] == 2'd0;
wire io_wr1 = cs_io && wr && a[5:4] == 2'd1;

// #0: COINS (pins 38-41), P1, P2, BUTTONS. #1: DSW2 nibble by pin 13 (LS157 dipmux), DSW1 low, DSW1 high, DSW0.
assign io0_i.kind    = io_kind0;
assign io0_i.reset_n = latch[4];
assign io0_i.run     = io_run;
assign io0_i.wr      = io_wr0;
assign io0_i.addr    = a[3:0];
assign io0_i.din     = do_[3:0];
assign io0_i.in      = {in_buttons[3:0], in_p2[3:0], in_p1[3:0], in_coins[3:0]};
assign io1_i.kind    = io_kind1;
assign io1_i.reset_n = latch[4];
assign io1_i.run     = io_run;
assign io1_i.wr      = io_wr1;
assign io1_i.addr    = a[3:0];
assign io1_i.din     = do_[3:0];
assign io1_i.in      = {dsw0[3:0], dsw1[7:4], dsw1[3:0], io1_o.out[0] ? dsw2[7:4] : dsw2[3:0]};

/////////////////////////////  CPU buses  /////////////////////////////

logic [7:0] main_di;
always_comb begin
    if      (cs_rom)   main_di = main_rom_q;
    else if (cs_vram)  main_di = vram_qa;
    else if (cs_wram0) main_di = wram_qa[0];
    else if (cs_wram1) main_di = wram_qa[1];
    else if (cs_wram2) main_di = wram_qa[2];
    else if (cs_sram)  main_di = sram_qa;
    else if (cs_io)    main_di = a[5] ? 8'hFF : {4'hF, a[4] ? io1_o.dout : io0_o.dout};
    else               main_di = 8'hFF;
end
wire [7:0] sub_di = scs_rom ? sub_rom_q : scs_sram ? sram_qb : 8'hFF;

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

/* verilator lint_off UNUSED */
wire unused = ^hcnt | ^vcnt | ^rom_ofs[2] | ^m6809_0_o.lic | ^m6809_1_o.lic | ^io0_o.out | ^io1_o.out[7:1];
/* verilator lint_on UNUSED */

endmodule
