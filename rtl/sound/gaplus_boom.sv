//============================================================================
//
//  Gaplus explosion analog stage (62XX O port -> speaker node), from the Midway Gaplus logic P.C. schematic
//  (sheet 3 of 3): O7-O4 and O3-O0 drive two binary resistor DACs (4.7K / 10K / 22K / 47K, Thevenin 2.6K), each
//  into a TL082 multiple-feedback band-pass (150K in, 0.01 uF + 0.01 uF, 470K feedback): f0 59.4 Hz, Q 0.877, peak
//  gain 1.54. The two outputs are summed through R17 / R18 10K and R5 10K onto the 99XX (SDATA) node.
//  Each band-pass runs as a Chamberlin state-variable filter at the 15XX sample rate (24 kHz), one multiplier
//  time-shared over six steps.
//  Copyright (C) 2026 Rodimus
//
//============================================================================

module gaplus_boom
(
    input  logic               clk,
    input  logic               reset,
    input  logic               smp,            // 24 kHz sample strobe
    input  logic         [7:0] o,              // 62XX O port {O7..O4, O3..O0}
    output logic signed [15:0] sound
);

// DAC: node voltage x 4095 / 5 V for each nibble (resistor conductances, MSB = 4.7K)
function automatic [11:0] dac(input [3:0] n);
    dac = (n[3] ? 12'd2296 : 12'd0) + (n[2] ? 12'd1079 : 12'd0) + (n[1] ? 12'd490 : 12'd0) + (n[0] ? 12'd230 : 12'd0);
endfunction

localparam signed [17:0] F_Q16 = 18'sd1020;       // 2 sin(pi f0 / fs)
localparam signed [17:0] Q_Q16 = 18'sd74694;      // 1 / Q
localparam signed [17:0] GAIN  = 18'sd5391;       // K / Q x mix level: x3 of 1797 (HW "a bit quiet"); boot boom peak ~32300, ~8400 RMS vs MAME's bang 9500 (sim 2026-10-25)

logic signed [27:0] low[2], band[2], high[2];
logic        [2:0]  step = 3'd7;
logic signed [27:0] ma;
logic signed [17:0] mb;
wire  signed [45:0] mp = ma * mb;
wire  signed [27:0] mq = 28'(mp >>> 16);
logic signed [28:0] acc;

wire  signed [46:0] s_out = (acc * GAIN) >>> 18;
wire        ch = step[0];                          // steps 0/2/4 channel 0, 1/3/5 channel 1
wire [11:0] xin = dac(ch ? o[3:0] : o[7:4]);
wire signed [27:0] x = $signed({6'd0, xin, 10'd0});

always_comb begin
    case (step)
        3'd0, 3'd1: begin ma = band[ch]; mb = F_Q16; end   // low += f * band
        3'd2, 3'd3: begin ma = band[ch]; mb = Q_Q16; end   // high = x - low - q * band
        default:    begin ma = high[ch]; mb = F_Q16; end   // band += f * high
    endcase
end

always_ff @(posedge clk) begin
    if (reset) begin
        for (int c = 0; c < 2; c++) begin low[c] <= 28'sd0; band[c] <= 28'sd0; high[c] <= 28'sd0; end
        acc   <= 29'sd0;
        step  <= 3'd7;
        sound <= 16'sd0;
    end
    else begin
        if (smp) step <= 3'd0;
        else if (step != 3'd7) step <= step + 3'd1;
        case (step)
            3'd0, 3'd1: low[ch]  <= low[ch] + mq;
            3'd2, 3'd3: high[ch] <= x - low[ch] - mq;
            3'd4, 3'd5: band[ch] <= band[ch] + mq;
            3'd6:       acc      <= 29'(band[0]) + 29'(band[1]);
            default: ;
        endcase
        if (smp) sound <= (s_out > 47'sd32767) ? 16'sh7FFF : (s_out < -47'sd32768) ? -16'sh8000 : 16'(s_out);
    end
end

endmodule
