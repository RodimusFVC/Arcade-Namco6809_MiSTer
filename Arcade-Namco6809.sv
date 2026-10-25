//============================================================================
//
//  Namco 6809 / 15XX hardware for MiSTer (Super Pac-Man, Pac & Pal, Grobda, Phozon, Mappy, The Tower of Druaga,
//  Dig Dug II, Motos, Gaplus / Galaga 3)
//  Copyright (C) 2026 Rodimus
//
//  Built from MAME's mappy.cpp / gaplus.cpp drivers (Nicola Salmoria, Manuel Abadia, Ernesto Corvi) and the
//  Bally Midway Super Pac-Man / Mappy schematics, with the MiSTer arcade framework by Sorgelig.
//  Top level scaffolded from the Galaga core (2026-10-24). Boards: rtl/namco6809_board.sv (Super Pac-Man so far).
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

wire        CLK_49M;
wire        locked;
wire [127:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [10:0] ps2_key;
wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_din;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
wire [26:0] ioctl_addr27;                     // hps_io's full address: the artwork download can pass 32 MB
wire [24:0] ioctl_addr = ioctl_addr27[24:0];  // every other ioctl user
wire  [7:0] ioctl_dout;
wire [15:0] joystick_0, joystick_1;
wire [21:0] gamma_bus;
wire        direct_video;
wire        video_rotated;
wire        pause_cpu;
wire        hblank, vblank;

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire signed [15:0] audio;
assign AUDIO_L = pause_cpu ? 16'd0 : audio;
assign AUDIO_R = pause_cpu ? 16'd0 : audio;
assign AUDIO_S = 1;   // signed
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

///////////////////////////////////////////////////

// MRA index 1 (tools/gen_mra.py):
//   byte 0      board variant (see rtl/namco6809_board.sv)
//   byte 1      flags: [0] 4-way joystick, [2] coins are 2-frame pulses, [4] vertical, [7] vertical is ROT90
//   byte 2      custom I/O kinds: [1:0] chip 0, [3:2] chip 1 (0 = 56XX, 1 = 58XX, 2 = 59XX)
//   byte 3      per-set options (board-defined)
//   bytes 4-7   idle level of the non-DIP ports COINS, P1, P2, BUTTONS (here, not in <switches default>: only
//               3 switch bytes survive Main_MiSTer's DIP default, see Common-Pitfalls)
//   bytes 16-71 input map, one byte per port bit (COINS, P1, P2, BUTTONS, DSW0, DSW1, DSW2; bit 0 first)
//   bytes 72-81 packed ROM store offsets, u16 LE in 256-byte units (17-bit, mod 2^17): maincpu, sub, sub2, tiles, sprites
// DIP switch bytes 0-2 = DSW0, DSW1, DSW2 (Gaplus: nibble ports packed by tools/gen_mra.py); a pressed control
// inverts its bit
localparam NPORT = 7;
reg  [7:0] game_cfg[16] = '{8'd0, 8'h90, 8'd0, 8'd0, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0};
reg  [7:0] in_map[NPORT*8];
reg  [7:0] rom_ofs_b[10];

always @(posedge CLK_49M) begin
    if (ioctl_wr && ioctl_index == 8'd1) begin
        if (ioctl_addr < 25'd16) game_cfg[ioctl_addr[3:0]] <= ioctl_dout;
        else if (ioctl_addr < 25'(16 + NPORT*8)) in_map[6'(ioctl_addr - 25'd16)] <= ioctl_dout;
        else if (ioctl_addr < 25'(16 + NPORT*8 + 10)) rom_ofs_b[4'(ioctl_addr - 25'(16 + NPORT*8))] <= ioctl_dout;
    end
end

wire [7:0] game_var   = game_cfg[0];
wire [7:0] game_flags = game_cfg[1];
wire game_vert = game_flags[4];
wire vert_view = game_vert & ~status[34];

wire [1:0] ar = status[33:32];

wire        art_fb;                // artwork framebuffer on HDMI: square canvas pixels
wire        art_wait, art_avail;
wire [11:0] art_cw, art_ch;
assign VIDEO_ARX = (!ar) ? (art_fb ? art_cw : vert_view ? 12'd3 : 12'd4) : 12'(ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (art_fb ? art_ch : vert_view ? 12'd4 : 12'd3) : 12'd0;

// Status bits from 32 up (Galaga layout). Free: 1-31, 61-127.
`include "build_id.v"
localparam CONF_STR = {
	"Namco6809;;",
	"P1,Video Options;",
	"P1O[33:32],Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"P1O[34],Orientation,Vert,Horz;",
	"P1O[35],HDMI Flip,Off,On;",
	"P1O[36],CRT Flip,Off,On;",
	"P1O[46:43],H Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[50:47],V Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[39:37],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"H1P4,Game Options;",
	"H1P4-,Artwork (MAME layout views);",
	"H1P4O[54:51],View,Off,View 1,View 2,View 3,View 4,View 5,View 6,View 7,View 8,View 9,View 10,View 11,View 12,View 13,View 14,View 15;",
	"H1P4O[55],Backdrop,On,Off;",
	"H1P4O[56],Overlay,On,Off;",
	"H1P4O[57],Bezel,On,Off;",
	"H1P4O[60],Control Panel,On,Off;",
	"H1P4O[58],Side Art,On,Off;",
	"H1P4O[59],Zoom to Screen,Off,On;",
	"H1-;",
	"P2,Pause Options;",
	"P2O[40],Pause when OSD is open,On,Off;",
	"P2O[41],Dim video after 10s,On,Off;",
	"-;",
	"P3,High Score Options;",
	"P3O[42],Autosave Hiscores,Off,On;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Btn 1,Btn 2,Btn 3,Btn 4,Coin,Start 1P,Start 2P,Pause;",
	"jn,A,B,X,Y,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_49M),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({~art_avail, direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),
	.ioctl_wait(art_wait),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);


////////////////////   CLOCKS   ///////////////////

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_49M),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(0),
	.mgmt_address(0),
	.mgmt_writedata(0),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// Hold the board in reset until the PLL is locked and the whole MRA load has finished. Main_MiSTer releases the
// sys reset on its first SPI access, before it sets status[0] for the MRA load: hold from FPGA configuration until
// status[0] has been seen once (Galaga core, HW-proven).
reg hps_ready = 1'b0;
always @(posedge CLK_49M) if (status[0]) hps_ready <= 1'b1;
wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked | ~hps_ready;

//////////////////  Arcade Buttons/Interfaces (rtl/mister_custom/controllers.sv)  ///////////////////////////

// Joystick bits: 0 R, 1 L, 2 D, 3 U, 4-7 Btn 1-4, 8 Coin, 9 Start 1P, 10 Start 2P, 11 Pause
wire [12:0] kb;
// CTL-2026-10-25: original below (v1, pause not connected)
// ctl_keyboard keyboard(.clk(CLK_49M), .ps2_key(ps2_key), .kb(kb));
// CTL-2026-10-25: v2 pause port (no toggle keys here, so pause changes nothing); kbx unused
/* verilator lint_off PINCONNECTEMPTY */
ctl_keyboard keyboard(.clk(CLK_49M), .ps2_key(ps2_key), .pause(pause_cpu), .kb(kb), .kbx());
/* verilator lint_on PINCONNECTEMPTY */

wire [3:0] dir1_raw = {joystick_0[3] | kb[0], joystick_0[2] | kb[1], joystick_0[1] | kb[2], joystick_0[0] | kb[3]};
wire [3:0] dir2_raw = joystick_1[3:0];
wire [3:0] dir1, dir2;   // {U, D, L, R}
ctl_joy4way joy4way_1(.clk(CLK_49M), .en(game_flags[0]), .in(dir1_raw), .out(dir1));
ctl_joy4way joy4way_2(.clk(CLK_49M), .en(game_flags[0]), .in(dir2_raw), .out(dir2));

wire m_pause = joystick_0[11] | kb[12];

wire coin1, coin2;
// CTL-2026-10-25: original below (v1 pause form: a coin pressed while paused fired after resume)
// ctl_coin_impulse coin_imp1(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
//                            .coin_raw(joystick_0[8] | kb[8]), .coin(coin1));
// ctl_coin_impulse coin_imp2(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
//                            .coin_raw(joystick_1[8] | kb[9]), .coin(coin2));
// CTL-2026-10-25: v2 PAUSE_MODE 1: a coin pressed while paused is discarded (library pause table); FRAMES 2 = v1 default
ctl_coin_impulse #(.FRAMES(4'd2), .PAUSE_MODE(1)) coin_imp1(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank),
                           .en(game_flags[2]), .coin_raw(joystick_0[8] | kb[8]), .coin(coin1));
ctl_coin_impulse #(.FRAMES(4'd2), .PAUSE_MODE(1)) coin_imp2(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank),
                           .en(game_flags[2]), .coin_raw(joystick_1[8] | kb[9]), .coin(coin2));

wire [35:0] ctl36;
ctl_ids ids(.joy0(joystick_0), .joy1(joystick_1), .kb(kb), .dir1(dir1), .dir2(dir2),
            .coin1(coin1), .coin2(coin2), .coin3(1'b0), .ctl(ctl36));
wire [63:0] ctl = {28'd0, ctl36};

// DIP switches arrive from the OSD via ioctl index 254: bytes 0-2 = DSW0, DSW1, DSW2
reg [7:0] dip_sw[8] = '{8'hFF,8'hFF,8'hFF,8'h00,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_49M) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

wire [NPORT*8-1:0]  idle;
wire [NPORT*64-1:0] in_map_flat;
genvar gi;
generate
	for (gi = 0; gi < NPORT; gi = gi + 1) begin : g_port
		assign idle[gi*8 +: 8] = gi < 4 ? game_cfg[4 + gi] : dip_sw[gi - 4];
	end
	for (gi = 0; gi < NPORT*8; gi = gi + 1) begin : g_map
		assign in_map_flat[gi*8 +: 8] = in_map[gi];
	end
endgenerate

wire [NPORT*8-1:0] in_ports;
ctl_port_map #(.NP(NPORT), .IDW(6)) port_map
(
// CTL-2026-10-25: original port list below (v1 had no port_sel / dip_bytes / dip_bit)
// 	.clk(CLK_49M), .idle(idle), .in_map(in_map_flat), .dips(32'd0), .ctl(ctl),
// 	.ovr_mask('0), .ovr_val('0), .ports(in_ports)
	// CTL-2026-10-25: v2 ports tied 0 (BASE_MODE 0 = v1 idle levels; they are unused)
	.clk(CLK_49M), .idle(idle), .in_map(in_map_flat), .dips(32'd0), .port_sel({(NPORT*8){1'b0}}),
	.dip_bytes(64'd0), .dip_bit({(NPORT*24){1'b0}}), .ctl(ctl),
	.ovr_mask('0), .ovr_val('0), .ports(in_ports)
);

// PAUSE SYSTEM
wire [23:0] rgb_out;
pause #(8,8,8,49) pause
(
	.*,
	.clk_sys(CLK_49M),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[41:40])
);

///////////////                 Video                  ////////////////

wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix;
wire        bd_hs, bd_vs, bd_hbl, bd_vbl;
wire  [7:0] bd_r, bd_g, bd_b;

// MAME artwork (ioctl index 5, OSD Game Options page): native composite on the core video (one pixel late),
// full view through the DDR3 framebuffer on HDMI. CODE_BITS 7 until Gaplus / Phozon colours per frame are measured
// (Mappy family: 32-entry palette PROM, 5 bits would do).
wire        art_run, art_ddr;
wire [31:0] art_fb_base;
wire  [7:0] art_burstcnt, art_be;
wire [28:0] art_addr;
wire [63:0] art_din;
wire        art_rd, art_we, art_clk;
artwork #(.IDX(8'd5), .CODE_BITS(7)) artwork
(
	.clk(CLK_49M),
	.sel(status[54:51]), .layer_off({status[60], status[57:55]}), .side_off(status[58]), .zoom(status[59]),
	.crt_flip(status[36]), .hdmi_flip(status[35]), .turn(status[34]), .avail(art_avail),
	.hdmi_w(HDMI_WIDTH), .hdmi_h(HDMI_HEIGHT),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27), .ioctl_dout(ioctl_dout), .ioctl_wait(art_wait),
	.ce_pix(ce_pix),
	.hs_in(bd_hs), .vs_in(bd_vs), .hblank_in(bd_hbl), .vblank_in(bd_vbl), .rgb_in({bd_r, bd_g, bd_b}),
	.hs_out(hs), .vs_out(vs), .hblank_out(hblank), .vblank_out(vblank), .rgb_out({r, g, b}),
	.running(art_run), .ddr_owner(art_ddr), .canvas_w(art_cw), .canvas_h(art_ch),
	.fb_base(art_fb_base), .fb_vbl(FB_VBL),
	.DDRAM_CLK(art_clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(art_burstcnt), .DDRAM_ADDR(art_addr),
	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(art_rd),
	.DDRAM_DIN(art_din), .DDRAM_BE(art_be), .DDRAM_WE(art_we)
);
// Orientation Horz (rotated monitor): the artwork turns its own view, so it keeps the framebuffer
assign art_fb = art_run & ~direct_video;

wire rotate_ccw = ~game_flags[7];  // ROT270 sets rotate CCW, ROT90 sets CW
wire no_rotate  = ~game_vert | status[34] | direct_video;
wire flip       = status[35];
wire        sr_fb_en, sr_clk, sr_rd, sr_we;
wire  [4:0] sr_fb_format;
wire [11:0] sr_fb_w, sr_fb_h;
wire [31:0] sr_fb_base;
wire [13:0] sr_fb_stride;
wire  [7:0] sr_burstcnt, sr_be;
wire [28:0] sr_addr;
wire [63:0] sr_din;
screen_rotate screen_rotate
(
	.*,
	.FB_EN(sr_fb_en), .FB_FORMAT(sr_fb_format), .FB_WIDTH(sr_fb_w), .FB_HEIGHT(sr_fb_h),
	.FB_BASE(sr_fb_base), .FB_STRIDE(sr_fb_stride),
	.DDRAM_CLK(sr_clk), .DDRAM_BURSTCNT(sr_burstcnt), .DDRAM_ADDR(sr_addr), .DDRAM_DIN(sr_din),
	.DDRAM_BE(sr_be), .DDRAM_WE(sr_we), .DDRAM_RD(sr_rd)
);

// the artwork takes the framebuffer while it draws, and DDR3 while it loads or draws
assign FB_EN     = art_fb | sr_fb_en;
assign FB_FORMAT = art_fb ? 5'b00110  : sr_fb_format;
assign FB_WIDTH  = art_fb ? art_cw    : sr_fb_w;
assign FB_HEIGHT = art_fb ? art_ch    : sr_fb_h;
assign FB_BASE   = art_fb ? art_fb_base : sr_fb_base;
assign FB_STRIDE = art_fb ? 14'd8192  : sr_fb_stride;
assign DDRAM_CLK      = CLK_49M;
assign DDRAM_BURSTCNT = art_ddr ? art_burstcnt : sr_burstcnt;
assign DDRAM_ADDR     = art_ddr ? art_addr : sr_addr;
assign DDRAM_DIN      = art_ddr ? art_din : sr_din;
assign DDRAM_BE       = art_ddr ? art_be : sr_be;
assign DDRAM_WE       = art_ddr ? art_we : sr_we;
assign DDRAM_RD       = art_ddr ? art_rd : sr_rd;

arcade_video #(288,24) arcade_video
(
	.*,

	.clk_video(CLK_49M),

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[39:37])
);

///////////////                 Board                  ////////////////

// CRT Flip (status[36]) = board-level 180-degree flip on every board; HDMI Flip (status[35]) on top of it
namco6809_board board
(
	.clk(CLK_49M),
	.reset(reset),
	.pause(pause_cpu),
	.variant(game_var),
	.game_cfg({game_cfg[15], game_cfg[14], game_cfg[13], game_cfg[12], game_cfg[11], game_cfg[10], game_cfg[9], game_cfg[8],
	           game_cfg[7],  game_cfg[6],  game_cfg[5],  game_cfg[4],  game_cfg[3],  game_cfg[2],  game_cfg[1], game_cfg[0]}),
	.rom_ofs({{rom_ofs_b[9][0], rom_ofs_b[8], 8'd0}, {rom_ofs_b[7][0], rom_ofs_b[6], 8'd0}, {rom_ofs_b[5][0], rom_ofs_b[4], 8'd0},
	          {rom_ofs_b[3][0], rom_ofs_b[2], 8'd0}, {rom_ofs_b[1][0], rom_ofs_b[0], 8'd0}}),
	.crt_flip(status[36]),
	.h_adj(status[46:43]),
	.v_adj(status[50:47]),

	.in_coins(in_ports[7:0]),
	.in_p1(in_ports[15:8]),
	.in_p2(in_ports[23:16]),
	.in_buttons(in_ports[31:24]),
	.dsw0(in_ports[39:32]),
	.dsw1(in_ports[47:40]),
	.dsw2(in_ports[55:48]),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr0(ioctl_wr & (ioctl_index == 8'd0)),

	.ce_pix(ce_pix),
	.video_r(bd_r),
	.video_g(bd_g),
	.video_b(bd_b),
	.video_hs(bd_hs),
	.video_vs(bd_vs),
	.video_hblank(bd_hbl),
	.video_vblank(bd_vbl),

	.audio(audio),

	.hs_access(hs_access_read | hs_access_write),
	.hs_address(hs_address),
	.hs_data_in(hs_data_in),
	.hs_data_out(hs_data_out),
	.hs_write(hs_write_enable)
);

// Hiscore: config = MRA index 3, dump = index 4; the board's bus is handed to it while the CPUs are paused.
// HS_SCOREWIDTH: set it to cover the largest hiscore.dat range of the supported sets before enabling saves.
wire [15:0] hs_address;
wire  [7:0] hs_data_in;
wire  [7:0] hs_data_out;
wire        hs_write_enable;
wire        hs_access_read;
wire        hs_access_write;
wire        hs_pause;
wire        hs_configured;

hiscore #(
	.HS_ADDRESSWIDTH(16),
	.CFG_ADDRESSWIDTH(4),
	.CFG_LENGTHWIDTH(2)
) hi (
	.*,
	.clk(CLK_49M),
	.paused(pause_cpu),
	.autosave(status[42]),
	.ram_address(hs_address),
	.data_from_ram(hs_data_out),
	.data_to_ram(hs_data_in),
	.data_from_hps(ioctl_dout),
	.data_to_hps(ioctl_din),
	.ram_write(hs_write_enable),
	.ram_intent_read(hs_access_read),
	.ram_intent_write(hs_access_write),
	.pause_cpu(hs_pause),
	.configured(hs_configured)
);

endmodule
