`timescale 1ns / 1ps
//
// rv32i_dut_lub.v thin wrapper instantiating rv32i_pipeline with
// load_use_branch.hex as the instruction memory file. Used by tb_load_use_branch.v.
//
module rv32i_dut_lub (
    input  wire clk,
    input  wire rst_n
);
    rv32i_pipeline #(
        .IMEM_FILE("load_use_branch.hex")
    ) dut (
        .clk   (clk),
        .rst_n (rst_n)
    );
endmodule
