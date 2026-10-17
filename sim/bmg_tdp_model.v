`timescale 1ns / 1ps
// bmg_tdp_model.v  SIMULATION ONLY (do not add to the IP): behavioural model of a Vivado Block Memory Generator
//   True Dual Port RAM, 32-bit data, byte write enables, 32-bit BYTE address interface, common clock,
//   read-first, read latency 1 (Primitives/Core output registers OFF), no reset.
//   Port A = PS side (AXI BRAM Controller), Port B = CPU.
module bmg_tdp_model #(
    parameter DEPTH_WORDS = 1024,
    parameter INIT_FILE   = ""
)(
    input  wire        clka, ena, input wire [3:0] wea, input wire [31:0] addra, input wire [31:0] dina, output reg [31:0] douta,
    input  wire        clkb, enb, input wire [3:0] web, input wire [31:0] addrb, input wire [31:0] dinb, output reg [31:0] doutb
);
    reg [31:0] mem [0:DEPTH_WORDS-1];
    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] = 32'h0;
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end
    wire [31:0] wa = addra >> 2, wb = addrb >> 2;
    always @(posedge clka) if (ena) begin
        douta <= mem[wa % DEPTH_WORDS];
        if (wea[0]) mem[wa % DEPTH_WORDS][7:0]   <= dina[7:0];
        if (wea[1]) mem[wa % DEPTH_WORDS][15:8]  <= dina[15:8];
        if (wea[2]) mem[wa % DEPTH_WORDS][23:16] <= dina[23:16];
        if (wea[3]) mem[wa % DEPTH_WORDS][31:24] <= dina[31:24];
    end
    always @(posedge clkb) if (enb) begin
        doutb <= mem[wb % DEPTH_WORDS];
        if (web[0]) mem[wb % DEPTH_WORDS][7:0]   <= dinb[7:0];
        if (web[1]) mem[wb % DEPTH_WORDS][15:8]  <= dinb[15:8];
        if (web[2]) mem[wb % DEPTH_WORDS][23:16] <= dinb[23:16];
        if (web[3]) mem[wb % DEPTH_WORDS][31:24] <= dinb[31:24];
    end
endmodule
