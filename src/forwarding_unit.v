// forwarding_unit.v EX/MEM and MEM/WB forwarding, skips in-flight loads
`timescale 1ns / 1ps

module forwarding_unit (
    input  wire [4:0] id_ex_rs1,
    input  wire [4:0] id_ex_rs2,
    input  wire        id_ex_uses_rs1,
    input  wire        id_ex_uses_rs2,

    input  wire [4:0] ex_mem_rd,
    input  wire        ex_mem_reg_write,
    input  wire        ex_mem_mem_read,  // skip in-flight load (result not ready)
    input  wire        ex_mem_valid,

    input  wire [4:0] mem_wb_rd,
    input  wire        mem_wb_reg_write,
    input  wire        mem_wb_valid,

    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b
);
    // 2'b00 = use id_ex value, 2'b10 = from EX/MEM, 2'b01 = from MEM/WB
    always @(*) begin
        forward_a = 2'b00;
        forward_b = 2'b00;

        // EX/MEM -> EX  (but NOT an in-flight load; its data isn't ready)
        if (ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read &&
            (ex_mem_rd != 5'd0) && id_ex_uses_rs1 &&
            (ex_mem_rd == id_ex_rs1)) begin
            forward_a = 2'b10;
        end
        else if (mem_wb_valid && mem_wb_reg_write &&
                 (mem_wb_rd != 5'd0) && id_ex_uses_rs1 &&
                 (mem_wb_rd == id_ex_rs1)) begin
            forward_a = 2'b01;
        end

        if (ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read &&
            (ex_mem_rd != 5'd0) && id_ex_uses_rs2 &&
            (ex_mem_rd == id_ex_rs2)) begin
            forward_b = 2'b10;
        end
        else if (mem_wb_valid && mem_wb_reg_write &&
                 (mem_wb_rd != 5'd0) && id_ex_uses_rs2 &&
                 (mem_wb_rd == id_ex_rs2)) begin
            forward_b = 2'b01;
        end
    end
endmodule
