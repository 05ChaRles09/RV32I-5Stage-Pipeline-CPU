`timescale 1ns / 1ps
//
// rv32i_dut_extra.v thin wrapper instantiating rv32i_pipeline with
// extra.hex as the instruction memory file. Used by tb_extra_branches.v.
//
module rv32i_dut_extra (
    input  wire clk,
    input  wire rst_n
);
    rv32i_pipeline #(
        .IMEM_FILE("extra.hex")
    ) dut (
        .clk   (clk),
        .rst_n (rst_n)
    );
endmodule
