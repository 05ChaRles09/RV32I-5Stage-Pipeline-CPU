// branch_unit.v resolves BEQ/BNE/BLT/BGE/BLTU/BGEU/JAL/JALR
// Uses already-forwarded rs1/rs2 values so dependencies are correct.
`timescale 1ns / 1ps

module branch_unit (
    input  wire [31:0] pc,
    input  wire [31:0] rs1_value,   // forwarded rs1
    input  wire [31:0] rs2_value,   // forwarded rs2
    input  wire [31:0] imm,
    input  wire [2:0]  funct3,
    input  wire        branch,
    input  wire        jump,
    input  wire        jalr,
    input  wire        valid,

    output reg         taken,
    output reg  [31:0] target
);
    localparam F3_BEQ  = 3'b000;
    localparam F3_BNE  = 3'b001;
    localparam F3_BLT  = 3'b100;
    localparam F3_BGE  = 3'b101;
    localparam F3_BLTU = 3'b110;
    localparam F3_BGEU = 3'b111;

    always @(*) begin
        taken  = 1'b0;
        target = pc + 32'd4;

        if (valid) begin
            if (jalr) begin
                taken  = 1'b1;
                target = (rs1_value + imm) & 32'hFFFFFFFE;
            end
            else if (jump) begin
                taken  = 1'b1;
                target = pc + imm;
            end
            else if (branch) begin
                target = pc + imm;
                case (funct3)
                    F3_BEQ:  taken = (rs1_value == rs2_value);
                    F3_BNE:  taken = (rs1_value != rs2_value);
                    F3_BLT:  taken = ($signed(rs1_value) <  $signed(rs2_value));
                    F3_BGE:  taken = ($signed(rs1_value) >= $signed(rs2_value));
                    F3_BLTU: taken = (rs1_value <  rs2_value);
                    F3_BGEU: taken = (rs1_value >= rs2_value);
                    default: taken = 1'b0;
                endcase
            end
        end
    end
endmodule
