// regfile.v 32x32 register file, x0 hardwired to 0,
// with write-through bypass so a same-cycle WB write is visible
// to a same-cycle ID read (handles WB-to-ID same-cycle hazard).
`timescale 1ns / 1ps

module regfile (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
    reg [31:0] regs [1:31];
    integer i;

    initial begin
        for (i = 1; i <= 31; i = i + 1)
            regs[i] = 32'b0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i <= 31; i = i + 1)
                regs[i] <= 32'b0;
        end else if (we && rd_addr != 5'd0) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // read with write-through bypass (same-cycle WB visible to ID read)
    assign rs1_data = (rs1_addr == 5'd0) ? 32'b0 :
                       (we && (rd_addr == rs1_addr)) ? rd_data :
                       regs[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0) ? 32'b0 :
                       (we && (rd_addr == rs2_addr)) ? rd_data :
                       regs[rs2_addr];
endmodule
