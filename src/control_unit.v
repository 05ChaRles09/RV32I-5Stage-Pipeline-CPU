// control_unit.v upgraded for 5-stage pipeline.
// Adds: uses_rs1, uses_rs2, wb_sel, alu_a_sel
//   wb_sel: 00=ALU result, 01=MEM rdata, 10=PC+4
//   alu_a_sel: 00=rs1(fwd), 01=pc, 10=zero (used for LUI, routes imm through ALU)
//
// alu_control is 6 bits:
//   [5]   = 0 : base RV32I ALU operation  (codes ALU_* below, upper bits 0)
//   [5]   = 1 : Zbb operation, [4:0] = ZB_* code (see zbb_unit.v)
//
// RV32M: only MUL (funct7=0000001, funct3=000) is implemented, as a single-cycle
//   32x32->low32 multiply in the EX stage. MULH*/DIV*/REM* are still illegal.
//
// illegal: asserted when the instruction is not supported by this core
//   (unknown opcode, unsupported funct3/funct7 combination, sub-word
//   load/store, SYSTEM/FENCE, all-zero word ...). When illegal is asserted
//   every other control output is forced to its "do nothing" value, so an
//   unsupported instruction behaves as a NOP instead of being silently
//   executed as something else (previously unknown R/I-type fell through
//   to ADD).
`timescale 1ns / 1ps

module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    input  wire [4:0] rs2_field,     // instr[24:20]; selects Zbb unary ops (clz/ctz/cpop/sext/rev8/orc.b/zext.h)
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        branch,
    output reg        jump,
    output reg        jalr,
    output reg        alu_src,
    output reg        mem_to_reg,
    output reg  [5:0] alu_control,
    output reg        uses_rs1,
    output reg        uses_rs2,
    output reg  [1:0] wb_sel,        // 00=ALU, 01=MEM, 10=PC+4
    output reg  [1:0] alu_a_sel,     // 00=rs1(fwd), 01=pc, 10=zero
    output reg        illegal
);
    // ---- base ALU operations -------------------------------------
    localparam ALU_AND  = 6'b000000;
    localparam ALU_OR   = 6'b000001;
    localparam ALU_ADD  = 6'b000010;
    localparam ALU_XOR  = 6'b000011;
    localparam ALU_SUB  = 6'b000110;
    localparam ALU_SLT  = 6'b000111;
    localparam ALU_SLL  = 6'b001000;
    localparam ALU_SRL  = 6'b001001;
    localparam ALU_SRA  = 6'b001010;
    localparam ALU_SLTU = 6'b001011;
    localparam ALU_MUL  = 6'b001100;

    // ---- Zbb operations ({1'b1, code}) ---------------------------
    localparam ZB_ANDN   = 6'b100000;
    localparam ZB_ORN    = 6'b100001;
    localparam ZB_XNOR   = 6'b100010;
    localparam ZB_MIN    = 6'b100011;
    localparam ZB_MINU   = 6'b100100;
    localparam ZB_MAX    = 6'b100101;
    localparam ZB_MAXU   = 6'b100110;
    localparam ZB_ROL    = 6'b100111;
    localparam ZB_ROR    = 6'b101000;
    localparam ZB_CLZ    = 6'b101001;
    localparam ZB_CTZ    = 6'b101010;
    localparam ZB_CPOP   = 6'b101011;
    localparam ZB_SEXT_B = 6'b101100;
    localparam ZB_SEXT_H = 6'b101101;
    localparam ZB_ZEXT_H = 6'b101110;
    localparam ZB_REV8   = 6'b101111;
    localparam ZB_ORC_B  = 6'b110000;

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
        illegal     = 1'b0;

        case (opcode)
            OPCODE_OP: begin
                reg_write = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                case ({funct7, funct3})
                    // RV32I
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
                    // RV32M (only MUL; MULH/MULHSU/MULHU/DIV/REM stay illegal)
                    {7'b0000001, 3'b000}: alu_control = ALU_MUL;
                    // Zbb
                    {7'b0100000, 3'b111}: alu_control = ZB_ANDN;
                    {7'b0100000, 3'b110}: alu_control = ZB_ORN;
                    {7'b0100000, 3'b100}: alu_control = ZB_XNOR;
                    {7'b0000101, 3'b100}: alu_control = ZB_MIN;
                    {7'b0000101, 3'b101}: alu_control = ZB_MINU;
                    {7'b0000101, 3'b110}: alu_control = ZB_MAX;
                    {7'b0000101, 3'b111}: alu_control = ZB_MAXU;
                    {7'b0110000, 3'b001}: alu_control = ZB_ROL;
                    {7'b0110000, 3'b101}: alu_control = ZB_ROR;
                    {7'b0000100, 3'b100}: begin           // zext.h (rv32): rs2 field must be 0
                        alu_control = ZB_ZEXT_H;
                        uses_rs2    = 1'b0;
                        if (rs2_field != 5'b00000) illegal = 1'b1;
                    end
                    default: illegal = 1'b1;
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
                    3'b010: alu_control = ALU_SLT;
                    3'b011: alu_control = ALU_SLTU;
                    3'b001: begin
                        case (funct7)
                            7'b0000000: alu_control = ALU_SLL;           // slli
                            7'b0110000: begin                            // Zbb unary ops
                                case (rs2_field)
                                    5'b00000: alu_control = ZB_CLZ;
                                    5'b00001: alu_control = ZB_CTZ;
                                    5'b00010: alu_control = ZB_CPOP;
                                    5'b00100: alu_control = ZB_SEXT_B;
                                    5'b00101: alu_control = ZB_SEXT_H;
                                    default:  illegal = 1'b1;
                                endcase
                            end
                            default: illegal = 1'b1;
                        endcase
                    end
                    3'b101: begin
                        case (funct7)
                            7'b0000000: alu_control = ALU_SRL;           // srli
                            7'b0100000: alu_control = ALU_SRA;           // srai
                            7'b0110000: alu_control = ZB_ROR;            // rori
                            7'b0110100: begin                            // rev8 (rv32)
                                alu_control = ZB_REV8;
                                if (rs2_field != 5'b11000) illegal = 1'b1;
                            end
                            7'b0010100: begin                            // orc.b
                                alu_control = ZB_ORC_B;
                                if (rs2_field != 5'b00111) illegal = 1'b1;
                            end
                            default: illegal = 1'b1;
                        endcase
                    end
                    default: illegal = 1'b1;
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
                // only LW is implemented (data memory is word-wide)
                if (funct3 != 3'b010) illegal = 1'b1;
            end

            OPCODE_STORE: begin
                mem_write  = 1'b1;
                alu_src    = 1'b1;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
                alu_control= ALU_ADD;
                // only SW is implemented
                if (funct3 != 3'b010) illegal = 1'b1;
            end

            OPCODE_BRANCH: begin
                branch     = 1'b1;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b1;
                alu_control= ALU_SUB;
                if (funct3 == 3'b010 || funct3 == 3'b011) illegal = 1'b1;
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
                if (funct3 != 3'b000) illegal = 1'b1;
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

            default: illegal = 1'b1;     // unknown opcode, SYSTEM, FENCE, 0x00000000 ...
        endcase

        // An illegal instruction must have no architectural effect (acts as NOP).
        if (illegal) begin
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
            wb_sel      = 2'b00;
            alu_a_sel   = 2'b00;
        end
    end
endmodule
