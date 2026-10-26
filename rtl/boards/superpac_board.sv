//============================================================================
//
//  Namco Super Pac-Man board (CPU A084-91434 / video A084-91435): superpac, superpacm, pacnpal*, grobda* (variant 0,
//  mappy = 0); Grobda: 16K sprite ROM (opts[1]), speech through the 15XX (register 2 writes, MAME / PCB notes)
//  Namco Mappy board (CPU A084-91479 / video A084-91480): mappy, mappyj (variant 2, mappy = 1); the same board with
//  per-set options (index 1 byte 3): todruaga* (64 sprite colours, no watchdog), digdug2* (32K sprites, no watchdog),
//  motos (32K sprites)
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
//  ROM store port A is time-sliced on div[4:3]: 0 tiles (video), 1 sound CPU, 2 main (Phozon: sub CPU), 3 main CPU.
//
//  Phozon board (variant 1, phozon = 1; no schematics: Super Pac board + MAME phozon_state): a third 6809 (sub CPU,
//  pool m6809_2, E falling at div 23) shares the tilemap / work / sound RAM with the main CPU (RAM port A time-sliced:
//  div[4:3] = 2 sub CPU, else main) and has 2K private RAM at A000 (pool xram). LS259: Q2 sub CPU IRQ enable,
//  Q6 sub CPU run (no flip: the flip bit is in work RAM 1F7F, read by the video). Watchdog at 7000, ROM 8000-FFFF;
//  the sound CPU has no LS259 access. DAC: 99XX assumed (Mappy / Gaplus era; #unverified, MAME has one model).
//
//  Gaplus board (variant 3, gaplus = 1; MAME gaplus_state + Midway schematics): the sub CPU (MAME "sub", pool m6809_2,
//  ROM A000-FFFF) shares tilemap / work RAM as on Phozon; the sound CPU is MAME "sub2" (ROM offsets 1 / 2 swapped).
//  No LS259: the 34XX decodes 7000 / 7800 (main IRQ enable, data in A11), 8000 / 8800 (sub + sound CPU run, sound
//  on), 9000 / 9800 (I/O run); sub CPU 6000-6FFF IRQ enable (A0), sound CPU 4000 / 6000 IRQ enable (A13). They set
//  the same latch bits as the LS259. Sound RAM 6000, I/O 6800 / 6810 / 6820, starfield control A000-A003, watchdog
//  7800 read (off: MAME has none). 99XX DAC.
//  62XX (6820-682F): the real MB88 program (namco62.zip, pool mb88_0) on the CUS16 I/O bus. The CPU side is the 2114
//  (16 x 4 bits here); the 62XX is bus master at VBLANK: R8 low = request, R9 low = grant (CUS16, given at once
//  here), R4-R6 = FA0-2, R7 = FR/W, R0-R3 = data. Reads (R7 = 1) see CPU offsets 8-F, writes (R7 = 0) land in
//  offsets 0-7, taken when R4-R7 change with R7 low (data is set first). X = 2HB (1.536 MHz: one machine cycle per
//  192 clocks), RESET = FRESET, R10/IRQ = VBLANK, K = IN2. Its O port drives the explosion DACs (gaplus_boom).
//
//============================================================================

module superpac_board
(
    input  logic        clk,                    // 49.152 MHz
    input  logic        reset,
    input  logic        pause,
    input  logic        mappy,                  // Mappy board deltas
    input  logic        phozon,                 // Phozon board deltas
    input  logic        gaplus,                 // Gaplus board deltas
    input  logic  [7:0] opts,                   // index 1 byte 3: [0] no watchdog, [1] 256 sprites, [2] 64 sprite colours
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
    output chip_pool_pkg::m6809r_i_t  m6809_2_i,          // Phozon sub CPU
    input  chip_pool_pkg::m6809r_o_t  m6809_2_o,
    output chip_pool_pkg::wsg15_i_t   wsg_i,
    output logic                      wsg_smp,
    output chip_pool_pkg::namcoio_i_t io0_i,
    input  chip_pool_pkg::namcoio_o_t io0_o,
    output chip_pool_pkg::namcoio_i_t io1_i,
    input  chip_pool_pkg::namcoio_o_t io1_o,
    output chip_pool_pkg::mb88_i_t    mb88_i,             // Gaplus 62XX
    input  chip_pool_pkg::mb88_o_t    mb88_o,

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
    output logic [10:0] xram_aa,                // Phozon sub CPU private RAM (A000-A7FF)
    output logic  [7:0] xram_da,
    output logic        xram_wa,
    input  logic  [7:0] xram_qa,
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
wire sub_on  = phozon | gaplus;                       // third 6809 fitted
wire fall_q2 = (div == 5'd15) & ~pause_x & sub_on;    // Phozon / Gaplus sub CPU: E falls at the end of ROM / RAM slot 2
wire fall_e2 = (div == 5'd23) & ~pause_x & sub_on;

/////////////////////////////  Video  /////////////////////////////

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
wire cs_flip  = !mappy && !phozon && !gaplus && a[15:11] == 5'b00100;
wire cs_scrl  = mappy && a[15:11] == 5'b00111;
wire cs_sram  = a[15:11] == (gaplus ? 5'b01100 : 5'b01000);            // Gaplus 6000
wire cs_io    = a[15:11] == (gaplus ? 5'b01101 : 5'b01001);            // Gaplus 6800
wire cs_latch = !gaplus && a[15:11] == 5'b01010;
wire cs_wdr   = gaplus ? a[15:11] == 5'b01111 : phozon ? a[15:11] == 5'b01110 : a[15:11] == 5'b10000;    // 7800 / 7000
wire wd_kick  = cs_wdr && (gaplus ? fall_e & rw : wr);                  // Gaplus: on read
wire g_mirq   = gaplus && a[15:12] == 4'h7 && wr;                       // Gaplus 34XX writes (data in A11)
wire g_sres   = gaplus && a[15:12] == 4'h8 && wr;
wire g_fres   = gaplus && a[15:12] == 4'h9 && wr;
wire g_star   = gaplus && a[15:11] == 5'b10100 && wr;
wire cs_rom   = (mappy || phozon) ? a[15] : a[15:13] >= 3'b101;

/////////////////////////////  Sound CPU  /////////////////////////////

wire [15:0] sa  = m6809_1_o.a;
wire  [7:0] sdo = m6809_1_o.dout;
wire        srw = m6809_1_o.rw;
wire        swr = sfall_e & ~srw;

wire scs_sram  = sa[15:13] == 3'b000;
wire scs_latch = !phozon && !gaplus && sa[15:13] == 3'b001;
wire g_sirq    = gaplus && sa[15:14] == 2'b01 && swr;                  // Gaplus sound CPU IRQ enable (A13)
wire scs_rom   = sa[15:13] == 3'b111;

/////////////////////////////  Phozon sub CPU  /////////////////////////////

wire [15:0] a2  = m6809_2_o.a;
wire  [7:0] do2 = m6809_2_o.dout;
wire        rw2 = m6809_2_o.rw;
wire        wr2 = fall_e2 & ~rw2;

wire [2:0] bank2   = ram_bank(a2, 1'b0);       // tilemap / work RAM as the main CPU (Super Pac map)
wire       s2_sram = phozon && a2[15:11] == 5'b01000;
wire       s2_xram = phozon && a2[15:11] == 5'b10100;
wire       s2_rom  = gaplus ? a2[15:13] >= 3'b101 : a2[15:13] == 3'b111;
wire       g_s2irq = gaplus && a2[15:12] == 4'h6 && wr2;                // Gaplus sub CPU IRQ enable (A0)
wire       slot2   = sub_on && div[4:3] == 2'd2;   // RAM port A belongs to the sub CPU

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
        if (wd_kick) wd_cnt <= 4'd0;
        else if (vblank_start && !pause && !opts[0]) begin    // Dig Dug II / Druaga: no watchdog (MAME)
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
    // IRQ on vblank while enabled, held until the enable bit is cleared
    if (cpu_rst || !latch[1]) irq_m <= 1'b0;
    else if (vblank_start)    irq_m <= 1'b1;
    if (cpu_rst || !latch[0]) irq_s <= 1'b0;
    else if (vblank_start)    irq_s <= 1'b1;
    if (cpu_rst || !latch[2] || !sub_on) irq_s2 <= 1'b0;
    else if (vblank_start)               irq_s2 <= 1'b1;
end

/////////////////////////////  ROM store port A slots  /////////////////////////////

wire [16:0] main_pk = {1'b0, a}  + rom_ofs[0];
wire [16:0] sub_pk  = {1'b0, sa} + (gaplus ? rom_ofs[2] : rom_ofs[1]);    // Gaplus: sound CPU = MAME "sub2"
wire [16:0] sub2_pk = {1'b0, a2} + (gaplus ? rom_ofs[1] : rom_ofs[2]);
wire [16:0] tile_pk = {4'd0, tile_rom_a} + rom_ofs[3];

always_ff @(posedge clk) begin
    case (div[4:3])
        2'd0:    rom_a_addr <= tile_pk;        // video reads at div 6
        2'd1:    rom_a_addr <= sub_pk;
        2'd2:    rom_a_addr <= sub_on ? sub2_pk : main_pk;
        default: rom_a_addr <= main_pk;
    endcase
    rom_b_addr <= {2'd0, spr_rom_a} + rom_ofs[4];
    if (div == 5'd14) sub_rom_q  <= rom_a_q;
    if (div == 5'd22) sub2_rom_q <= rom_a_q;
    if (div == 5'd30) main_rom_q <= rom_a_q;
end

/////////////////////////////  RAMs  /////////////////////////////

// port A: main CPU (Phozon: the sub CPU in slot 2), or the hiscore system while paused
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

// sound RAM: main CPU (Phozon: + sub CPU in slot 2) on port A, sound CPU on port B
wire   slot2s  = slot2 && phozon;                  // only Phozon's sub CPU reaches the sound RAM
assign sram_aa = slot2s ? a2[9:0] : a[9:0];
assign sram_da = slot2s ? do2 : do_;
assign sram_wa = slot2s ? s2_sram && wr2 : cs_sram && wr;
assign sram_ab = sa[9:0];
assign sram_db = sdo;
assign sram_wb = scs_sram && swr;

assign xram_aa = a2[10:0];
assign xram_da = do2;
assign xram_wa = s2_xram && wr2;

/////////////////////////////  15XX  /////////////////////////////

// register writes snooped from every CPU (never on the same clock: E falls at div 31 / 15 / 23)
logic [10:0] smp_div = 11'd0;
always_ff @(posedge clk) smp_div <= smp_div + 11'd1;
assign wsg_smp = smp_div == 11'd0 && !pause;   // 24 kHz

wire wsg_mw = cs_sram && wr && a[9:6] == 4'd0;
wire wsg_2w = s2_sram && wr2 && a2[9:6] == 4'd0;
assign wsg_i.sound_en = latch[3];
assign wsg_i.dac_mode = (mappy || phozon || gaplus) ? 2'd1 : 2'd0;    // 99XX : LS273 + 4066 ladder
assign wsg_i.reg_wr   = wsg_mw || wsg_2w || (scs_sram && swr && sa[9:6] == 4'd0);
assign wsg_i.reg_addr = wsg_mw ? a[5:0] : wsg_2w ? a2[5:0] : sa[5:0];
assign wsg_i.reg_din  = wsg_mw ? do_ : wsg_2w ? do2 : sdo;
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
// Gaplus #1: DSWA high, DSWB low, DSWB high, DSWA low (MAME; DSW0 = DSWA, DSW1 = DSWB)
assign io1_i.in      = {dsw0[3:0], dsw1[7:4], dsw1[3:0], gaplus ? dsw0[7:4] : io1_o.out[0] ? dsw2[7:4] : dsw2[3:0]};

// Gaplus 62XX at 6820: the 2114 cells shared by the CPU and the 62XX (see the header)
logic [15:0][3:0] cio3 = '0;
logic  [7:0] c62 = 8'd0;
always_ff @(posedge clk) c62 <= (c62 == 8'd191) ? 8'd0 : c62 + 8'd1;

wire  [3:0] m62_p0 = mb88_o.r_out[3:0];
wire  [3:0] m62_p1 = mb88_o.r_out[7:4];
wire  [3:0] m62_p2 = mb88_o.r_out[11:8];
wire        m62_gnt = !m62_p2[0];                   // R8 low: the CUS16 grants at once (R9 low)
logic [3:0] m62_p1d = 4'hF;
wire        m62_wr = gaplus && m62_gnt && !m62_p1[3] && m62_p1 != m62_p1d;
always_ff @(posedge clk) begin
    m62_p1d <= m62_p1;
    if (m62_wr) cio3[{1'b0, m62_p1[2:0]}] <= m62_p0;
    if (gaplus && cs_io && wr && a[5:4] == 2'd2) cio3[a[3:0]] <= do_[3:0];
end
wire [7:0] cio3_q = {4'hF, cio3[a[3:0]]};

assign mb88_i.ena     = gaplus && c62 == 8'd0 && !pause;
assign mb88_i.reset_n = gaplus && latch[4];
assign mb88_i.k       = dsw2[3:0];
assign mb88_i.r_in    = {mb88_o.r_out[15:12],
                         m62_p2 & {1'b1, !video_vblank, !m62_gnt, 1'b1},
                         m62_p1,
                         m62_p0 & ((m62_gnt && m62_p1[3]) ? cio3[{1'b1, m62_p1[2:0]}] : 4'hF)};
assign mb88_i.irq_n   = !video_vblank;              // R10/_IRQ = VBLANK (polarity #unverified: IRQ at vblank start)
assign mb88_i.tc_n    = 1'b1;
assign mb88_i.si_n    = 1'b1;
assign mb88_i.rom_d   = 8'h00;                      // ROM read in the dispatcher (mcu62_rom)

/////////////////////////////  CPU buses  /////////////////////////////

logic [7:0] main_di;
always_comb begin
    if      (cs_rom)   main_di = main_rom_q;
    else if (cs_vram)  main_di = vram_qa;
    else if (cs_wram0) main_di = wram_qa[0];
    else if (cs_wram1) main_di = wram_qa[1];
    else if (cs_wram2) main_di = wram_qa[2];
    else if (cs_sram)  main_di = sram_qa;
    else if (cs_io)    main_di = (gaplus && a[5:4] == 2'd2) ? cio3_q : a[5] ? 8'hFF : {4'hF, a[4] ? io1_o.dout : io0_o.dout};
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
wire unused = ^hcnt | ^vcnt | ^m6809_0_o.lic | ^m6809_1_o.lic | ^m6809_2_o.lic | ^io0_o.out | ^io1_o.out[7:1];
/* verilator lint_on UNUSED */

endmodule
