//============================================================================
//
//  Sky Kid / Dragon Buster video (MAME namco/skykid.cpp; Namco 07XX-style timing, the Super Pac raster).
//  Copyright (C) 2026 Rodimus
//
//  Layers, back to front: background (64 x 32 tiles, opaque, scrolled), text tiles whose category (code bits 7-4)
//  equals priority bits 7-4 when priority bit 2 is set, sprites, the other text tiles.
//    Text   36 x 28 (Super Pac scan, RAM 4000-47FF: code, +400 colour), 2bpp, 16 bytes per char (bytes 8-15 =
//           pixels 0-3), palette index {colour[5:0], pen}, pen 0 transparent. Game flip uses the second (pre-flipped)
//           character set: positions mirror, glyph pixels do not.
//    BG     RAM 2000-2FFF (code, +800 attribute): tile {attr[0], code}, colour {attr[0], attr[6:1]}; 2bpp, 16 bytes
//           per tile (bytes 2y / 2y+1 = pixels 0-3 / 4-7); lookup PROM 300 + {colour, pen}. Scroll = written address.
//           MAME (tilemap scroll 512 x 256 on a 288 x 224 screen): map x = x + sx + 35, y + sy + 25; game flip (the
//           game runs flipped: A001 at boot) map x = 476 - x - (sx ^ 1), y = 230 - y - sy: the scroll counts the other way.
//    Sprites the Mappy sprite generator: bank 0 x780 number / colour, bank 1 y / x, bank 2 flip / size, number
//           bit 8, x MSB; 16 x 16 3bpp, lookup PROM 500 + {colour, pen}, FF transparent; no disable bit.
//           Sprite ROM as loaded (MAME init_skykid unpacks it; decoded on read here): sprites 0-FF planes 1-2 at
//           0000, plane 0 = the third ROM's low (0-7F) / high (80-FF) nibbles at 4000; sprites 100-1FF planes 1-2
//           at 6000 (repeats every 80), no plane 0.
//    RGB    4-bit PROMs 000 / 100 / 200 (MAME pal4bit).
//  ROM store port A: text bytes in slot 0 (k = 0 / 4, as Super Pac), background bytes in slot 1 (k = 1 / 5).
//
//============================================================================

module skykid_video
(
    input  logic        clk,                // 49.152 MHz
    input  logic  [4:0] div,                // board divider: one pixel per div[2:0] cycle, hcnt[1:0] = div[4:3]
    input  logic        flip,               // game flip (A000 / A001)
    input  logic        crt_flip,
    input  logic  [8:0] scroll_x,
    input  logic  [7:0] scroll_y,
    input  logic  [7:0] pri,                // A000 data: bit 2 enable, bits 7-4 text category under the sprites
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    output logic  [8:0] hcnt,
    output logic  [8:0] vcnt,
    output logic        vblank_start,

    output logic [10:0] tx_a,               // text RAM (xram port B)
    input  logic  [7:0] tx_q,
    output logic [11:0] bg_a,               // background RAM (vram port B)
    input  logic  [7:0] bg_q,
    output logic [10:0] spr_a,              // sprite registers x780-x7FF of the three sprite RAM banks
    input  logic  [7:0] spr_q0,
    input  logic  [7:0] spr_q1,
    input  logic  [7:0] spr_q2,
    output logic [12:0] txt_rom_a,          // chars region, slot 0
    output logic [12:0] bg_rom_a,           // tiles region, slot 1
    input  logic  [7:0] tile_rom_q,
    output logic [14:0] spr_rom_a,          // sprites region (port B)
    input  logic  [7:0] spr_rom_q,
    output logic [10:0] clut_a,             // colour PROMs, port B: RGB, background lookup
    input  logic  [7:0] clut_q,
    output logic [10:0] slut_a,             // port A: sprite lookup
    input  logic  [7:0] slut_q,
    output logic  [9:0] lbuf_wa,
    output logic  [8:0] lbuf_wd,
    output logic        lbuf_we,
    output logic  [9:0] lbuf_ra,
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

/////////////////////////////  Timing  /////////////////////////////

logic [8:0] hc = 9'd0, vc = 9'd0;                      // free-running: hc[1:0] tracks div[4:3]
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

/////////////////////////////  Text layer  /////////////////////////////

// Super Pac pipeline: code / colour of tile t+2 at k = 6 / 7, char bytes of tile t+1 at k = 0 / 4 (slot 0).
// tflip mirrors positions (game flip ^ CRT flip); glyph pixels mirror with the CRT flip only.
wire       tflip = flip ^ crt_flip;
wire [5:0] tcur  = hc[8:3];
wire [2:0] k     = hc[2:0];
wire [5:0] tc1   = (tcur == 6'd47) ? 6'd0 : tcur + 6'd1;
wire [8:0] yc1   = (tcur == 6'd47) ? vnext : vc;
wire [5:0] tc2   = (tcur >= 6'd46) ? tcur - 6'd46 : tcur + 6'd2;
wire [8:0] yc2   = (tcur >= 6'd46) ? vnext : vc;

wire [8:0] my1   = tflip ? 9'd223 - yc1 : yc1;
wire [8:0] my2   = tflip ? 9'd223 - yc2 : yc2;
wire [5:0] mc2   = tflip ? 6'd35 - tc2 : tc2;
wire [5:0] cc2   = mc2 - 6'd2;                          // MAME col - 2: bit 5 = fixed side columns
wire [5:0] row2  = my2[8:3];
wire [4:0] srw2  = row2[4:0] + 5'd2;
wire [9:0] map_tx = cc2[5] ? {cc2[4:0], srw2} : {srw2, cc2[4:0]};
assign tx_a = {k[0], map_tx};                           // k = 6: code, k = 7: colour

logic [7:0] code1, code2, attr1, attr2, tb0n, tb1n, tb0, tb1, tattr, tcode;

wire       half  = k[2] ^ ~crt_flip;                   // bytes 8-15 = glyph pixels 0-3
wire [2:0] trow  = my1[2:0] ^ {3{flip}};               // game flip: glyph rows not mirrored
assign txt_rom_a = {flip, code1, half, trow};

always_ff @(posedge clk) begin
    if (ph == 3'd6) begin
        if (k == 3'd6) code2 <= tx_q;
        if (k == 3'd7) attr2 <= tx_q;
        if (k == 3'd0) tb0n <= tile_rom_q;
        if (k == 3'd4) tb1n <= tile_rom_q;
    end
    if (ce && k == 3'd7) begin
        tb0   <= tb0n;
        tb1   <= tb1n;
        tattr <= attr1;
        tcode <= code1;
        code1 <= code2;
        attr1 <= attr2;
    end
end

wire [7:0] tbyte = k[2] ? tb1 : tb0;
wire [1:0] ti    = crt_flip ? ~k[1:0] : k[1:0];
wire [1:0] tpen  = {tbyte[{1'b1, ~ti}], tbyte[{1'b0, ~ti}]};

/////////////////////////////  Background  /////////////////////////////

// Map position of screen pixel (x, y): base +/- x, base +/- y, the sign set by game flip ^ CRT flip (CRT flip takes the
// native pixel at 287 - x / 223 - y). During screen tile t the layer fetches the tile under screen x = 8t + 16 (two
// tiles ahead; next line from t = 46): code + attribute at k = 0, ROM bytes in slot 1 at k = 1 / 5, stored by tile
// number bits 1-0 (the displayed tiles are 1-2 tiles behind, never the same entry).
wire       bmir = flip ^ crt_flip;
wire [8:0] sxf  = scroll_x ^ {8'd0, flip};
wire [8:0] bxb  = flip ? (crt_flip ? 9'd189 - sxf : 9'd476 - sxf) : (crt_flip ? 9'd322 + sxf : 9'd35 + sxf);
wire [7:0] byb  = flip ? (crt_flip ? 8'd7 - scroll_y : 8'd230 - scroll_y) : (crt_flip ? 8'd248 + scroll_y : 8'd25 + scroll_y);

wire [8:0] fx   = (tcur >= 6'd46) ? {tcur, 3'd0} - 9'd368 : {tcur, 3'd0} + 9'd16;
wire [8:0] fy   = (tcur >= 6'd46) ? vnext : vc;
wire [8:0] fbx  = bmir ? bxb - fx : bxb + fx;
wire [7:0] fby  = bmir ? byb - fy[7:0] : byb + fy[7:0];

logic [5:0] bt;                                         // tile column being fetched
logic [2:0] brow;
logic [7:0] bcode, battr, blo;
logic [7:0] bl_lo[4], bl_hi[4];
logic [6:0] bl_col[4];

assign bg_a     = {ph[2], fby[7:3], fbx[8:3]};         // ph 0-3 code, 4-7 attribute (k = 0)
assign bg_rom_a = {battr[0], bcode, brow, k[2]};       // k = 1: pixels 0-3, k = 5: 4-7

always_ff @(posedge clk) begin
    if (k == 3'd0) begin
        if (ph == 3'd3) begin bcode <= bg_q; bt <= fbx[8:3]; brow <= fby[2:0]; end
        if (ph == 3'd7) battr <= bg_q;
    end
    if (ph == 3'd6 && k == 3'd1) blo <= tile_rom_q;
    if (ph == 3'd6 && k == 3'd5) begin
        bl_lo[bt[1:0]]  <= blo;
        bl_hi[bt[1:0]]  <= tile_rom_q;
        bl_col[bt[1:0]] <= {battr[0], battr[6:1]};
    end
end

// displayed pixel
wire [8:0] dbx  = bmir ? bxb - hc : bxb + hc;
wire [7:0] bbyte = dbx[2] ? bl_hi[dbx[4:3]] : bl_lo[dbx[4:3]];
wire [1:0] bpen  = {bbyte[{1'b1, ~dbx[1:0]}], bbyte[{1'b0, ~dbx[1:0]}]};
wire [6:0] bcol  = bl_col[dbx[4:3]];

/////////////////////////////  Colour mix  /////////////////////////////

// Pixel at hcnt: background lookup at ph 0-1, then the R / G / B PROMs at ph 2-4; output during the next pixel.
logic [7:0] bg_c, spr_c;
logic [7:0] tx_c;
logic       tx_on, tx_low;
logic [3:0] pr_q, pg_q, pb_q;

wire       spr_on = spr_c != 8'hFF;
wire [7:0] pix    = (tx_on && !tx_low) ? tx_c : spr_on ? spr_c : tx_on ? tx_c : bg_c;

always_comb begin
    if (ph <= 3'd1)      clut_a = 11'h300 + {2'b00, bcol, bpen};
    else if (ph == 3'd2) clut_a = {3'd0, pix};
    else if (ph == 3'd3) clut_a = 11'h100 + {3'd0, pix};
    else                 clut_a = 11'h200 + {3'd0, pix};
end
assign lbuf_ra = {vc[0], hc};

always_ff @(posedge clk) begin
    if (ph == 3'd1) begin
        bg_c   <= clut_q;
        spr_c  <= lbuf_rq[7:0];
        tx_c   <= {tattr[5:0], tpen};
        tx_on  <= tpen != 2'd0;
        tx_low <= pri[2] && tcode[7:4] == pri[7:4];
    end
    if (ph == 3'd3) pr_q <= clut_q[3:0];
    if (ph == 3'd4) pg_q <= clut_q[3:0];
    if (ph == 3'd5) pb_q <= clut_q[3:0];
end

wire [8:0] hs_on = 9'd312 + {{4{h_adj[3]}}, h_adj, 1'b0};    // 24 px front porch, 32 sync
wire [8:0] vs_on = 9'd232 + {{5{v_adj[3]}}, v_adj};          // 8 lines front porch, 8 sync
wire       h_vis = hc < 9'd288;
wire       v_vis = vc < 9'd224;

always_ff @(posedge clk) begin
    if (ce) begin
        r      <= (h_vis && v_vis) ? {pr_q, pr_q} : 8'd0;
        g      <= (h_vis && v_vis) ? {pg_q, pg_q} : 8'd0;
        b      <= (h_vis && v_vis) ? {pb_q, pb_q} : 8'd0;
        hblank <= ~h_vis;
        vblank <= ~v_vis;
        hs     <= ~(hc >= hs_on && hc < hs_on + 9'd32);
        vs     <= ~(vc >= vs_on && vc < vs_on + 9'd8);
    end
end

/////////////////////////////  Sprite engine  /////////////////////////////

// During line L the engine draws line L+1 into the other half of the line buffer: clear 288 pixels to FF, then the
// 64 sprites in order (later ones on top). CRT flip: the line drawn is picture line 223 - L+1, each pixel at 287 - x.
localparam S_IDLE = 3'd0, S_CLR = 3'd1, S_RD0 = 3'd2, S_RD1 = 3'd3, S_RD2 = 3'd4, S_EVAL = 3'd5, S_ROM = 3'd6,
           S_PIX = 3'd7;
logic [2:0] st = S_IDLE;
logic [8:0] tgt, clr;
logic       bw;
logic [5:0] s;
logic [7:0] n0, c0, y0, x0, a0, a1;
logic       szx, szy, sflx, sfly, tx, ty, bsel;
logic [3:0] sr;
logic [1:0] gcol, pcnt, wcnt;
logic [9:0] sx;
logic [8:0] code;
logic [7:0] sb0, sb1;

assign spr_a = {4'hF, s, st == S_RD1};

// EVAL (MAME: sy = ((249 - y - 16 * y size) & 0xFF) - 32, one-line buffer delay as the Mappy board)
wire        e_szx = a0[2], e_szy = a0[3];
wire  [7:0] e_s1  = 8'd249 - y0 - {3'd0, e_szy, 4'd0};
wire  [9:0] e_row = {1'b0, tgt} + 10'd32 - {2'd0, e_s1};
wire        e_vis = !e_row[9] && (e_row[8:5] == 4'd0) && (e_szy || !e_row[4]);

wire  [1:0] bcol_s = sflx ? ~gcol : gcol;
wire  [8:0] scode  = code + {7'd0, ty ^ (szy & sfly), tx ^ (szx & sflx)};
assign spr_rom_a   = bsel ? {2'b10, scode[6:0], sr[3], bcol_s, sr[2:0]} :
                     scode[8] ? {2'b11, scode[6:0], sr[3], bcol_s, sr[2:0]} : {1'b0, scode[7:0], sr[3], bcol_s, sr[2:0]};

wire  [1:0] pi    = sflx ? ~pcnt : pcnt;
wire  [1:0] spen2 = {sb0[{1'b1, ~pi}], sb0[{1'b0, ~pi}]};
wire        sp0   = !scode[8] && (scode[7] ? sb1[{1'b1, ~pi}] : sb1[{1'b0, ~pi}]);
wire  [9:0] px    = sx + {5'd0, tx, gcol, pcnt};
wire  [8:0] pxf   = crt_flip ? 9'd287 - px[8:0] : px[8:0];
logic [8:0] px1, px2;
logic       pv1 = 1'b0, pv2 = 1'b0;

always_ff @(posedge clk) begin
    pv1 <= 1'b0;
    if (st == S_PIX) begin
        slut_a <= 11'h500 + {2'b00, c0[5:0], sp0, spen2};
        px1    <= pxf;
        pv1    <= !px[9] && px[8:0] < 9'd288;
    end
    px2 <= px1;
    pv2 <= pv1;
end

assign lbuf_we = (st == S_CLR) || (pv2 && slut_q != 8'hFF);
assign lbuf_wa = (st == S_CLR) ? {bw, clr} : {bw, px2};
assign lbuf_wd = (st == S_CLR) ? 9'h0FF : {1'b0, slut_q};

always_ff @(posedge clk) begin
    if (ce && hc == 9'd383) begin
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
            sflx <= a0[0] ^ flip;
            sfly <= a0[1] ^ flip;
            code <= {a0[7], n0} & {7'h7F, ~e_szy, ~e_szx};
            ty   <= e_row[4];
            sr   <= (a0[1] ^ flip) ? ~e_row[3:0] : e_row[3:0];
            sx   <= {1'b0, a1[0], x0} - 10'd71;
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
                if (!bsel) begin sb0 <= spr_rom_q; bsel <= 1'b1; end
                else begin sb1 <= spr_rom_q; bsel <= 1'b0; pcnt <= 2'd0; st <= S_PIX; end
            end
        end
        S_PIX: begin
            pcnt <= pcnt + 2'd1;
            if (pcnt == 2'd3) begin
                wcnt <= 2'd0;
                if ({tx, gcol} != {szx, 2'b11}) begin {tx, gcol} <= {tx, gcol} + 3'd1; st <= S_ROM; end
                else if (s == 6'd63) st <= S_IDLE;
                else begin s <= s + 6'd1; st <= S_RD0; end
            end
        end
        default: st <= S_IDLE;
    endcase
end

/* verilator lint_off UNUSED */
wire unused = ^a1[7:1] ^ ^lbuf_rq[8];
/* verilator lint_on UNUSED */

endmodule
