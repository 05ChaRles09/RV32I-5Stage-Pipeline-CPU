// control_unit.v upgraded for 5-stage pipeline.
// Adds: uses_rs1, uses_rs2, wb_sel, alu_a_sel
//   wb_sel: 00=ALU result, 01=MEM rdata, 10=PC+4
//   alu_a_sel: 00=rs1(fwd), 01=pc, 10=zero (used for LUI, routes imm through ALU)
`timescale 1ns / 1ps

module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        branch,
    output reg        jump,
    output reg        jalr,
    output reg        alu_src,
    output reg        mem_to_reg,
    output reg  [3:0] alu_control,
    output reg        uses_rs1,
    output reg        uses_rs2,
    output reg  [1:0] wb_sel,        // 00=ALU, 01=MEM, 10=PC+4
    output reg  [1:0] alu_a_sel      // 00=rs1(fwd), 01=pc, 10=zero
);
    localparam ALU_AND  = 4'b0000;
    localparam ALU_OR   = 4'b0001;
    localparam ALU_ADD  = 4'b0010;
    localparam ALU_XOR  = 4'b0011;
    localparam ALU_SUB  = 4'b0110;
    localparam ALU_SLT  = 4'b0111;
    localparam ALU_SLL  = 4'b1000;
    localparam ALU_SRL  = 4'b1001;
    localparam ALU_SRA  = 4'b1010;
    localparam ALU_SLTU = 4'b1011;

    localparam OPCODE_OP     = 7'b0110011;
    localparam OPCODE_OPIMM  = 7'b0010011;
    localparam OPCODE_LOAD   = 7'b0000011;
    localparam OPCODE_STORE  = 7'b0100011;
    localparam OPCODE_BRANCH = 7'b1100011;
    localparam OPCODE_JAL    = 7'b1101111;
    localparam OPCODE_JALR   = 7'b1100111;
    localparam OPCODE_LUI    = 7'b0110111;
    localparam OPCODE_AUIPC  = 7'b0010111;

    always @(*) begin
        reg_write   = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        branch      = 1'b0;
        jump        = 1'b0;
        jalr        = 1'b0;
        alu_src     = 1'b0;
        mem_to_reg  = 1'b0;
        alu_control = ALU_ADD;
        uses_rs1    = 1'b0;
        uses_rs2    = 1'b0;
        wb_sel      = 2'b00; // ALU
        alu_a_sel   = 2'b00; // rs1(fwd)

        case (opcode)
            OPCODE_OP: begin
                reg_write = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                case ({funct7, funct3})
                    {7'b0000000, 3'b000}: alu_control = ALU_ADD;
                    {7'b0100000, 3'b000}: alu_control = ALU_SUB;
                    {7'b0000000, 3'b111}: alu_control = ALU_AND;
                    {7'b0000000, 3'b110}: alu_control = ALU_OR;
                    {7'b0000000, 3'b100}: alu_control = ALU_XOR;
                    {7'b0000000, 3'b001}: alu_control = ALU_SLL;
                    {7'b0000000, 3'b101}: alu_control = ALU_SRL;
                    {7'b0100000, 3'b101}: alu_control = ALU_SRA;
                    {7'b0000000, 3'b010}: alu_control = ALU_SLT;
                    {7'b0000000, 3'b011}: alu_control = ALU_SLTU;
                    default: alu_control = ALU_ADD;
                endcase
            end

            OPCODE_OPIMM: begin
                reg_write = 1'b1;
                alu_src  = 1'b1;
                uses_rs1 = 1'b1;
                case (funct3)
                    3'b000: alu_control = ALU_ADD;
                    3'b111: alu_control = ALU_AND;
                    3'b110: alu_control = ALU_OR;
                    3'b100: alu_control = ALU_XOR;
                    3'b001: alu_control = ALU_SLL;
                    3'b101: alu_control = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b010: alu_control = ALU_SLT;
                    3'b011: alu_control = ALU_SLTU;
                    default: alu_control = ALU_ADD;
                endcase
            end

            OPCODE_LOAD: begin
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                alu_src    = 1'b1;
                mem_to_reg = 1'b1;
                uses_rs1   = 1'b1;
                alu_control= ALU_ADD;
                wb_sel     = 2'b01; // MEM
            end

            OPCODE_STORE: begin
                mem_write  = 1'b1;
                alu_src    = 1'b1;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
                alu_control= ALU_ADD;
            end

            OPCODE_BRANCH: begin
                branch     = 1'b1;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
                alu_control= ALU_SUB;
            end

            OPCODE_JAL: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                wb_sel     = 2'b10; // PC+4
            end

            OPCODE_JALR: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                jalr       = 1'b1;
                uses_rs1   = 1'b1;
                wb_sel     = 2'b10;      // link = PC+4
            end

            OPCODE_LUI: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;      // B = imm
                alu_a_sel  = 2'b10;      // A = 0 -> ALU result = imm (already <<12)
                wb_sel     = 2'b00;      // ALU result
            end

            OPCODE_AUIPC: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_a_sel  = 2'b01; // pc
                alu_control= ALU_ADD;
            end
        endcase
    end
endmodule
