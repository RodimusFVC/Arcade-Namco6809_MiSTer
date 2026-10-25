//============================================================================
//
//  Namco 15XX waveform sound generator (8 voices) + the boards' volume DACs, written from MAME
//  devices/sound/namco.cpp (namco_15xx_device; Nicola Salmoria, Aaron Giles) and the Mappy / Super Pac-Man CPU
//  board schematics.
//  Copyright (C) 2026 Rodimus
//
//  Registers = the first 64 bytes of the CPU-shared sound RAM, snooped on write (8 bytes per voice):
//    +2 counter MSBs (bits 4-0 = waveform step; Grobda's DAC trick), +3 volume (bits 3-0),
//    +4 / +5 frequency bits 7-0 / 15-8, +6 bits 3-0 frequency 19-16, bits 6-4 waveform
//  One sample per voice at 24 kHz (18.432 MHz / 768): a 20-bit phase accumulator per voice, waveform PROM
//  address {waveform, phase[19:15]}. The 8 voices are time-multiplexed into the board DAC (one slot each).
//  dac_mode 0: Super Pac-Man LS273 4M + 4066 4L ladder, simulated per voice slot (tools/superpac_dac.py:
//              exact RC update of the output node C25 for each 5.2 us slot, then the slot average, DC removed).
//              SOUND ON clears the LS273: volume switches open, waveform bits low.
//  dac_mode 1: Mappy / Gaplus 99XX (custom, undocumented): MAME's linear (sample - 8) x volume sum.
//
//============================================================================

module namco_15xx
(
    input  logic clk,
    input  logic reset,
    input  logic smp,                           // one clock per 24 kHz sample period
    input  chip_pool_pkg::wsg15_i_t i,
    output chip_pool_pkg::wsg15_o_t o
);

logic  [3:0] vol[8];
logic [19:0] freq[8], acc[8];
logic  [2:0] wsel[8];
logic  [7:0] reg2[8];

wire [2:0] wch = i.reg_addr[5:3];

// sequencer: 8 clocks per voice slot (PROM address, wait, sample, DAC pipeline); seq[6] = idle
logic  [6:0] seq = 7'd64;
wire   [2:0] v  = seq[5:3];
wire   [2:0] ph = seq[2:0];
logic  [7:0] wave_a;
logic [15:0] sound;

/////////////////////////////  dac_mode 1: linear  /////////////////////////////

logic signed [12:0] sum;
wire  signed  [4:0] wsmp = $signed({1'b0, i.wave_d}) - 5'sd8;
wire  signed  [9:0] prod_l = wsmp * $signed({1'b0, vol[v]});

/////////////////////////////  dac_mode 0: Super Pac-Man ladder  /////////////////////////////

// tables from tools/superpac_dac.py: w = waveform node (Q14 V), g = volume conductance (uS x 16), b = RC step
function automatic [15:0] tab_w(input [3:0] s);
    case (s)
        4'd0: tab_w = 16'd0;      4'd1: tab_w = 16'd3123;   4'd2: tab_w = 16'd6672;   4'd3: tab_w = 16'd9795;
        4'd4: tab_w = 16'd14679;  4'd5: tab_w = 16'd17802;  4'd6: tab_w = 16'd21351;  4'd7: tab_w = 16'd24474;
        4'd8: tab_w = 16'd31231;  4'd9: tab_w = 16'd34355;  4'd10: tab_w = 16'd37904; 4'd11: tab_w = 16'd41027;
        4'd12: tab_w = 16'd45910; 4'd13: tab_w = 16'd49033; 4'd14: tab_w = 16'd52582; default: tab_w = 16'd55706;
    endcase
endfunction
function automatic [11:0] tab_g(input [3:0] s);
    case (s)
        4'd0: tab_g = 12'd0;      4'd1: tab_g = 12'd160;    4'd2: tab_g = 12'd339;    4'd3: tab_g = 12'd496;
        4'd4: tab_g = 12'd719;    4'd5: tab_g = 12'd874;    4'd6: tab_g = 12'd1049;   4'd7: tab_g = 12'd1203;
        4'd8: tab_g = 12'd1559;   4'd9: tab_g = 12'd1710;   4'd10: tab_g = 12'd1880;  4'd11: tab_g = 12'd2030;
        4'd12: tab_g = 12'd2241;  4'd13: tab_g = 12'd2389;  4'd14: tab_g = 12'd2555;  default: tab_g = 12'd2702;
    endcase
endfunction
function automatic [12:0] tab_b(input [3:0] s);
    case (s)
        4'd0: tab_b = 13'd4263;   4'd1: tab_b = 13'd4241;   4'd2: tab_b = 13'd4215;   4'd3: tab_b = 13'd4193;
        4'd4: tab_b = 13'd4162;   4'd5: tab_b = 13'd4140;   4'd6: tab_b = 13'd4116;   4'd7: tab_b = 13'd4095;
        4'd8: tab_b = 13'd4048;   4'd9: tab_b = 13'd4027;   4'd10: tab_b = 13'd4005;  4'd11: tab_b = 13'd3985;
        4'd12: tab_b = 13'd3958;  4'd13: tab_b = 13'd3939;  4'd14: tab_b = 13'd3917;  default: tab_b = 13'd3899;
    endcase
endfunction

localparam signed [31:0] K5     = 32'sd59578182;    // 22K pull-up to +5 V (uA x 2^18)
localparam signed [12:0] GF16   = 13'sd2531;        // fixed node conductance 22K || 12K || 34K (uS x 16)
localparam signed [23:0] V_IDLE = 24'sd1506412;     // 5 V through the 22K / (12K || 34K) divider: 1.4366 V (Q20)

logic signed [23:0] vnode = V_IDLE, dc = V_IDLE;    // node voltage, DC tracker (Q20 V)
logic signed [26:0] vsum = 27'(V_IDLE) <<< 3;
logic        [15:0] wl;
logic        [11:0] gl;
logic        [12:0] bl;
logic signed [17:0] diff;
logic signed [31:0] cterm, e;
logic signed [30:0] prod;
logic signed [23:0] dv;

wire  signed [17:0] v14   = 18'(vnode >>> 6);
wire  signed [26:0] e27   = 27'(e >>> 2);           // |e| < 2^28: one 27 x 14 DSP multiply below
wire  signed [40:0] eb    = e27 * $signed({1'b0, bl});
wire  signed [23:0] vavg  = 24'(vsum >>> 3);
wire  signed [23:0] ac    = vavg - dc;
wire  signed [39:0] out_s = ac * 16'sd1250;          // ~20000 / V: the loudness of the linear build (HW 2026-10-25)
wire  signed [19:0] out_c = 20'(out_s >>> 16);

/////////////////////////////  Sequencer  /////////////////////////////

always_ff @(posedge clk) begin
    if (reset) begin
        for (int k = 0; k < 8; k++) begin
            vol[k] <= 4'd0;  freq[k] <= 20'd0;  wsel[k] <= 3'd0;  reg2[k] <= 8'd0;  acc[k] <= 20'd0;
        end
        seq   <= 7'd64;
        sound <= 16'd0;
        vnode <= V_IDLE;
        dc    <= V_IDLE;
        vsum  <= 27'(V_IDLE) <<< 3;
    end
    else begin
        if (i.reg_wr) case (i.reg_addr[2:0])
            3'd2: if (i.reg_din != reg2[wch]) begin
                      reg2[wch] <= i.reg_din;
                      acc[wch]  <= {i.reg_din[4:0], acc[wch][14:0]};
                  end
            3'd3: vol[wch] <= i.reg_din[3:0];
            3'd4: freq[wch][7:0]   <= i.reg_din;
            3'd5: freq[wch][15:8]  <= i.reg_din;
            3'd6: begin freq[wch][19:16] <= i.reg_din[3:0];  wsel[wch] <= i.reg_din[6:4]; end
            default: ;
        endcase

        if (smp) begin                          // previous sample complete (seq idle): output it, start the next
            seq  <= 7'd0;
            sum  <= 13'sd0;
            vsum <= 27'sd0;
            if (i.dac_mode == 2'd0) begin
                sound <= (out_c > 20'sd32767) ? 16'h7FFF : (out_c < -20'sd32768) ? 16'h8000 : out_c[15:0];
                dc    <= dc + ((vavg - dc) >>> 10);      // ~4 Hz DC removal (the amp input is AC-coupled)
            end
            else sound <= i.sound_en ? {sum[10:0], 5'd0} : 16'd0;
        end
        else if (!seq[6]) seq <= seq + 7'd1;

        if (!seq[6]) case (ph)
            3'd0: wave_a <= {wsel[v], acc[v][19:15]};
            3'd2: begin
                sum <= sum + 13'(prod_l);
                if (!(i.reg_wr && i.reg_addr[2:0] == 3'd2 && wch == v)) acc[v] <= acc[v] + freq[v];
                wl <= i.sound_en ? tab_w(i.wave_d) : 16'd0;   // LS273 cleared by SOUND ON
                gl <= i.sound_en ? tab_g(vol[v])  : 12'd0;
                bl <= i.sound_en ? tab_b(vol[v])  : tab_b(4'd0);
            end
            3'd3: begin
                diff  <= $signed({2'b00, wl}) - v14;
                cterm <= K5 - GF16 * v14;
            end
            3'd4: prod <= $signed({1'b0, gl}) * diff;
            3'd5: e <= 32'(prod) + cterm;
            3'd6: dv <= 24'(eb >>> 18);
            3'd7: begin
                vnode <= vnode + dv;
                vsum  <= vsum + 27'(vnode) + 27'(dv);
            end
            default: ;
        endcase
    end
end

assign o.wave_a = wave_a;
assign o.sound  = sound;

endmodule
