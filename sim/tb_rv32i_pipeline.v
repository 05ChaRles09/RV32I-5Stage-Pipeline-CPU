`timescale 1ns / 1ps
//
// tb_rv32i_pipeline.v self-checking main regression testbench
// Covers: add, addi, lui, sw, lw (load-use stall),
//         beq (taken flush), bne (not-taken), jal (link+target),
//         EX/MEM and MEM/WB forwarding chains.
// (jalr, blt/bge/bltu/bgeu, auipc, and load-use-into-branch have their
//  own dedicated testbenches: tb_jalr.v, tb_extra_branches.v, tb_load_use_branch.v)
//
// Build:
//   cd sim && ./run_all.sh
// or manually:
//   iverilog -g2012 -o rv32i_pipeline.vvp *.v tb_rv32i_pipeline.v (excluding other tb_*.v)
//   vvp rv32i_pipeline.vvp
//
module tb_rv32i_pipeline;
    reg clk;
    reg rst_n;

    rv32i_pipeline dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    always #5 clk = ~clk;

    integer errors = 0;

    task check;
        input [127:0] name;
        input [4:0]   idx;
        input [31:0]  exp;
        reg   [31:0]  got;
        begin
            got = dut.regfile_inst.regs[idx];
            if (got !== exp) begin
                $display("FAIL %-20s x%0d = %0d (0x%08h), expected %0d (0x%08h)",
                         name, idx, got, got, exp, exp);
                errors = errors + 1;
            end else begin
                $display("PASS %-20s x%0d = %0d", name, idx, got);
            end
        end
    endtask

    task check_mem;
        input [127:0] name;
        input [11:0]  addr;
        input [31:0]  exp;
        reg   [31:0]  got;
        begin
            got = dut.dmem_inst.mem[addr];
            if (got !== exp) begin
                $display("FAIL %-20s mem[0x%03h] = %0d (0x%08h), expected %0d (0x%08h)",
                         name, addr, got, got, exp, exp);
                errors = errors + 1;
            end else begin
                $display("PASS %-20s mem[0x%03h] = %0d", name, addr, got);
            end
        end
    endtask

    initial begin
        $dumpfile("rv32i_pipeline.vcd");
        $dumpvars(0, tb_rv32i_pipeline);

        clk = 0;
        rst_n = 0;
        #15 rst_n = 1;
        #1000;

        $display("---- register check ----");
        check("basic add",       3,  15);       // x3  = x1+x2 = 15
        check("EX/MEM fwd x4",   4,  5);        // x4 = 5 (base for fwd)
        check("EX/MEM fwd x5",   5,  8);        // x5 = x4+3 = 8 (fwd from EX/MEM)
        check("EX/MEM fwd x23", 23, 13);        // x23 = x5+5 = 13
        check("chain x6",        6,  1);
        check("chain x7",        7,  2);
        check("chain x8",        8,  3);
        check("lw result x10",  10, 42);        // lw mem[0]
        check("load-use add x12",12, 84);       // x12 = x10+x9 = 42+42
        check("lw->MEM/WB x9",   9, 42);        // x9 = x10 = 42
        check("branch flush x13",13, 0);        // taken -> 99 not executed
        check("branch target x14",14, 7);       // skipped false arm
        check("bne not-taken x17",17, 9);       // x17 = 9
        check("jal link x1",     1, 32'h00000080); // pc+4 of jal at 0x7c = 0x80
        check("jal target x20", 20, 99);        // jumped over false arm
        check("lui x22",        22, 32'h12345000);

        $display("---- memory check ----");
        check_mem("sw mem[0]", 0, 42);

        $display("========================================");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TOTAL FAILURES: %0d", errors);
        $display("========================================");
        $finish;
    end

    initial begin
        #100000;
        $display("ERROR: simulation timed out");
        $finish;
    end
endmodule
