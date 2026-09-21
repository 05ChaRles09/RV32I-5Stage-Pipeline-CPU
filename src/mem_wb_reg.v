// mem_wb_reg.v carries MEM results to WB stage
`timescale 1ns / 1ps

module mem_wb_reg (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] alu_result_in,
    input  wire [31:0] mem_rdata_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] imm_in,
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,
    input  wire        jump_in,
    input  wire        valid_in,
    input  wire [1:0]  wb_sel_in,
    input  wire [4:0]  rd_in,
    input  wire [2:0]  funct3_in,

    output reg [31:0] alu_result_out,
    output reg [31:0] mem_rdata_out,
    output reg [31:0] pc_plus4_out,
    output reg [31:0] imm_out,
    output reg        reg_write_out,
    output reg        mem_to_reg_out,
    output reg        jump_out,
    output reg        valid_out,
    output reg [1:0]  wb_sel_out,
    output reg [4:0]  rd_out,
    output reg [2:0]  funct3_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_out   <= 32'b0;
            mem_rdata_out    <= 32'b0;
            pc_plus4_out     <= 32'b0;
            imm_out          <= 32'b0;
            reg_write_out    <= 1'b0;
            mem_to_reg_out   <= 1'b0;
            jump_out         <= 1'b0;
            valid_out        <= 1'b0;
            wb_sel_out       <= 2'b00;
            rd_out           <= 5'b0;
            funct3_out       <= 3'b0;
        end else begin
            alu_result_out   <= alu_result_in;
            mem_rdata_out    <= mem_rdata_in;
            pc_plus4_out     <= pc_plus4_in;
            imm_out          <= imm_in;
            reg_write_out    <= reg_write_in;
            mem_to_reg_out   <= mem_to_reg_in;
            jump_out         <= jump_in;
            valid_out        <= valid_in;
            wb_sel_out       <= wb_sel_in;
            rd_out           <= rd_in;
            funct3_out       <= funct3_in;
        end
    end
endmodule
