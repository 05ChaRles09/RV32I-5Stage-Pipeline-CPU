// dmem.v data memory, combinational read, synchronous write
`timescale 1ns / 1ps

module dmem #(
    parameter ADDR_WIDTH = 12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    reg [31:0] mem [0:DEPTH-1];
    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'h00000000;
    end

    // synchronous write, combinational read (so load data is available
    // in the same MEM cycle and flows into MEM/WB).
    // NOTE: no reset on the memory array resets prevent BRAM/distributed
    // RAM inference. The array is initialized via the initial block above.
    always @(posedge clk) begin
        if (mem_write) begin
            mem[addr[ADDR_WIDTH-1:2]] <= wdata;
        end
    end

    assign rdata = mem[addr[ADDR_WIDTH-1:2]];
endmodule
