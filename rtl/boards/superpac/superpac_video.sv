//  Based on MAME mappy_v.cpp, gaplus_v.cpp (Manuel Abadia, Ernesto Corvi, Nicola Salmoria, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module superpac_video
(
    input  logic        clk,
    input  logic  [4:0] div,                // board divider: one pixel per div[2:0] cycle, hcnt[1:0] = div[4:3]
    input  logic        mappy,
    input  logic        phozon,
    input  logic        gaplus,
    input  logic [3:0][7:0] star_ctl,
    input  logic        sprbig,
    input  logic        slut64,
    input  logic        flip,
    input  logic        crt_flip,
    input  logic  [7:0] scroll,
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    output logic  [8:0] hcnt,
    output logic  [8:0] vcnt,
    output logic        vblank_start,

    output logic [11:0] vram_a,
    input  logic  [7:0] vram_q,
    output logic [10:0] spr_a,
    input  logic  [7:0] spr_q0,
    input  logic  [7:0] spr_q1,
    input  logic  [7:0] spr_q2,
    output logic [12:0] tile_rom_a,
    input  logic  [7:0] tile_rom_q,
    output logic [14:0] spr_rom_a,
    input  logic  [7:0] spr_rom_q,
    output logic  [9:0] clut_a,
    input  logic  [7:0] clut_q,
    output logic [10:0] slut_a,
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

logic [8:0] hc = 9'd0, vc = 9'd0;
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

logic      ph_flip = 1'b0;
wire       gflip = (phozon || gaplus) ? ph_flip : flip;
wire       tflip = gflip ^ crt_flip;
wire [5:0] tcur  = hc[8:3];
wire [2:0] k     = hc[2:0];
wire [5:0] tc1   = (tcur == 6'd47) ? 6'd0 : tcur + 6'd1;
wire [8:0] yc1   = (tcur == 6'd47) ? vnext : vc;
wire [5:0] tc2   = (tcur >= 6'd46) ? tcur - 6'd46 : tcur + 6'd2;
wire [8:0] yc2   = (tcur >= 6'd46) ? vnext : vc;

wire [8:0] my1   = tflip ? 9'd223 - yc1 : yc1;
wire [8:0] my2   = tflip ? 9'd223 - yc2 : yc2;
wire [5:0] mc1   = tflip ? 6'd35 - tc1 : tc1;
wire [5:0] mc2   = tflip ? 6'd35 - tc2 : tc2;
wire [5:0] cc1   = mc1 - 6'd2;
wire [5:0] cc2   = mc2 - 6'd2;

wire [8:0] sy1   = (mappy && !cc1[5]) ? my1 + {1'b0, scroll} : my1;
wire [8:0] sy2   = (mappy && !cc2[5]) ? my2 + {1'b0, scroll} : my2;
wire [5:0] row2  = sy2[8:3];
wire [4:0] srw2  = row2[4:0] + 5'd2;

wire [9:0]  map_sp = cc2[5] ? {cc2[4:0], srw2} : {srw2, cc2[4:0]};
wire [3:0]  frw2   = row2[3:0] + 4'd2;
wire [10:0] map_mp = cc2[5] ? {4'b1111, cc2[1:0], row2[4], frw2} : {row2, cc2[4:0]};

assign vram_a = mappy ? {k[0], map_mp} : {1'b0, k[0], map_sp};

logic [7:0] code1, code2, attr1, attr2, tb0n, tb1n, tb0, tb1, tattr;
logic [7:0] gbn[4], gb[4];

wire half = k[2] ^ ~tflip;
wire [1:0] g_pr = {k[2], ph[2]} ^ {2{tflip}};
assign tile_rom_a = gaplus ? {code1, ~g_pr[1], g_pr[0], sy1[2:0]} :
                    {phozon & attr1[7], code1, half, sy1[2:0]};
wire [7:0] tile_d = mappy ? ~tile_rom_q : tile_rom_q;

always_ff @(posedge clk) begin
    if (ph == 3'd6) begin
        if (k == 3'd6) code2 <= vram_q;
        if (k == 3'd7) attr2 <= vram_q;
        if (k == 3'd0) tb0n <= tile_d;
        if (k == 3'd4) tb1n <= tile_d;
    end
    if (ph == 3'd5 && k[1:0] == 2'd0) gbn[{k[2], 1'b0}] <= tile_rom_q;
    if (ph == 3'd7 && k[1:0] == 2'd0) gbn[{k[2], 1'b1}] <= tile_rom_q;
    if (ce && k == 3'd7) begin
        tb0   <= tb0n;
        tb1   <= tb1n;
        for (int j = 0; j < 4; j++) gb[j] <= gbn[j];
        tattr <= attr1;
        code1 <= code2;
        attr1 <= attr2;
    end
end

wire [7:0] tbyte = k[2] ? tb1 : tb0;
wire [1:0] ti    = tflip ? ~k[1:0] : k[1:0];
wire [1:0] tpen2 = {tbyte[{1'b1, ~ti}], tbyte[{1'b0, ~ti}]};
wire [7:0] gbyte = gb[k[2:1]];
wire [3:0] gnib  = tattr[7] ? gbyte[7:4] : gbyte[3:0];
wire [1:0] tpen  = !gaplus ? tpen2 : (k[0] ^ tflip) ? {gnib[2], gnib[0]} : {gnib[3], gnib[1]};

logic [3:0] ctab_c;
logic [8:0] spr_c;
logic       prio_c;
logic [7:0] pal_q;
logic [3:0] pr_q, pg_q, pb_q;

wire [3:0] ct      = (mappy || phozon || gaplus) ? ctab_c : ~ctab_c;
wire       spr_on  = spr_c[3:0] != 4'hF;
wire       tile_hi = prio_c && ct != 4'hF;
wire       sprio   = !mappy && !phozon && spr_on && spr_c[3:1] == 3'd0;
wire [4:0] tcol    = {~phozon, ct};
wire [4:0] scol    = {phozon, spr_c[3:0]};
wire [4:0] pix5    = sprio ? scol : tile_hi ? tcol : spr_on ? scol : tcol;
wire       g_spr   = !spr_c[8] && spr_c[7:0] != 8'hFF;
wire [7:0] gtcol   = {4'hF, ct};
wire [7:0] gpix    = tile_hi ? gtcol : g_spr ? spr_c[7:0] : (ct != 4'hF) ? gtcol : spr_c[8] ? spr_c[7:0] : gtcol;
wire [7:0] pix     = gaplus ? gpix : {3'd0, pix5};

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

function automatic [7:0] lvl3(input [2:0] v);
    lvl3 = (v[0] ? 8'd33 : 8'd0) + (v[1] ? 8'd71 : 8'd0) + (v[2] ? 8'd151 : 8'd0);
endfunction
function automatic [7:0] lvl2(input [1:0] v);
    lvl2 = (v[0] ? 8'd81 : 8'd0) + (v[1] ? 8'd174 : 8'd0);
endfunction
function automatic [7:0] lvl4(input [3:0] v);
    case (v)
        4'd0: lvl4 = 8'd0;    4'd1: lvl4 = 8'd14;   4'd2: lvl4 = 8'd31;   4'd3: lvl4 = 8'd46;
        4'd4: lvl4 = 8'd67;   4'd5: lvl4 = 8'd81;   4'd6: lvl4 = 8'd98;   4'd7: lvl4 = 8'd112;
        4'd8: lvl4 = 8'd143;  4'd9: lvl4 = 8'd157;  4'd10: lvl4 = 8'd174; 4'd11: lvl4 = 8'd188;
        4'd12: lvl4 = 8'd209; 4'd13: lvl4 = 8'd224; 4'd14: lvl4 = 8'd241; default: lvl4 = 8'd255;
    endcase
endfunction

function automatic [7:0] lvl4g(input [3:0] v);
    lvl4g = (v[0] ? 8'd14 : 8'd0) + (v[1] ? 8'd31 : 8'd0) + (v[2] ? 8'd67 : 8'd0) + (v[3] ? 8'd143 : 8'd0);
endfunction

wire [8:0] hs_on = 9'd312 + {{4{h_adj[3]}}, h_adj, 1'b0};
wire [8:0] vs_on = 9'd232 + {{5{v_adj[3]}}, v_adj};
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
logic [9:0] p_code;
logic [1:0] p_szx, p_szy, p_ty;
logic [8:0] g_code;
logic       g_dup, hp;

wire rd_flip = (phozon || gaplus) && st == S_IDLE && vc == 9'd230;
assign spr_a = rd_flip ? 11'h77F : {4'hF, s, st == S_RD1};
always_ff @(posedge clk) if (ce && rd_flip && hc == 9'd8) ph_flip <= spr_q2[0];

function automatic [1:0] p_size(input [1:0] c);
    p_size = (c == 2'd0) ? 2'd1 : (c == 2'd2) ? 2'd3 : 2'd0;
endfunction
wire  [1:0] pe_szx = p_size(a0[3:2]);
wire  [1:0] pe_szy = p_size(a0[5:4]);
wire  [7:0] pe_s1  = 8'd0 - y0 - {3'd0, pe_szy, 3'd0};
wire  [9:0] pe_row = {1'b0, tgt} + 10'd32 - {2'd0, pe_s1};
wire        pe_vis = ~a1[1] && !pe_row[9] && (pe_row[8:3] <= {4'd0, pe_szy});

wire        e_szx = gaplus ? a0[3] : a0[2];
wire        e_szy = gaplus ? a0[5] : a0[3];
wire  [7:0] e_s1  = (gaplus ? 8'd248 : 8'd1) - y0 - {3'd0, e_szy, 4'd0};
wire  [9:0] e_row = {1'b0, tgt} + 10'd32 - {2'd0, e_s1};
wire        e_vis = ~a1[1] && !e_row[9] && (e_row[8:5] == 4'd0) && (e_szy || !e_row[4]);

wire  [1:0] bcol  = flx ? ~gcol : gcol;
wire  [7:0] tcode = code + {6'd0, ty ^ (szy & fly), tx ^ (szx & flx)};
wire  [1:0] p_xx  = {tx, gcol[1]} ^ (flx ? p_szx : 2'd0);
wire  [1:0] p_yy  = p_ty ^ (fly ? p_szy : 2'd0);
wire  [9:0] p_til = p_code + {6'd0, p_yy[1], p_xx[1], p_yy[0], p_xx[0]};
wire  [8:0] g_t   = g_code + (g_dup ? 9'd0 : {7'd0, ty ^ (szy & fly), tx ^ (szx & flx)});
wire  [8:0] g_n   = (g_t[8:7] == 2'b11) ? {2'b00, g_t[6:0]} : g_t;
assign spr_rom_a  = gaplus ? (bsel ? {2'b11, g_n[6:0], sr[3], bcol, sr[2:0]} : {g_n, sr[3], bcol, sr[2:0]}) :
                    phozon ? {2'b00, p_til[8:0], gcol[0] ^ flx, sr[2:0]} :
                    {mappy & sprbig & bsel, mappy ? (sprbig ? tcode[7] : bsel) : (sprbig & tcode[7]), tcode[6:0], sr[3], bcol,
                     sr[2:0]};
wire  [2:0] g_last = phozon ? {p_szx, 1'b1} : {szx, 2'b11};

wire  [1:0] pi    = flx ? ~pcnt : pcnt;
wire  [1:0] spen2 = {sb0[{1'b1, ~pi}], sb0[{1'b0, ~pi}]};
wire  [3:0] spen4 = {sb0[{1'b1, ~pi}], sb0[{1'b0, ~pi}], sb1[{1'b1, ~pi}], sb1[{1'b0, ~pi}]};
wire  [9:0] px    = sx + {5'd0, tx, gcol, pcnt};
wire  [8:0] pxf   = crt_flip ? 9'd287 - px[8:0] : px[8:0];
wire        gp0   = !g_n[8] && (g_n[7] ? sb1[{1'b0, ~pi}] : sb1[{1'b1, ~pi}]);
wire  [8:0] g_idx = {c0[5:0], gp0, spen2};

logic [2:0][7:0] st_ox = '0, st_oy = '0;
logic [7:0] st_fc = 8'd0;
always_ff @(posedge clk) begin
    if (ce && hc == 9'd383 && vc == 9'd229) begin
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
    if (ce && hc == 9'd383) begin
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
        S_STAR: begin
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
        S_ROM: begin
            wcnt <= wcnt + 2'd1;
            if (wcnt == 2'd2) begin
                wcnt <= 2'd0;
                if (!bsel) sb0 <= spr_rom_q;
                else       sb1 <= spr_rom_q;
                if ((mappy || gaplus) && !bsel) bsel <= 1'b1;
                else begin bsel <= 1'b0; pcnt <= 2'd0; st <= S_PIX; end
            end
        end
        S_PIX: if (gaplus && !hp) hp <= 1'b1;
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
