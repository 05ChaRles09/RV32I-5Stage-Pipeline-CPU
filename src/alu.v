// alu.v  RV32I ALU + Zbb (via zbb_unit) + RV32M MUL + custom XDOTP16.
// ALU_Control[5] == 0 : base RV32I operation (ALU_* codes)
// ALU_Control[5] == 1 : Zbb operation, code = ALU_Control[4:0]
`timescale 1ns / 1ps

module alu (
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [5:0]  ALU_Control,
    output reg  [31:0] Result,
    output wire         Zero
);
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
    localparam ALU_MUL  = 6'b001100;   // RV32M MUL: low 32 bits of A*B (same for signed/unsigned)

    localparam ALU_XDOT = 6'b001101;   // custom XDOTP16: signed int16 2-element dot product

    wire [31:0] zbb_result;

    // XDOTP16: rd = A[15:0]*B[15:0] + A[31:16]*B[31:16]  (signed 16x16 products, 32-bit wrap-around sum)
    wire signed [15:0] xa0 = A[15:0];
    wire signed [15:0] xa1 = A[31:16];
    wire signed [15:0] xb0 = B[15:0];
    wire signed [15:0] xb1 = B[31:16];
    wire signed [31:0] xp0 = xa0 * xb0;
    wire signed [31:0] xp1 = xa1 * xb1;
    wire        [31:0] xdot_result = xp0 + xp1;

    zbb_unit zbb_inst (
        .A      (A),
        .B      (B),
        .op     (ALU_Control[4:0]),
        .Result (zbb_result)
    );

    always @(*) begin
        if (ALU_Control[5]) begin
            Result = zbb_result;
        end else begin
            case (ALU_Control)
                ALU_AND:  Result = A & B;
                ALU_OR:   Result = A | B;
                ALU_ADD:  Result = A + B;
                ALU_XOR:  Result = A ^ B;
                ALU_SUB:  Result = A - B;
                ALU_SLT:  Result = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0;
                ALU_SLL:  Result = A << B[4:0];
                ALU_SRL:  Result = A >> B[4:0];
                ALU_SRA:  Result = $signed(A) >>> B[4:0];
                ALU_SLTU: Result = (A < B) ? 32'd1 : 32'd0;
                ALU_MUL:  Result = A * B;      // 32x32 -> low 32 bits; inferred as DSP48E2
                ALU_XDOT: Result = xdot_result; // 2 x DSP48E2 (16x16) + adder
                default:  Result = 32'b0;
            endcase
        end
    end

    assign Zero = (Result == 32'b0);
endmodule
