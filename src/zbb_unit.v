// zbb_unit.v  RISC-V "Zbb" (basic bit-manipulation) functional unit, RV32.
// Purely combinational; instantiated inside alu.v and selected when
// ALU_Control[5] == 1.  op = ALU_Control[4:0].
//
//   op  mnemonic   operation
//   --  --------   ---------------------------------------------
//   00  andn       A & ~B
//   01  orn        A | ~B
//   02  xnor       ~(A ^ B)
//   03  min        signed   min(A,B)
//   04  minu       unsigned min(A,B)
//   05  max        signed   max(A,B)
//   06  maxu       unsigned max(A,B)
//   07  rol/       rotate left  by B[4:0]
//   08  ror/rori   rotate right by B[4:0]
//   09  clz        count leading zeros   (32 when A == 0)
//   10  ctz        count trailing zeros  (32 when A == 0)
//   11  cpop       population count
//   12  sext.b     sign-extend A[7:0]
//   13  sext.h     sign-extend A[15:0]
//   14  zext.h     zero-extend A[15:0]
//   15  rev8       byte-reverse A
//   16  orc.b      each byte = (byte != 0) ? 8'hFF : 8'h00
`timescale 1ns / 1ps

module zbb_unit (
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [4:0]  op,
    output reg  [31:0] Result
);
    localparam OP_ANDN   = 5'd0;
    localparam OP_ORN    = 5'd1;
    localparam OP_XNOR   = 5'd2;
    localparam OP_MIN    = 5'd3;
    localparam OP_MINU   = 5'd4;
    localparam OP_MAX    = 5'd5;
    localparam OP_MAXU   = 5'd6;
    localparam OP_ROL    = 5'd7;
    localparam OP_ROR    = 5'd8;
    localparam OP_CLZ    = 5'd9;
    localparam OP_CTZ    = 5'd10;
    localparam OP_CPOP   = 5'd11;
    localparam OP_SEXT_B = 5'd12;
    localparam OP_SEXT_H = 5'd13;
    localparam OP_ZEXT_H = 5'd14;
    localparam OP_REV8   = 5'd15;
    localparam OP_ORC_B  = 5'd16;

    // ---- helpers -------------------------------------------------
    // bit-reversed copy of A (so ctz(A) == clz(reverse(A)))
    reg [31:0] a_rev;
    integer k;
    always @(*) begin
        for (k = 0; k < 32; k = k + 1)
            a_rev[k] = A[31-k];
    end

    // count leading zeros of x (32 if x == 0)
    function [5:0] clz32;
        input [31:0] x;
        integer i;
        reg found;
        reg [5:0] cnt;
        begin
            cnt   = 6'd0;
            found = 1'b0;
            for (i = 31; i >= 0; i = i - 1) begin
                if (!found) begin
                    if (x[i]) found = 1'b1;
                    else      cnt   = cnt + 6'd1;
                end
            end
            clz32 = cnt;
        end
    endfunction

    // population count
    function [5:0] popcount32;
        input [31:0] x;
        integer i;
        begin
            popcount32 = 6'd0;
            for (i = 0; i < 32; i = i + 1)
                popcount32 = popcount32 + {5'b0, x[i]};
        end
    endfunction

    wire [4:0]  shamt = B[4:0];
    wire [63:0] dbl   = {A, A};
    wire [63:0] rol64 = dbl << shamt;     // rol = upper word of ({A,A} << shamt)
    wire [63:0] ror64 = dbl >> shamt;     // ror = lower word of ({A,A} >> shamt)

    wire a_lt_b_s = ($signed(A) < $signed(B));
    wire a_lt_b_u = (A < B);

    always @(*) begin
        case (op)
            OP_ANDN:   Result = A & ~B;
            OP_ORN:    Result = A | ~B;
            OP_XNOR:   Result = ~(A ^ B);
            OP_MIN:    Result = a_lt_b_s ? A : B;
            OP_MINU:   Result = a_lt_b_u ? A : B;
            OP_MAX:    Result = a_lt_b_s ? B : A;
            OP_MAXU:   Result = a_lt_b_u ? B : A;
            OP_ROL:    Result = rol64[63:32];
            OP_ROR:    Result = ror64[31:0];
            OP_CLZ:    Result = {26'b0, clz32(A)};
            OP_CTZ:    Result = {26'b0, clz32(a_rev)};
            OP_CPOP:   Result = {26'b0, popcount32(A)};
            OP_SEXT_B: Result = {{24{A[7]}},  A[7:0]};
            OP_SEXT_H: Result = {{16{A[15]}}, A[15:0]};
            OP_ZEXT_H: Result = {16'b0, A[15:0]};
            OP_REV8:   Result = {A[7:0], A[15:8], A[23:16], A[31:24]};
            OP_ORC_B:  Result = {{8{|A[31:24]}}, {8{|A[23:16]}}, {8{|A[15:8]}}, {8{|A[7:0]}}};
            default:   Result = 32'b0;
        endcase
    end
endmodule
