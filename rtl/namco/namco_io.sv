//============================================================================
//
//  Namco 56XX / 58XX / 59XX custom I/O (MB8843, undumped) - behavioural model, written from MAME namco/namcoio.cpp
//  (Nicola Salmoria). Kind (index 1 byte 2): 0 = 56XX, 1 = 58XX, 2 = 59XX.
//  Copyright (C) 2026 Rodimus
//
//  CPU side = the 16XX nibble buffer: 16 nibbles, read as F0 | nibble. The command in nibble 8 runs once per
//  frame (run strobe, MAME customio_run 50 us after vblank) while the chip is out of reset.
//  Port pins: in[3:0] pins 38-41, in[7:4] 22-25, in[11:8] 26-29, in[15:12] 30-33 (active low, as MAME's ports);
//  out[3:0] pins 13-16, out[7:4] 17-20.
//
//============================================================================

module namco_io
(
    input  logic clk,
    input  logic reset,                         // power-on: nibble RAM cleared (MAME device_reset)
    input  chip_pool_pkg::namcoio_i_t i,
    output chip_pool_pkg::namcoio_o_t o
);

logic [3:0] ram[16];
logic [3:0] out0 = 4'd0, out1 = 4'd0;

// coin / credit state (MAME handle_coins); reset by the 4 RESET line
logic [3:0] lastcoins, lastbuttons;
logic [3:0] coins[2], cpc[2], cpcred[2];        // coins inserted, coins per credit, credits per coin
logic [6:0] credits;                            // 0-99 (MAME's int is unbounded; capped here, #unverified)

wire [3:0] in0 = i.in[3:0], in1 = i.in[7:4], in2 = i.in[11:8], in3 = i.in[15:12];

assign o.dout = ram[i.addr];
assign o.out  = {out1, out0};

// handle_coins(0), evaluated in one clock from the current state
wire  [3:0] cval = ~in0;
wire  [3:0] ctog = cval ^ lastcoins;
wire  [3:0] bval = ~in3;
wire  [3:0] btog = bval ^ lastbuttons;

logic signed [5:0] add;
logic        [1:0] sub;
logic        [3:0] coins_n[2];
always_comb begin
    add = 6'sd0;
    coins_n[0] = coins[0];
    coins_n[1] = coins[1];
    for (int c = 0; c < 2; c++) begin
        if (cval[c] & ctog[c]) begin
            coins_n[c] = coins[c] + 4'd1;
            if (coins_n[c] >= {1'b0, cpc[c][2:0]}) begin
                add = $signed({2'b00, cpcred[c]}) - $signed({5'b0, cpc[c][3]});
                coins_n[c] = coins_n[c] - {1'b0, cpc[c][2:0]};
            end
            else if (cpc[c][3]) add = 6'sd1;
        end
    end
    if (cval[3] & ctog[3]) add = 6'sd1;         // service coin
    sub = 2'd0;
    if (ram[9] == 4'd0) begin                   // start buttons only while the game allows
        if (bval[2] & btog[2])      begin if (credits >= 7'd1) sub = 2'd1; end
        else if (bval[3] & btog[3]) begin if (credits >= 7'd2) sub = 2'd2; end
    end
end
wire signed [8:0] cr_sum = $signed({2'b00, credits}) + 9'(add) - $signed({7'b0, sub});
wire        [6:0] cr_new = cr_sum < 0 ? 7'd0 : cr_sum > 9'sd99 ? 7'd99 : cr_sum[6:0];
wire        [3:0] cr_hi  = 4'((11'(cr_new) * 11'd205) >> 11);    // /10 for 0-99
wire        [3:0] cr_lo  = 4'(cr_new - 7'(cr_hi) * 7'd10);

wire [6:0] chk_sum = 7'(ram[9]) + 7'(ram[10]) + 7'(ram[11]) + 7'(ram[12]) + 7'(ram[13]) + 7'(ram[14]) + 7'(ram[15]);

// Commands by chip kind (MAME namcoio.cpp customio_run):
//   56XX: 1 switches -> 0-3, 2 coinage, 4 coins (credits 0-1, add 2, sub 3), 7 boot check, 8 nibble sum, 9 DIP read
//   58XX: 1 switches -> 4-7, 2 coinage, 3 coins (swapped: add 0, sub 1, credits 2-3), 4 DIP read, 5 LFSR boot check
//   59XX: 3 inputs -> 4-7
// The DIP read samples port A (pins 38-41, behind a board-level LS157 steered by pin 13) twice: pin 13 = 0, then 1.
localparam S_IDLE = 3'd0, S_DIPA = 3'd1, S_DIPB = 3'd2, S_LFN = 3'd3, S_LFX = 3'd4;
logic [2:0] st = S_IDLE;
logic [1:0] wait_n;
logic [6:0] lf_cnt;
logic [7:0] lf_seed, lf_rng;
logic [2:0] lf_i, lf_t;
logic [3:0] lf_n;

wire k56 = i.kind == 2'd0, k58 = i.kind == 2'd1, k59 = i.kind == 2'd2;
wire [1:0] swap = k58 ? 2'd2 : 2'd0;

function automatic [7:0] nxt(input [7:0] x);    // MAME NEXT(): 7-bit LFSR step
    nxt = (x[0] ? x ^ 8'h90 : x) >> 1;
endfunction

logic [3:0] lf_arg;
always_comb begin
    case (lf_t)
        3'd0: lf_arg = ram[11];  3'd1: lf_arg = ram[10];  3'd2: lf_arg = ram[9];   3'd3: lf_arg = ram[15];
        3'd4: lf_arg = ram[14];  3'd5: lf_arg = ram[13];  default: lf_arg = ram[12];
    endcase
end
wire [3:0] lf_n2 = lf_rng[0] ? lf_n ^ ~lf_arg : lf_n;

always_ff @(posedge clk) begin
    if (i.wr) ram[i.addr] <= i.din;

    if (!i.reset_n) begin
        credits <= 7'd0;
        coins[0] <= 4'd0;  cpc[0] <= 4'd1;  cpcred[0] <= 4'd1;
        coins[1] <= 4'd0;  cpc[1] <= 4'd1;  cpcred[1] <= 4'd1;
        st <= S_IDLE;
    end
    else case (st)
        S_IDLE: if (i.run) begin
            if ((k56 || k58) && ram[8] == 4'd1) begin              // read switch inputs
                if (k56) begin ram[0] <= ~in0;  ram[1] <= ~in1;  ram[2] <= ~in2;  ram[3] <= ~in3; end
                else     begin ram[4] <= ~in0;  ram[5] <= ~in1;  ram[6] <= ~in2;  ram[7] <= ~in3; end
                out0 <= ram[9];  out1 <= ram[10];
            end
            if ((k56 || k58) && ram[8] == 4'd2) begin              // coinage settings
                cpc[0] <= ram[9];  cpcred[0] <= ram[10];  cpc[1] <= ram[11];  cpcred[1] <= ram[12];
            end
            if ((k56 && ram[8] == 4'd4) || (k58 && ram[8] == 4'd3)) begin    // coins and start, switch inputs
                lastcoins   <= cval;
                lastbuttons <= bval;
                coins[0] <= coins_n[0];
                coins[1] <= coins_n[1];
                credits  <= cr_new;
                ram[{2'b00, 2'd0 ^ swap}] <= cr_hi;
                ram[{2'b00, 2'd1 ^ swap}] <= cr_lo;
                if (add != 6'sd0) ram[{2'b00, 2'd2 ^ swap}] <= 4'(add);
                if (sub != 2'd0)  ram[{2'b00, 2'd3 ^ swap}] <= {2'b00, sub};
                ram[4] <= ~in1;
                ram[5] <= {bval[2], 1'b0, bval[0], 1'b0} | (bval & btog & 4'b0101);
                ram[6] <= ~in2;
                ram[7] <= (bval & 4'b1010) | ((bval & btog & 4'b1010) >> 1);
            end
            if (k56 && ram[8] == 4'd7) begin ram[2] <= 4'hE;  ram[7] <= 4'h6; end            // Libble Rabble
            if (k56 && ram[8] == 4'd8) begin ram[0] <= {1'b0, chk_sum[6:4]};  ram[1] <= chk_sum[3:0]; end
            if ((k56 && ram[8] == 4'd9) || (k58 && ram[8] == 4'd4)) begin    // DIP switches: pin 13 low first
                out0[0] <= 1'b0;  wait_n <= 2'd3;  st <= S_DIPA;
            end
            if (k58 && ram[8] == 4'd5) begin                       // boot check: LFSR seeded by nibbles 9-10
                lf_seed <= 8'h22;  lf_cnt <= {ram[9][2:0], ram[10]};  st <= S_LFN;
            end
            if (k59 && ram[8] == 4'd3) begin                       // Pac & Pal chip 1
                ram[4] <= ~in0;  ram[5] <= ~in2;  ram[6] <= ~in1;  ram[7] <= ~in3;
            end
        end
        S_DIPA: if (wait_n != 2'd0) wait_n <= wait_n - 2'd1;
                else begin
                    ram[0] <= ~in0;  ram[2] <= ~in1;  ram[4] <= ~in2;  ram[6] <= ~in3;
                    out0[0] <= 1'b1;  wait_n <= 2'd3;  st <= S_DIPB;
                end
        S_DIPB: if (wait_n != 2'd0) wait_n <= wait_n - 2'd1;
                else begin
                    ram[1] <= ~in0;  ram[3] <= ~in1;  ram[5] <= ~in2;  ram[7] <= ~in3;
                    st <= S_IDLE;
                end
        S_LFN: if (lf_cnt != 7'd0) begin lf_seed <= nxt(lf_seed);  lf_cnt <= lf_cnt - 7'd1; end
               else begin lf_rng <= lf_seed;  lf_i <= 3'd1;  lf_t <= 3'd0;  lf_n <= 4'd0;  st <= S_LFX; end
        S_LFX: begin                                               // 7 result nibbles x 7 taps
            lf_rng <= nxt(lf_rng);
            if (lf_t == 3'd0) lf_seed <= nxt(lf_rng);
            if (lf_t != 3'd6) begin lf_n <= lf_n2;  lf_t <= lf_t + 3'd1; end
            else begin
                ram[{1'b0, lf_i}] <= ~lf_n2;
                lf_n <= 4'd0;
                lf_t <= 3'd0;
                lf_rng <= lf_seed;
                if (lf_i == 3'd7) begin
                    ram[0] <= (ram[9] == 4'hF) ? 4'hF : 4'h0;      // MAME's Gaplus kludge
                    st <= S_IDLE;
                end
                else lf_i <= lf_i + 3'd1;
            end
        end
        default: st <= S_IDLE;
    endcase

    if (reset) begin
        for (int k = 0; k < 16; k++) ram[k] <= 4'd0;
        lastcoins <= 4'd0;
        lastbuttons <= 4'd0;
    end
end

endmodule
