//============================================================================
//
//  Super Pac-Man / Mappy video boards: 07XX timing, 00XX / 17XX tilemap, sprite line buffer, colour mix.
//  Copyright (C) 2026 Rodimus
//
//  Written from the Super Pac-Man video board schematic (9-3, M051-00316-C007), the Mappy video board schematic and
//  MAME namco/mappy_v.cpp (Nicola Salmoria). Super Pac tile pixel path: 1D LS273 -> 3C char ROM (A0-A3 = 4H, 4V,
//  2V, 1V xor FLIP) -> 11XX -> 4E lookup PROM (A2-A7 = colour from 4F LS377) -> 4D PAL SPV-5 (with the sprite
//  nibble and colour bit 6 = priority) -> 4C palette PROM -> RGB. The PAL equations (SPV-5, Mappy MPI-4) are not on
//  the schematics: MAME's mixes are used.
//    Super Pac (mappy = 0): tile colour 10 + (lookup ^ F); sprites over tiles; tiles with colour bit 6 over sprites
//                           unless their lookup is 0; sprite lookup 0 / 1 over everything. 36 x 28 fixed tilemap
//                           (RAM 0000 code / 0400 colour), 2bpp 16 x 16 sprites, 64 colours.
//    Mappy     (mappy = 1): tile colour 10 + lookup; tiles with colour bit 6 over sprites unless their lookup is F.
//                           36 x 60 tilemap (RAM 0000 code / 0800 colour): columns 2-33 scroll vertically (17XX),
//                           columns 0-1 / 34-35 fixed; tile ROM stored inverted (MAME ROMREGION_INVERT, inverted on
//                           read here). 4bpp 16 x 16 sprites (byte pairs), 16 colours.
//    Phozon    (phozon = 1, no schematics: MAME phozon_state): Super Pac tilemap with a 9-bit tile number (colour
//                           bit 7), tiles in palette 00-0F and sprites in 10-1F, tiles over sprites unless their
//                           lookup is F; 8 x 8 2bpp sprites in 8 / 16 / 32 pixel sizes; 4-bit RGB PROMs (000 / 100 / 200,
//                           2.2K / 1K / 470 / 220), char lookup 300, sprite lookup 400; flip bit in work RAM 1F7F.
//    Gaplus    (gaplus = 1, MAME gaplus_state; Midway schematics for the board only): Super Pac tilemap, 9-bit tile
//                           number from a nibble-packed char ROM (32 bytes per char, 2 pixels per nibble; chars 100-1FF
//                           = the high nibbles, MAME driver_init), 16 x 16 3bpp sprites (plane 0 from the nibble-packed
//                           fourth ROM), 8-bit palette: RGB PROMs 000 / 100 / 200, char lookup 300 (F0 + n), sprite
//                           lookup 400 (low nibble) + 600 (high), FF = transparent; MAME's starfield (CUS26 not modelled:
//                           gaplus_stars.sv + three per-set offsets moved by the control registers once a frame).
//  The line buffer clears to 1111 (RM2 pull-ups), so it holds sprite lookup values and F = no sprite.
//  Gaplus: it holds {star, palette index}, cleared to {0, FF}.
//
//  Raster (MAME): 6.144 MHz, 384 x 264, 288 x 224 visible from hcnt 0 / vcnt 0, 60.606 Hz. One pixel = 8 clocks.
//  The picture is the unrotated (ROT90) 288 x 224 frame; the top level rotates it.
//  flip = the game's own flip (tiles mirrored, sprite flips toggled, as MAME: the game mirrors its sprite positions
//  itself). crt_flip = OSD flip: the whole picture turned 180 degrees (tiles mirrored, sprite positions mirrored).
//
//============================================================================

module superpac_video
(
    input  logic        clk,                // 49.152 MHz
    input  logic  [4:0] div,                // board divider: one pixel per div[2:0] cycle, hcnt[1:0] = div[4:3]
    input  logic        mappy,
    input  logic        phozon,
    input  logic        gaplus,
    input  logic [3:0][7:0] star_ctl,       // Gaplus starfield control (A000-A003)
    input  logic        sprbig,             // sprite ROM twice the base (256 sprites: Grobda 16K 2bpp, Dig Dug II / Motos 32K 4bpp)
    input  logic        slut64,             // Mappy board: 1024-entry sprite lookup (64 colours: Tower of Druaga)
    input  logic        flip,
    input  logic        crt_flip,
    input  logic  [7:0] scroll,             // Mappy: tilemap scroll (columns 2-33)
    input  logic  [3:0] h_adj,              // HSYNC moved 2 pixels per step (signed)
    input  logic  [3:0] v_adj,              // VSYNC moved 1 line per step (signed)

    output logic  [8:0] hcnt,
    output logic  [8:0] vcnt,
    output logic        vblank_start,       // one clock as line 224 (first vblank line) begins

    output logic [11:0] vram_a,             // tilemap RAM (Super Pac 0000-07FF, Mappy 0000-0FFF)
    input  logic  [7:0] vram_q,
    output logic [10:0] spr_a,              // sprite registers x780-x7FF, the same address in the three work RAMs
    input  logic  [7:0] spr_q0,             //   bank 0: number, colour
    input  logic  [7:0] spr_q1,             //   bank 1: y, x
    input  logic  [7:0] spr_q2,             //   bank 2: flip / size, disable / x MSB
    output logic [12:0] tile_rom_a,         // tiles region, read in the board's port-A slot (div 0-7)
    input  logic  [7:0] tile_rom_q,
    output logic [14:0] spr_rom_a,          // sprites region (8K or 16K 2bpp / 16K or 32K 4bpp)
    input  logic  [7:0] spr_rom_q,
    output logic  [9:0] clut_a,             // colour PROMs: palette 000-01F, char lookup 020-11F (Phozon: RGB 000-21F, 300-3FF)
    input  logic  [7:0] clut_q,
    output logic [10:0] slut_a,             // sprite lookup address (colour PROM 120-21F, Druaga 120-51F, Phozon 400-4FF)
    input  logic  [7:0] slut_q,
    output logic  [9:0] lbuf_wa,            // line buffer: {half, x}, written by the sprite engine
    output logic  [8:0] lbuf_wd,
    output logic        lbuf_we,
    output logic  [9:0] lbuf_ra,            //              read by the colour mix
    input  logic  [8:0] lbuf_rq,

    output logic  [7:0] r,
    output logic  [7:0] g,
    output logic  [7:0] b,
    output logic        hs,
    output logic        vs,
    output logic        hblank,
    output logic        vblank
);

wire [2:0] ph = div[2:0];
wire       ce = ph == 3'd7;

/////////////////////////////  Timing (07XX)  /////////////////////////////

logic [8:0] hc = 9'd0, vc = 9'd0;                      // free-running from power-up: hc[1:0] tracks div[4:3]
assign hcnt = hc;
assign vcnt = vc;
wire [8:0] vnext = (vc == 9'd263) ? 9'd0 : vc + 9'd1;

always_ff @(posedge clk) begin
    if (ce) begin
        if (hc == 9'd383) begin
            hc <= 9'd0;
            vc <= vnext;
        end
        else hc <= hc + 9'd1;
    end
end

assign vblank_start = ce && hc == 9'd383 && vc == 9'd223;

/////////////////////////////  Tilemap fetch  /////////////////////////////

// Pipeline per 8-pixel tile t (k = pixel in tile): code / colour of tile t+2 at k = 6 / 7, char ROM bytes of
// tile t+1 at k = 0 (screen pixels 0-3) and k = 4 (4-7) in the board's ROM slot, all loaded at the tile edge.
logic      ph_flip = 1'b0;                              // Phozon / Gaplus: work RAM 1F7F bit 0, read once per frame
wire       gflip = (phozon || gaplus) ? ph_flip : flip;
wire       tflip = gflip ^ crt_flip;
wire [5:0] tcur  = hc[8:3];
wire [2:0] k     = hc[2:0];
wire [5:0] tc1   = (tcur == 6'd47) ? 6'd0 : tcur + 6'd1;
wire [8:0] yc1   = (tcur == 6'd47) ? vnext : vc;
wire [5:0] tc2   = (tcur >= 6'd46) ? tcur - 6'd46 : tcur + 6'd2;
wire [8:0] yc2   = (tcur >= 6'd46) ? vnext : vc;

wire [8:0] my1   = tflip ? 9'd223 - yc1 : yc1;         // tilemap line / column (flip mirrors both)
wire [8:0] my2   = tflip ? 9'd223 - yc2 : yc2;
wire [5:0] mc1   = tflip ? 6'd35 - tc1 : tc1;
wire [5:0] mc2   = tflip ? 6'd35 - tc2 : tc2;
wire [5:0] cc1   = mc1 - 6'd2;                          // MAME col - 2: bit 5 = fixed side columns
wire [5:0] cc2   = mc2 - 6'd2;

// Mappy: the scrolling columns read line (y + scroll) of the 480-line map (223 + 255 never wraps)
wire [8:0] sy1   = (mappy && !cc1[5]) ? my1 + {1'b0, scroll} : my1;
wire [8:0] sy2   = (mappy && !cc2[5]) ? my2 + {1'b0, scroll} : my2;
wire [5:0] row2  = sy2[8:3];
wire [4:0] srw2  = row2[4:0] + 5'd2;                   // Super Pac: MAME row + 2

// MAME superpac_tilemap_scan (32 x 32 RAM, 36 x 28 visible) / mappy_tilemap_scan (fixed columns at 780-7FF)
wire [9:0]  map_sp = cc2[5] ? {cc2[4:0], srw2} : {srw2, cc2[4:0]};
wire [3:0]  frw2   = row2[3:0] + 4'd2;
wire [10:0] map_mp = cc2[5] ? {4'b1111, cc2[1:0], row2[4], frw2} : {row2, cc2[4:0]};

assign vram_a = mappy ? {k[0], map_mp} : {1'b0, k[0], map_sp};    // k = 6: code, k = 7: colour

logic [7:0] code1, code2, attr1, attr2, tb0n, tb1n, tb0, tb1, tattr;
logic [7:0] gbn[4], gb[4];                              // Gaplus char bytes, by screen pixel pair

// char ROM: 16 bytes per tile, bytes 8-15 = pixels 0-3, bytes 0-7 = pixels 4-7 (MAME charlayout)
wire half = k[2] ^ ~tflip;                             // k = 0: first screen half, k = 4: second
// Gaplus: 32 bytes per char, byte {pair, row} holds screen-order pixel pairs (char pixels 0-1 at pair 2, 2-3 at 3,
// 4-5 at 0, 6-7 at 1); two reads per ROM slot (ph 0-3 / 4-7): pairs 0-1 at k = 0, 2-3 at k = 4.
wire [1:0] g_pr = {k[2], ph[2]} ^ {2{tflip}};          // char pixel pair
assign tile_rom_a = gaplus ? {code1, ~g_pr[1], g_pr[0], sy1[2:0]} :
                    {phozon & attr1[7], code1, half, sy1[2:0]};    // Phozon: tile number bit 8 = colour bit 7
wire [7:0] tile_d = mappy ? ~tile_rom_q : tile_rom_q;

always_ff @(posedge clk) begin
    if (ph == 3'd6) begin
        if (k == 3'd6) code2 <= vram_q;
        if (k == 3'd7) attr2 <= vram_q;
        if (k == 3'd0) tb0n <= tile_d;
        if (k == 3'd4) tb1n <= tile_d;
    end
    if (ph == 3'd5 && k[1:0] == 2'd0) gbn[{k[2], 1'b0}] <= tile_rom_q;   // read A (pair address from ph 0)
    if (ph == 3'd7 && k[1:0] == 2'd0) gbn[{k[2], 1'b1}] <= tile_rom_q;   // read B (from ph 4)
    if (ce && k == 3'd7) begin
        tb0   <= tb0n;
        tb1   <= tb1n;
        for (int j = 0; j < 4; j++) gb[j] <= gbn[j];
        tattr <= attr1;
        code1 <= code2;
        attr1 <= attr2;
    end
end

// pixel k of the current tile: 2bpp, planes at bits 7-4 / 3-0 (MAME: plane 0 = MSB of the pen)
wire [7:0] tbyte = k[2] ? tb1 : tb0;
wire [1:0] ti    = tflip ? ~k[1:0] : k[1:0];
wire [1:0] tpen2 = {tbyte[{1'b1, ~ti}], tbyte[{1'b0, ~ti}]};
// Gaplus: nibble = chars 0-FF low, 100-1FF high; even pixel {b3, b1}, odd {b2, b0} (planes at bit offsets 4 / 6)
wire [7:0] gbyte = gb[k[2:1]];
wire [3:0] gnib  = tattr[7] ? gbyte[7:4] : gbyte[3:0];
wire [1:0] tpen  = !gaplus ? tpen2 : (k[0] ^ tflip) ? {gnib[2], gnib[0]} : {gnib[3], gnib[1]};

/////////////////////////////  Colour mix  /////////////////////////////

// Pixel at hcnt is coloured during its own period and output (with its blanking) during the next.
logic [3:0] ctab_c;
logic [8:0] spr_c;
logic       prio_c;
logic [7:0] pal_q;
logic [3:0] pr_q, pg_q, pb_q;                           // Phozon RGB PROM nibbles

wire [3:0] ct      = (mappy || phozon || gaplus) ? ctab_c : ~ctab_c;  // ct = F is transparent over sprites
wire       spr_on  = spr_c[3:0] != 4'hF;
wire       tile_hi = prio_c && ct != 4'hF;
wire       sprio   = !mappy && !phozon && spr_on && spr_c[3:1] == 3'd0;
wire [4:0] tcol    = {~phozon, ct};                     // tiles: palette 10-1F (Phozon 00-0F)
wire [4:0] scol    = {phozon, spr_c[3:0]};              // sprites: palette 00-0F (Phozon 10-1F)
wire [4:0] pix5    = sprio ? scol : tile_hi ? tcol : spr_on ? scol : tcol;
// Gaplus (MAME: stars, low tiles, sprites, high tiles; empty = pen 0, taken as the transparent char colour FF)
wire       g_spr   = !spr_c[8] && spr_c[7:0] != 8'hFF;
wire [7:0] gtcol   = {4'hF, ct};
wire [7:0] gpix    = tile_hi ? gtcol : g_spr ? spr_c[7:0] : (ct != 4'hF) ? gtcol : spr_c[8] ? spr_c[7:0] : gtcol;
wire [7:0] pix     = gaplus ? gpix : {3'd0, pix5};

// Super Pac / Mappy: lookup at ph 0-2, palette byte at ph 3-5. Phozon / Gaplus: lookup at ph 0-1, then R / G / B PROMs.
wire rgb_proms = phozon || gaplus;
always_comb begin
    if (!rgb_proms)      clut_a = (ph <= 3'd2) ? 10'h020 + {2'b00, tattr[5:0], tpen} : {2'd0, pix};
    else if (ph <= 3'd1) clut_a = 10'h300 + {2'b00, tattr[5:0], tpen};
    else if (ph == 3'd2) clut_a = {2'd0, pix};
    else if (ph == 3'd3) clut_a = 10'h100 + {2'd0, pix};
    else                 clut_a = 10'h200 + {2'd0, pix};
end
assign lbuf_ra = {vc[0], hc};

always_ff @(posedge clk) begin
    if (rgb_proms ? ph == 3'd1 : ph == 3'd2) begin
        ctab_c <= clut_q[3:0];
        spr_c  <= lbuf_rq;
        prio_c <= tattr[6];
    end
    if (ph == 3'd5) pal_q <= clut_q;
    if (ph == 3'd3) pr_q  <= clut_q[3:0];
    if (ph == 3'd4) pg_q  <= clut_q[3:0];
    if (ph == 3'd5) pb_q  <= clut_q[3:0];
end

// RGB: R bits 0-2 and G bits 3-5 through 1K / 470 / 220, B bits 6-7 through 470 / 220 (MAME weights)
function automatic [7:0] lvl3(input [2:0] v);
    lvl3 = (v[0] ? 8'd33 : 8'd0) + (v[1] ? 8'd71 : 8'd0) + (v[2] ? 8'd151 : 8'd0);
endfunction
function automatic [7:0] lvl2(input [1:0] v);
    lvl2 = (v[0] ? 8'd81 : 8'd0) + (v[1] ? 8'd174 : 8'd0);
endfunction
// Phozon: 4 bits through 2.2K / 1K / 470 / 220 (MAME weights, rounded per level)
function automatic [7:0] lvl4(input [3:0] v);
    case (v)
        4'd0: lvl4 = 8'd0;    4'd1: lvl4 = 8'd14;   4'd2: lvl4 = 8'd31;   4'd3: lvl4 = 8'd46;
        4'd4: lvl4 = 8'd67;   4'd5: lvl4 = 8'd81;   4'd6: lvl4 = 8'd98;   4'd7: lvl4 = 8'd112;
        4'd8: lvl4 = 8'd143;  4'd9: lvl4 = 8'd157;  4'd10: lvl4 = 8'd174; 4'd11: lvl4 = 8'd188;
        4'd12: lvl4 = 8'd209; 4'd13: lvl4 = 8'd224; 4'd14: lvl4 = 8'd241; default: lvl4 = 8'd255;
    endcase
endfunction

// Gaplus: MAME's constants 0E / 1F / 43 / 8F
function automatic [7:0] lvl4g(input [3:0] v);
    lvl4g = (v[0] ? 8'd14 : 8'd0) + (v[1] ? 8'd31 : 8'd0) + (v[2] ? 8'd67 : 8'd0) + (v[3] ? 8'd143 : 8'd0);
endfunction

wire [8:0] hs_on = 9'd312 + {{4{h_adj[3]}}, h_adj, 1'b0};    // 24 px front porch, 32 sync (Galaga's raster)
wire [8:0] vs_on = 9'd232 + {{5{v_adj[3]}}, v_adj};          // 8 lines front porch, 8 sync
wire       h_vis = hc < 9'd288;
wire       v_vis = vc < 9'd224;

always_ff @(posedge clk) begin
    if (ce) begin
        r      <= !(h_vis && v_vis) ? 8'd0 : gaplus ? lvl4g(pr_q) : phozon ? lvl4(pr_q) : lvl3(pal_q[2:0]);
        g      <= !(h_vis && v_vis) ? 8'd0 : gaplus ? lvl4g(pg_q) : phozon ? lvl4(pg_q) : lvl3(pal_q[5:3]);
        b      <= !(h_vis && v_vis) ? 8'd0 : gaplus ? lvl4g(pb_q) : phozon ? lvl4(pb_q) : lvl2(pal_q[7:6]);
        hblank <= ~h_vis;
        vblank <= ~v_vis;
        hs     <= ~(hc >= hs_on && hc < hs_on + 9'd32);
        vs     <= ~(vc >= vs_on && vc < vs_on + 9'd8);
    end
end

/////////////////////////////  Sprite engine  /////////////////////////////

// During line L the engine draws line L+1 into the other half of the line buffer: clear 288 pixels to 1111,
// then the 64 sprites in order (later ones on top). MAME mappy_draw_sprites, register layout:
//   bank 0: +0 number, +1 colour;  bank 1: +0 y, +1 x;  bank 2: +0 bit 0 x flip, 1 y flip, 2 x size, 3 y size;
//                                                                +1 bit 0 x MSB, 1 disable
// Phozon (MAME phozon_state::draw_sprites): number = {+0, bank 2 +0 bits 7-6}, sizes 8 / 16 / 32 (bank 2 +0 bits 3-2
// x, 5-4 y: 16, 8, 32, -), 8 x 8 tiles {y1, x1, y0, x0} from the number, x - 69, y without the one-line offset.
// The 4-pixel group counter {tx, gcol} gives x = 16 tx + 4 gcol for 16-pixel tiles and 8 {tx, gcol[1]} + 4 gcol[0]
// for 8-pixel tiles, so both walk the row with the same counters.
// Gaplus (MAME gaplus_base_state::draw_sprites): bank 2 +0 bit 3 x size, 5 y size, 6 number bit 8, 7 duplicate (one
// tile in every quarter); tiles number + {y, x} without masking, numbers 180-1FF wrap (384 sprites); x - 71,
// y = 248 - y; 3bpp, two lookup reads per pixel. Before the sprites the engine draws the line's stars (S_STAR).
// CRT flip: the line drawn is picture line 223 - L+1, each pixel at 287 - x.
localparam S_IDLE = 4'd0, S_CLR = 4'd1, S_RD0 = 4'd2, S_RD1 = 4'd3, S_RD2 = 4'd4, S_EVAL = 4'd5, S_ROM = 4'd6,
           S_PIX = 4'd7, S_STAR = 4'd8;
logic [3:0] st = S_IDLE;
logic [8:0] tgt, clr;
logic       bw;
logic [5:0] s;
logic [7:0] n0, c0, y0, x0, a0, a1;
logic       szx, szy, flx, fly, tx, ty, bsel;
logic [3:0] sr;
logic [1:0] gcol, pcnt, wcnt;
logic [9:0] sx;
logic [7:0] code;
logic [7:0] sb0, sb1;
logic [9:0] p_code;                                     // Phozon sprite number
logic [1:0] p_szx, p_szy, p_ty;
logic [8:0] g_code;                                     // Gaplus sprite number
logic       g_dup, hp;

wire rd_flip = (phozon || gaplus) && st == S_IDLE && vc == 9'd230;  // vblank line: engine idle, read 1F7F (bank 2 +77F)
assign spr_a = rd_flip ? 11'h77F : {4'hF, s, st == S_RD1};
always_ff @(posedge clk) if (ce && rd_flip && hc == 9'd8) ph_flip <= spr_q2[0];

function automatic [1:0] p_size(input [1:0] c);         // MAME size[]: 16, 8, 32, 8 pixels -> tiles - 1
    p_size = (c == 2'd0) ? 2'd1 : (c == 2'd2) ? 2'd3 : 2'd0;
endfunction
wire  [1:0] pe_szx = p_size(a0[3:2]);
wire  [1:0] pe_szy = p_size(a0[5:4]);
wire  [7:0] pe_s1  = 8'd0 - y0 - {3'd0, pe_szy, 3'd0};
wire  [9:0] pe_row = {1'b0, tgt} + 10'd32 - {2'd0, pe_s1};
wire        pe_vis = ~a1[1] && !pe_row[9] && (pe_row[8:3] <= {4'd0, pe_szy});

// EVAL: visibility of sprite s on line tgt (MAME: sy = ((257 - y - 16 * y size) & 0xFF) - 32, one-line buffer delay)
wire        e_szx = gaplus ? a0[3] : a0[2];
wire        e_szy = gaplus ? a0[5] : a0[3];
wire  [7:0] e_s1  = (gaplus ? 8'd248 : 8'd1) - y0 - {3'd0, e_szy, 4'd0};    // Gaplus: sy = 256 - y - 8
wire  [9:0] e_row = {1'b0, tgt} + 10'd32 - {2'd0, e_s1};
wire        e_vis = ~a1[1] && !e_row[9] && (e_row[8:5] == 4'd0) && (e_szy || !e_row[4]);

// sprite ROM: 2bpp 64 bytes per sprite, byte = {row bit 3, column group, row bits 2-0}, 4 pixels per byte;
//             4bpp: MAME's ROM_LOAD16_BYTE pair, stored as two halves (gen_mra: even-byte file, then odd): planes
//             0-1 from the first half, 2-3 from the second (+8K, or +16K for a 32K ROM), 64 bytes per sprite each.
//             Sprite number bit 7 is used by the double-size ROMs only (sprbig; otherwise 128 sprites, MAME wraps).
wire  [1:0] bcol  = flx ? ~gcol : gcol;
wire  [7:0] tcode = code + {6'd0, ty ^ (szy & fly), tx ^ (szx & flx)};
wire  [1:0] p_xx  = {tx, gcol[1]} ^ (flx ? p_szx : 2'd0);   // Phozon tile column / row in the sprite
wire  [1:0] p_yy  = p_ty ^ (fly ? p_szy : 2'd0);
wire  [9:0] p_til = p_code + {6'd0, p_yy[1], p_xx[1], p_yy[0], p_xx[0]};
// Gaplus: planes 1-2 from the first 24K (2bpp layout), plane 0 from the fourth ROM at 6000: sprites 0-7F its high
// nibbles, 80-FF its low nibbles (MAME driver_init), 100-17F none (the optional ROM, empty)
wire  [8:0] g_t   = g_code + (g_dup ? 9'd0 : {7'd0, ty ^ (szy & fly), tx ^ (szx & flx)});
wire  [8:0] g_n   = (g_t[8:7] == 2'b11) ? {2'b00, g_t[6:0]} : g_t;
assign spr_rom_a  = gaplus ? (bsel ? {2'b11, g_n[6:0], sr[3], bcol, sr[2:0]} : {g_n, sr[3], bcol, sr[2:0]}) :
                    phozon ? {2'b00, p_til[8:0], gcol[0] ^ flx, sr[2:0]} :
                    {mappy & sprbig & bsel, mappy ? (sprbig ? tcode[7] : bsel) : (sprbig & tcode[7]), tcode[6:0], sr[3], bcol,
                     sr[2:0]};
wire  [2:0] g_last = phozon ? {p_szx, 1'b1} : {szx, 2'b11};  // last 4-pixel group of the row

// pixel pipeline: lookup address -> PROM -> line buffer write (opaque pixels inside the 288-pixel line)
wire  [1:0] pi    = flx ? ~pcnt : pcnt;
wire  [1:0] spen2 = {sb0[{1'b1, ~pi}], sb0[{1'b0, ~pi}]};
wire  [3:0] spen4 = {sb0[{1'b1, ~pi}], sb0[{1'b0, ~pi}], sb1[{1'b1, ~pi}], sb1[{1'b0, ~pi}]};
wire  [9:0] px    = sx + {5'd0, tx, gcol, pcnt};
wire  [8:0] pxf   = crt_flip ? 9'd287 - px[8:0] : px[8:0];
wire        gp0   = !g_n[8] && (g_n[7] ? sb1[{1'b0, ~pi}] : sb1[{1'b1, ~pi}]);
wire  [8:0] g_idx = {c0[5:0], gp0, spen2};

/////////////////////////////  Gaplus stars  /////////////////////////////

// MAME starfield: star i of gaplus_stars.sv belongs to set i % 3; each set is moved as a whole (offsets in the
// 256-wide / 224-line wrap window, x 16-271) by its control register once a frame while A000 bit 0 is set.
// Set 1 stars with even i blink unless its control is 85 (MAME's guess from PCB video).
logic [2:0][7:0] st_ox = '0, st_oy = '0;
logic [7:0] st_fc = 8'd0;
always_ff @(posedge clk) begin
    if (ce && hc == 9'd383 && vc == 9'd229) begin        // once a frame, in vblank (MAME: at vblank end)
        st_fc <= st_fc + 8'd1;
        if (star_ctl[0][0]) for (int j = 0; j < 3; j++) case (star_ctl[j + 1])
            8'h85, 8'h86: st_ox[j] <= st_ox[j] + 8'd1;
            8'h06:        st_ox[j] <= st_ox[j] + 8'd2;
            8'h80:        st_ox[j] <= st_ox[j] - 8'd1;
            8'h82:        st_ox[j] <= st_ox[j] - 8'd2;
            8'h81:        st_ox[j] <= st_ox[j] - 8'd3;
            8'h9F:        st_oy[j] <= (st_oy[j] >= 8'd221) ? st_oy[j] - 8'd221 : st_oy[j] + 8'd3;
            8'hAF:        st_oy[j] <= (st_oy[j] < 8'd3) ? st_oy[j] + 8'd221 : st_oy[j] - 8'd3;
            default: ;
        endcase
    end
end

logic  [7:0] si;
logic  [1:0] sset, stp;
logic [24:0] sd_q, sd_r;
logic        s_last;
gaplus_stars stars (.i(si), .d(sd_q), .last(s_last));
wire  [8:0] sy_s  = {1'b0, sd_r[16:9]} + {1'b0, st_oy[sset]};
wire  [8:0] sy_w  = (sy_s >= 9'd224) ? sy_s - 9'd224 : sy_s;
wire  [7:0] sx_w  = sd_r[24:17] + st_ox[sset];
wire  [3:0] sbl   = st_fc[3:0] + si[3:0];
wire        sblnk = sset == 2'd1 && star_ctl[2] != 8'h85 && !si[0] && (sbl[3] ? sbl[1] : sbl[2]);
wire        s_hit = star_ctl[0][0] && sy_w == tgt && !sblnk;
wire  [8:0] sx_p  = 9'd16 + {1'b0, sx_w};

/////////////////////////////  Pixel pipeline  /////////////////////////////

// Gaplus: the low lookup nibble is addressed one clock before the high one; pv1 marks the high address.
logic [8:0] px1, px2;
logic       pv1 = 1'b0, pv2 = 1'b0, ps1 = 1'b0, ps2 = 1'b0;
logic [3:0] lo_q;

always_ff @(posedge clk) begin
    pv1 <= 1'b0;
    ps1 <= 1'b0;
    if (st == S_PIX && gaplus) begin
        slut_a <= (hp ? 11'h600 : 11'h400) + {2'b00, g_idx};
        px1    <= pxf;
        pv1    <= hp && !px[9] && px[8:0] < 9'd288;
    end
    else if (st == S_PIX) begin
        slut_a <= phozon ? 11'h400 + {3'd0, c0[5:0], spen2} :
                  11'h120 + (!mappy ? {3'd0, c0[5:0], spen2} : slut64 ? {1'b0, c0[5:0], spen4} : {3'd0, c0[3:0], spen4});
        px1    <= pxf;
        pv1    <= !px[9] && px[8:0] < 9'd288;
    end
    else if (st == S_STAR && stp == 2'd1) slut_a <= 11'h400 + {2'b00, sd_r[8:0]};
    else if (st == S_STAR && stp == 2'd2) begin
        slut_a <= 11'h600 + {2'b00, sd_r[8:0]};
        px1    <= crt_flip ? 9'd287 - sx_p : sx_p;
        pv1    <= 1'b1;
        ps1    <= 1'b1;
    end
    if (pv1) lo_q <= slut_q[3:0];
    px2 <= px1;
    pv2 <= pv1;
    ps2 <= ps1;
end

wire [7:0] g_wd = {slut_q[3:0], lo_q};
assign lbuf_we = (st == S_CLR) || (pv2 && (gaplus ? (ps2 || g_wd != 8'hFF) : slut_q[3:0] != 4'hF));
assign lbuf_wa = (st == S_CLR) ? {bw, clr} : {bw, px2};
assign lbuf_wd = (st == S_CLR) ? 9'h0FF : gaplus ? {ps2, g_wd} : {5'h0F, slut_q[3:0]};

always_ff @(posedge clk) begin
    if (ce && hc == 9'd383) begin                      // line start: draw the line after the one beginning now
        tgt <= vnext == 9'd263 ? (crt_flip ? 9'd223 : 9'd0) : crt_flip ? 9'd222 - vnext : vnext + 9'd1;
        bw  <= ~vnext[0];
        clr <= 9'd0;
        st  <= (vnext == 9'd263 || vnext < 9'd223) ? S_CLR : S_IDLE;
    end
    else case (st)
        S_CLR: begin
            if (clr == 9'd287) begin
                s    <= 6'd0;
                si   <= 8'd0;
                sset <= 2'd0;
                stp  <= 2'd0;
                st   <= (gaplus && star_ctl[0][0]) ? S_STAR : S_RD0;
            end
            clr <= clr + 9'd1;
        end
        S_STAR: begin                                  // stp 0: table entry, 1: test (+ low lookup), 2: high lookup
            if (stp == 2'd0) begin sd_r <= sd_q; stp <= 2'd1; end
            else if (stp == 2'd1 && s_hit) stp <= 2'd2;
            else begin
                stp  <= 2'd0;
                si   <= si + 8'd1;
                sset <= (sset == 2'd2) ? 2'd0 : sset + 2'd1;
                if (s_last) st <= S_RD0;
            end
        end
        S_RD0: st <= S_RD1;
        S_RD1: begin n0 <= spr_q0; y0 <= spr_q1; a0 <= spr_q2; st <= S_RD2; end
        S_RD2: begin c0 <= spr_q0; x0 <= spr_q1; a1 <= spr_q2; st <= S_EVAL; end
        S_EVAL: begin
            szx    <= e_szx;
            szy    <= e_szy;
            flx    <= a0[0] ^ gflip;
            fly    <= a0[1] ^ gflip;
            code   <= n0 & {6'h3F, ~e_szy, ~e_szx};
            ty     <= e_row[4];
            sr     <= phozon ? {1'b0, (a0[1] ^ gflip) ? ~pe_row[2:0] : pe_row[2:0]} :
                               (a0[1] ^ gflip) ? ~e_row[3:0] : e_row[3:0];
            sx     <= {1'b0, a1[0], x0} - (gaplus ? 10'd71 : phozon ? 10'd69 : 10'd40);
            g_code <= {a0[6], n0};
            g_dup  <= a0[7];
            hp     <= 1'b0;
            p_code <= {n0, a0[7:6]};
            p_szx  <= pe_szx;
            p_szy  <= pe_szy;
            p_ty   <= pe_row[4:3];
            tx     <= 1'b0;
            gcol   <= 2'd0;
            wcnt   <= 2'd0;
            bsel   <= 1'b0;
            if (phozon ? pe_vis : e_vis) st <= S_ROM;
            else if (s == 6'd63) st <= S_IDLE;
            else begin s <= s + 6'd1; st <= S_RD0; end
        end
        S_ROM: begin                                   // board registers the packed address: data after 3 clocks
            wcnt <= wcnt + 2'd1;
            if (wcnt == 2'd2) begin
                wcnt <= 2'd0;
                if (!bsel) sb0 <= spr_rom_q;
                else       sb1 <= spr_rom_q;
                if ((mappy || gaplus) && !bsel) bsel <= 1'b1;   // 4bpp / Gaplus 3bpp: second byte
                else begin bsel <= 1'b0; pcnt <= 2'd0; st <= S_PIX; end
            end
        end
        S_PIX: if (gaplus && !hp) hp <= 1'b1;          // Gaplus: two clocks per pixel
        else begin
            hp   <= 1'b0;
            pcnt <= pcnt + 2'd1;
            if (pcnt == 2'd3) begin
                wcnt <= 2'd0;
                if ({tx, gcol} != g_last) begin {tx, gcol} <= {tx, gcol} + 3'd1; st <= S_ROM; end
                else if (s == 6'd63) st <= S_IDLE;
                else begin s <= s + 6'd1; st <= S_RD0; end
            end
        end
        default: st <= S_IDLE;
    endcase
end

endmodule
