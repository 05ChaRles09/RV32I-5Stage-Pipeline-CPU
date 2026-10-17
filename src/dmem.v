// dmem.v data memory (BRAM-style): synchronous write and SYNCHRONOUS read (latency 1, read-first).
// Driven from the EX stage: addr/wdata/mem_write are the EX-stage values, rdata is valid in the MEM stage.
`timescale 1ns / 1ps

module dmem #(
    parameter ADDR_WIDTH = 12,
    parameter EXTERNAL   = 0     // 1: data memory lives OUTSIDE (Block Memory Generator); ext_rdata is used
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata,
    input  wire [31:0] ext_rdata
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    reg [31:0] mem [0:DEPTH-1];
    reg [31:0] rdata_q;
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h00000000;
    end

    // Synchronous write + synchronous read (read-first). No reset on the array (keeps BRAM inference).
    // mem_read is unused: the read port is always enabled, rdata is only consumed by loads.
    always @(posedge clk) begin
        if (mem_write)
            mem[addr[ADDR_WIDTH-1:2]] <= wdata;
        rdata_q <= mem[addr[ADDR_WIDTH-1:2]];
    end
    assign rdata = EXTERNAL ? ext_rdata : rdata_q;
endmodule
