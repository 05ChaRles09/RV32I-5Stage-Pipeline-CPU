// imem.v instruction memory, parameterized, flat address range
`timescale 1ns / 1ps

module imem #(
    parameter ADDR_WIDTH = 12,
    parameter MEM_FILE    = "program.hex"
)(
    input  wire [31:0] addr,
    output wire [31:0] instr
);
    localparam DEPTH = (1 << ADDR_WIDTH);
    reg [31:0] mem [0:DEPTH-1];
    integer i;

    initial begin
        // Hardcoded default program (40 distinct instructions).
        // This guarantees imem output is NON-CONSTANT even when the hex
        // file is absent (e.g. standalone Vivado synthesis where the run
        // directory has no program.hex) otherwise Vivado constant-folds
        // the whole ROM away and prunes the entire pipeline.
        // If $readmemh finds MEM_FILE, it overrides these values.
        mem[0]  = 32'h00500093; // addi x1, x0, 5
        mem[1]  = 32'h00a00113; // addi x2, x0, 10
        mem[2]  = 32'h002081b3; // add  x3, x1, x2
        mem[3]  = 32'h00500213; // addi x4, x0, 5
        mem[4]  = 32'h00320293; // addi x5, x4, 3
        mem[5]  = 32'h00528b93; // addi x23, x5, 5
        mem[6]  = 32'h00100313; // addi x6, x0, 1
        mem[7]  = 32'h00130393; // addi x7, x6, 1
        mem[8]  = 32'h00138413; // addi x8, x7, 1
        mem[9]  = 32'h00000593; // addi x11, x0, 0
        mem[10] = 32'h02a00493; // addi x9, x0, 42
        mem[11] = 32'h0095a023; // sw   x9, 0(x11)
        mem[12] = 32'h0005a503; // lw   x10, 0(x11)
        mem[13] = 32'h00950633; // add  x12, x10, x9
        mem[14] = 32'h00000493; // addi x9, x0, 0
        mem[15] = 32'h00050493; // addi x9, x10, 0
        mem[16] = 32'h00000693; // addi x13, x0, 0
        mem[17] = 32'h00100793; // addi x15, x0, 1
        mem[18] = 32'h00100813; // addi x16, x0, 1
        mem[19] = 32'h01078463; // beq  x15, x16, skip1
        mem[20] = 32'h06300693; // addi x13, x0, 99
        mem[21] = 32'h00700713; // addi x14, x0, 7
        mem[22] = 32'h00100913; // addi x18, x0, 1
        mem[23] = 32'h00200993; // addi x19, x0, 2
        mem[24] = 32'h01391663; // bne  x18, x19, skip2
        mem[25] = 32'h00500893; // addi x17, x0, 5
        mem[26] = 32'h00900893; // addi x17, x0, 9
        mem[27] = 32'h00900893; // addi x17, x0, 9
        mem[28] = 32'h00000013; // nop
        mem[29] = 32'h00000013; // nop
        mem[30] = 32'h00000a93; // addi x21, x0, 0
        mem[31] = 32'h00c000ef; // jal  x1, target1
        mem[32] = 32'h00500a93; // addi x21, x0, 5
        mem[33] = 32'h00700a93; // addi x21, x0, 7
        mem[34] = 32'h06300a13; // addi x20, x0, 99
        mem[35] = 32'h0080006f; // jal  x0, aftjalr
        mem[36] = 32'h00500a93; // addi x21, x0, 5
        mem[37] = 32'h12345b37; // lui  x22, 0x12345
        mem[38] = 32'h0040006f; // jal  x0, spin
        mem[39] = 32'h0000006f; // jal  x0, spin
        for (i = 40; i < DEPTH; i = i + 1)
            mem[i] = 32'h00000013; // NOP fill

        $readmemh(MEM_FILE, mem);
        $display("IMEM: successfully loaded file '%0s'", MEM_FILE);
        $display("IMEM: mem[0] = %08h", mem[0]);
    end

    // word-addressed, only low (ADDR_WIDTH-2) bits matter
    assign instr = mem[addr[ADDR_WIDTH-1:2]];
endmodule
