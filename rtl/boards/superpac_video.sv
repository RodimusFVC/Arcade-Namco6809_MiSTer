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
//  The line buffer clears to 1111 (RM2 pull-ups), so it holds sprite lookup values and F = no sprite.
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
    output logic [11:0] tile_rom_a,         // tiles region, read in the board's port-A slot (div 0-7)
    input  logic  [7:0] tile_rom_q,
    output logic [14:0] spr_rom_a,          // sprites region (8K or 16K 2bpp / 16K or 32K 4bpp)
    input  logic  [7:0] spr_rom_q,
    output logic  [8:0] clut_a,             // colour PROMs: palette 000-01F, char lookup 020-11F
    input  logic  [7:0] clut_q,
    output logic  [9:0] slut_a,             // sprite lookup (colour PROM 120-21F, Druaga 120-51F)
    input  logic  [7:0] slut_q,
    output logic  [9:0] lbuf_wa,            // line buffer: {half, x}, written by the sprite engine
    output logic  [7:0] lbuf_wd,
    output logic        lbuf_we,
    output logic  [9:0] lbuf_ra,            //              read by the colour mix
    input  logic  [7:0] lbuf_rq,

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
wire       tflip = flip ^ crt_flip;
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

// char ROM: 16 bytes per tile, bytes 8-15 = pixels 0-3, bytes 0-7 = pixels 4-7 (MAME charlayout)
wire half = k[2] ^ ~tflip;                             // k = 0: first screen half, k = 4: second
assign tile_rom_a = {code1, half, sy1[2:0]};
wire [7:0] tile_d = mappy ? ~tile_rom_q : tile_rom_q;

always_ff @(posedge clk) begin
    if (ph == 3'd6) begin
        if (k == 3'd6) code2 <= vram_q;
        if (k == 3'd7) attr2 <= vram_q;
        if (k == 3'd0) tb0n <= tile_d;
        if (k == 3'd4) tb1n <= tile_d;
    end
    if (ce && k == 3'd7) begin
        tb0   <= tb0n;
        tb1   <= tb1n;
        tattr <= attr1;
        code1 <= code2;
        attr1 <= attr2;
    end
end

// pixel k of the current tile: 2bpp, planes at bits 7-4 / 3-0 (MAME: plane 0 = MSB of the pen)
wire [7:0] tbyte = k[2] ? tb1 : tb0;
wire [1:0] ti    = tflip ? ~k[1:0] : k[1:0];
wire [1:0] tpen  = {tbyte[{1'b1, ~ti}], tbyte[{1'b0, ~ti}]};

/////////////////////////////  Colour mix  /////////////////////////////

// Pixel at hcnt is coloured during its own period and output (with its blanking) during the next.
logic [3:0] ctab_c, spr_c;
logic       prio_c;
logic [7:0] pal_q;

wire [3:0] ct      = mappy ? ctab_c : ~ctab_c;          // tile colour 10 + ct; ct = F is transparent over sprites
wire       spr_on  = spr_c != 4'hF;
wire       tile_hi = prio_c && ct != 4'hF;
wire       sprio   = !mappy && spr_on && spr_c[3:1] == 3'd0;
wire [4:0] pix     = sprio ? {1'b0, spr_c} : tile_hi ? {1'b1, ct} : spr_on ? {1'b0, spr_c} : {1'b1, ct};

assign clut_a  = (ph <= 3'd2) ? 9'h020 + {1'b0, tattr[5:0], tpen} : {4'd0, pix};
assign lbuf_ra = {vc[0], hc};

always_ff @(posedge clk) begin
    if (ph == 3'd2) begin
        ctab_c <= clut_q[3:0];
        spr_c  <= lbuf_rq[3:0];
        prio_c <= tattr[6];
    end
    if (ph == 3'd5) pal_q <= clut_q;
end

// RGB: R bits 0-2 and G bits 3-5 through 1K / 470 / 220, B bits 6-7 through 470 / 220 (MAME weights)
function automatic [7:0] lvl3(input [2:0] v);
    lvl3 = (v[0] ? 8'd33 : 8'd0) + (v[1] ? 8'd71 : 8'd0) + (v[2] ? 8'd151 : 8'd0);
endfunction
function automatic [7:0] lvl2(input [1:0] v);
    lvl2 = (v[0] ? 8'd81 : 8'd0) + (v[1] ? 8'd174 : 8'd0);
endfunction

wire [8:0] hs_on = 9'd312 + {{4{h_adj[3]}}, h_adj, 1'b0};    // 24 px front porch, 32 sync (Galaga's raster)
wire [8:0] vs_on = 9'd232 + {{5{v_adj[3]}}, v_adj};          // 8 lines front porch, 8 sync
wire       h_vis = hc < 9'd288;
wire       v_vis = vc < 9'd224;

always_ff @(posedge clk) begin
    if (ce) begin
        r      <= (h_vis && v_vis) ? lvl3(pal_q[2:0]) : 8'd0;
        g      <= (h_vis && v_vis) ? lvl3(pal_q[5:3]) : 8'd0;
        b      <= (h_vis && v_vis) ? lvl2(pal_q[7:6]) : 8'd0;
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
// CRT flip: the line drawn is picture line 223 - L+1, each pixel at 287 - x.
localparam S_IDLE = 3'd0, S_CLR = 3'd1, S_RD0 = 3'd2, S_RD1 = 3'd3, S_RD2 = 3'd4, S_EVAL = 3'd5, S_ROM = 3'd6,
           S_PIX = 3'd7;
logic [2:0] st = S_IDLE;
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

assign spr_a = {4'hF, s, st == S_RD1};

// EVAL: visibility of sprite s on line tgt (MAME: sy = ((257 - y - 16 * y size) & 0xFF) - 32, one-line buffer delay)
wire        e_szx = a0[2], e_szy = a0[3];
wire  [7:0] e_s1  = 8'd1 - y0 - {3'd0, e_szy, 4'd0};
wire  [9:0] e_row = {1'b0, tgt} + 10'd32 - {2'd0, e_s1};
wire        e_vis = ~a1[1] && !e_row[9] && (e_row[8:5] == 4'd0) && (e_szy || !e_row[4]);

// sprite ROM: 2bpp 64 bytes per sprite, byte = {row bit 3, column group, row bits 2-0}, 4 pixels per byte;
//             4bpp: MAME's ROM_LOAD16_BYTE pair, stored as two halves (gen_mra: even-byte file, then odd): planes
//             0-1 from the first half, 2-3 from the second (+8K, or +16K for a 32K ROM), 64 bytes per sprite each.
//             Sprite number bit 7 is used by the double-size ROMs only (sprbig; otherwise 128 sprites, MAME wraps).
wire  [1:0] bcol  = flx ? ~gcol : gcol;
wire  [7:0] tcode = code + {6'd0, ty ^ (szy & fly), tx ^ (szx & flx)};
assign spr_rom_a  = {mappy & sprbig & bsel, mappy ? (sprbig ? tcode[7] : bsel) : (sprbig & tcode[7]), tcode[6:0], sr[3], bcol,
                     sr[2:0]};

// pixel pipeline: lookup address -> PROM -> line buffer write (opaque pixels inside the 288-pixel line)
wire  [1:0] pi    = flx ? ~pcnt : pcnt;
wire  [1:0] spen2 = {sb0[{1'b1, ~pi}], sb0[{1'b0, ~pi}]};
wire  [3:0] spen4 = {sb0[{1'b1, ~pi}], sb0[{1'b0, ~pi}], sb1[{1'b1, ~pi}], sb1[{1'b0, ~pi}]};
wire  [9:0] px    = sx + {5'd0, tx, gcol, pcnt};
wire  [8:0] pxf   = crt_flip ? 9'd287 - px[8:0] : px[8:0];
logic [8:0] px1, px2;
logic       pv1 = 1'b0, pv2 = 1'b0;

always_ff @(posedge clk) begin
    pv1 <= 1'b0;
    if (st == S_PIX) begin
        slut_a <= !mappy ? {2'b00, c0[5:0], spen2} : slut64 ? {c0[5:0], spen4} : {2'b00, c0[3:0], spen4};
        px1    <= pxf;
        pv1    <= !px[9] && px[8:0] < 9'd288;
    end
    px2 <= px1;
    pv2 <= pv1;
end

assign lbuf_we = (st == S_CLR) || (pv2 && slut_q[3:0] != 4'hF);
assign lbuf_wa = (st == S_CLR) ? {bw, clr} : {bw, px2};
assign lbuf_wd = (st == S_CLR) ? 8'hFF : {4'hF, slut_q[3:0]};

always_ff @(posedge clk) begin
    if (ce && hc == 9'd383) begin                      // line start: draw the line after the one beginning now
        tgt <= vnext == 9'd263 ? (crt_flip ? 9'd223 : 9'd0) : crt_flip ? 9'd222 - vnext : vnext + 9'd1;
        bw  <= ~vnext[0];
        clr <= 9'd0;
        st  <= (vnext == 9'd263 || vnext < 9'd223) ? S_CLR : S_IDLE;
    end
    else case (st)
        S_CLR: begin
            if (clr == 9'd287) begin s <= 6'd0; st <= S_RD0; end
            clr <= clr + 9'd1;
        end
        S_RD0: st <= S_RD1;
        S_RD1: begin n0 <= spr_q0; y0 <= spr_q1; a0 <= spr_q2; st <= S_RD2; end
        S_RD2: begin c0 <= spr_q0; x0 <= spr_q1; a1 <= spr_q2; st <= S_EVAL; end
        S_EVAL: begin
            szx  <= e_szx;
            szy  <= e_szy;
            flx  <= a0[0] ^ flip;
            fly  <= a0[1] ^ flip;
            code <= n0 & {6'h3F, ~e_szy, ~e_szx};
            ty   <= e_row[4];
            sr   <= (a0[1] ^ flip) ? ~e_row[3:0] : e_row[3:0];
            sx   <= {1'b0, a1[0], x0} - 10'd40;
            tx   <= 1'b0;
            gcol <= 2'd0;
            wcnt <= 2'd0;
            bsel <= 1'b0;
            if (e_vis) st <= S_ROM;
            else if (s == 6'd63) st <= S_IDLE;
            else begin s <= s + 6'd1; st <= S_RD0; end
        end
        S_ROM: begin                                   // board registers the packed address: data after 3 clocks
            wcnt <= wcnt + 2'd1;
            if (wcnt == 2'd2) begin
                wcnt <= 2'd0;
                if (!bsel) sb0 <= spr_rom_q;
                else       sb1 <= spr_rom_q;
                if (mappy && !bsel) bsel <= 1'b1;      // 4bpp: second byte of the pair
                else begin bsel <= 1'b0; pcnt <= 2'd0; st <= S_PIX; end
            end
        end
        S_PIX: begin
            pcnt <= pcnt + 2'd1;
            if (pcnt == 2'd3) begin
                wcnt <= 2'd0;
                gcol <= gcol + 2'd1;
                if (gcol != 2'd3)    st <= S_ROM;
                else if (tx != szx) begin tx <= 1'b1; st <= S_ROM; end
                else if (s == 6'd63) st <= S_IDLE;
                else begin s <= s + 6'd1; st <= S_RD0; end
            end
        end
        default: st <= S_IDLE;
    endcase
end

endmodule
