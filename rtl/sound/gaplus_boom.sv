//  Copyright (C) 2026 Rodimus

module gaplus_boom
(
    input  logic               clk,
    input  logic               reset,
    input  logic               smp,
    input  logic         [7:0] o,
    output logic signed [15:0] sound
);

function automatic [11:0] dac(input [3:0] n);
    dac = (n[3] ? 12'd2296 : 12'd0) + (n[2] ? 12'd1079 : 12'd0) + (n[1] ? 12'd490 : 12'd0) + (n[0] ? 12'd230 : 12'd0);
endfunction

localparam signed [17:0] F_Q16 = 18'sd1020;
localparam signed [17:0] Q_Q16 = 18'sd74694;
localparam signed [17:0] GAIN  = 18'sd5391;

logic signed [27:0] low[2], band[2], high[2];
logic        [2:0]  step = 3'd7;
logic signed [27:0] ma;
logic signed [17:0] mb;
wire  signed [45:0] mp = ma * mb;
wire  signed [27:0] mq = 28'(mp >>> 16);
logic signed [28:0] acc;

wire  signed [46:0] s_out = (acc * GAIN) >>> 18;
wire        ch = step[0];
wire [11:0] xin = dac(ch ? o[3:0] : o[7:4]);
wire signed [27:0] x = $signed({6'd0, xin, 10'd0});

always_comb begin
    case (step)
        3'd0, 3'd1: begin ma = band[ch]; mb = F_Q16; end
        3'd2, 3'd3: begin ma = band[ch]; mb = Q_Q16; end
        default:    begin ma = high[ch]; mb = F_Q16; end
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
