`timescale 1ns / 1ps
//
// rv32i_dut_jalr.v thin wrapper instantiating rv32i_pipeline with
// jalr.hex as the instruction memory file. Used by tb_jalr.v.
//
module rv32i_dut_jalr (
    input  wire clk,
    input  wire rst_n
);
    rv32i_pipeline #(
        .IMEM_FILE("jalr.hex")
    ) dut (
        .clk   (clk),
        .rst_n (rst_n)
    );
endmodule
