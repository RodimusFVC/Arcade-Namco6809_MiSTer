//============================================================================
//
//  Namco 15XX waveform sound generator (8 voices), written from MAME devices/sound/namco.cpp
//  (namco_15xx_device; Nicola Salmoria, Aaron Giles) and the Mappy / Super Pac-Man CPU board schematics.
//  Copyright (C) 2026 Rodimus
//
//  Registers = the first 64 bytes of the CPU-shared sound RAM, snooped on write (8 bytes per voice):
//    +2 counter MSBs (bits 4-0 = waveform step; Grobda's DAC trick), +3 volume (bits 3-0),
//    +4 / +5 frequency bits 7-0 / 15-8, +6 bits 3-0 frequency 19-16, bits 6-4 waveform
//  One sample per voice at 24 kHz (18.432 MHz / 768): a 20-bit phase accumulator per voice, waveform PROM
//  address {waveform, phase[19:15]}. The voices are summed (the boards' DAC is time-multiplexed per voice and
//  RC-filtered). SOUND ON clears the output latch; the generator itself keeps running.
//  DAC: linear signed (sample - 8) x volume for both boards (MAME's model). dac_mode is reserved for the
//  Super Pac-Man LS273 + 4066 resistor ladder (mode 0) - not modelled yet.
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

// sequencer: 4 clocks per voice (PROM address, wait, sample, accumulate)
logic  [4:0] seq = 5'd31;
wire   [2:0] v = seq[4:2];
logic signed [12:0] sum;
logic  [7:0] wave_a;
logic [15:0] sound;

wire signed [4:0] wsmp = $signed({1'b0, i.wave_d}) - 5'sd8;
wire signed [9:0] prod = wsmp * $signed({1'b0, vol[v]});

always_ff @(posedge clk) begin
    if (reset) begin
        for (int k = 0; k < 8; k++) begin
            vol[k] <= 4'd0;  freq[k] <= 20'd0;  wsel[k] <= 3'd0;  reg2[k] <= 8'd0;  acc[k] <= 20'd0;
        end
        seq <= 5'd31;
        sound <= 16'd0;
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

        if (smp) begin
            seq <= 5'd0;
            sum <= 13'sd0;
        end
        else if (seq != 5'd31) seq <= seq + 5'd1;

        if (seq[1:0] == 2'd0) wave_a <= {wsel[v], acc[v][19:15]};
        if (seq[1:0] == 2'd2) begin
            sum <= sum + 13'(prod);
            if (!(i.reg_wr && i.reg_addr[2:0] == 3'd2 && wch == v)) acc[v] <= acc[v] + freq[v];
        end
        if (seq == 5'd31) sound <= i.sound_en ? {sum[10:0], 5'd0} : 16'd0;    // idle: last voice summed
    end
end

assign o.wave_a = wave_a;
assign o.sound  = sound;

/* verilator lint_off UNUSED */
wire [1:0] unused_dac = i.dac_mode;
/* verilator lint_on UNUSED */

endmodule
