// id_ex_reg.v also carries uses_rs1/uses_rs2, wb_sel, alu_a_sel
`timescale 1ns / 1ps

module id_ex_reg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] imm_in,

    input  wire [4:0]  rs1_in,
    input  wire [4:0]  rs2_in,
    input  wire [4:0]  rd_in,
    input  wire [2:0]  funct3_in,
    input  wire [3:0]  alu_control_in,

    input  wire        reg_write_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        mem_to_reg_in,
    input  wire        alu_src_in,
    input  wire        branch_in,
    input  wire        jump_in,
    input  wire        jalr_in,
    input  wire        valid_in,
    input  wire        uses_rs1_in,
    input  wire        uses_rs2_in,
    input  wire [1:0]  wb_sel_in,
    input  wire [1:0]  alu_a_sel_in,

    output reg [31:0] pc_out,
    output reg [31:0] pc_plus4_out,
    output reg [31:0] rs1_data_out,
    output reg [31:0] rs2_data_out,
    output reg [31:0] imm_out,

    output reg [4:0]  rs1_out,
    output reg [4:0]  rs2_out,
    output reg [4:0]  rd_out,
    output reg [2:0]  funct3_out,
    output reg [3:0]  alu_control_out,

    output reg        reg_write_out,
    output reg        mem_read_out,
    output reg        mem_write_out,
    output reg        mem_to_reg_out,
    output reg        alu_src_out,
    output reg        branch_out,
    output reg        jump_out,
    output reg        jalr_out,
    output reg        valid_out,
    output reg        uses_rs1_out,
    output reg        uses_rs2_out,
    output reg [1:0]  wb_sel_out,
    output reg [1:0]  alu_a_sel_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n | flush) begin
            pc_out          <= 32'b0;
            pc_plus4_out    <= 32'b0;
            rs1_data_out    <= 32'b0;
            rs2_data_out    <= 32'b0;
            imm_out         <= 32'b0;
            rs1_out         <= 5'b0;
            rs2_out         <= 5'b0;
            rd_out          <= 5'b0;
            funct3_out      <= 3'b0;
            alu_control_out <= 4'b0;
            reg_write_out   <= 1'b0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            mem_to_reg_out  <= 1'b0;
            alu_src_out     <= 1'b0;
            branch_out      <= 1'b0;
            jump_out        <= 1'b0;
            jalr_out        <= 1'b0;
            valid_out       <= 1'b0;
            uses_rs1_out    <= 1'b0;
            uses_rs2_out    <= 1'b0;
            wb_sel_out      <= 2'b00;
            alu_a_sel_out   <= 2'b00;
        end else begin
            pc_out          <= pc_in;
            pc_plus4_out    <= pc_plus4_in;
            rs1_data_out    <= rs1_data_in;
            rs2_data_out    <= rs2_data_in;
            imm_out         <= imm_in;
            rs1_out         <= rs1_in;
            rs2_out         <= rs2_in;
            rd_out          <= rd_in;
            funct3_out      <= funct3_in;
            alu_control_out <= alu_control_in;
            reg_write_out   <= reg_write_in;
            mem_read_out    <= mem_read_in;
            mem_write_out   <= mem_write_in;
            mem_to_reg_out  <= mem_to_reg_in;
            alu_src_out     <= alu_src_in;
            branch_out      <= branch_in;
            jump_out        <= jump_in;
            jalr_out        <= jalr_in;
            valid_out       <= valid_in;
            uses_rs1_out    <= uses_rs1_in;
            uses_rs2_out    <= uses_rs2_in;
            wb_sel_out      <= wb_sel_in;
            alu_a_sel_out   <= alu_a_sel_in;
        end
    end
endmodule
