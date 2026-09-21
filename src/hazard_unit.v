// hazard_unit.v load-use hazard detection (stall one cycle)
`timescale 1ns / 1ps

module hazard_unit (
    input  wire        id_ex_mem_read,
    input  wire [4:0]  id_ex_rd,
    input  wire        id_ex_valid,

    input  wire [4:0]  if_id_rs1,
    input  wire [4:0]  if_id_rs2,
    input  wire        if_id_uses_rs1,
    input  wire        if_id_uses_rs2,
    input  wire        if_id_valid,

    output reg         stall
);
    always @(*) begin
        stall = 1'b0;

        if (id_ex_valid && id_ex_mem_read && (id_ex_rd != 5'd0) && if_id_valid) begin
            if ((if_id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
                (if_id_uses_rs2 && (id_ex_rd == if_id_rs2))) begin
                stall = 1'b1;
            end
        end
    end
endmodule
