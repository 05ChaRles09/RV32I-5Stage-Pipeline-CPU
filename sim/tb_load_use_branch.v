`timescale 1ns / 1ps
//
// tb_load_use_branch.v tests a load-use hazard whose loaded value is
// consumed by a branch comparison on the very next instruction. This
// exercises hazard_unit stall + EX/MEM forwarding feeding branch_unit
// resolution simultaneously.
//
// Program (see gen_extra_programs.py / load_use_branch.hex):
//   addi x1, x0, 0
//   addi x2, x0, 5
//   sw   x2, 0(x1)
//   lw   x3, 0(x1)         ; load x3 = mem[0] = 5
//   beq  x3, x2, tgt       ; x3 (just loaded) == x2 (==5) -> taken
//   addi x4, x0, 99        ; flushed
// tgt:
//   addi x4, x0, 7
//   jal x0, spin
// spin: jal x0, spin
//
// Pass: x3 == 5 AND x4 == 7 (branch taken, fall-through flushed).
//
module tb_load_use_branch;
    reg clk;
    reg rst_n;

    rv32i_dut_lub wrapper (
        .clk   (clk),
        .rst_n (rst_n)
    );

    always #5 clk = ~clk;

    integer errors = 0;

    initial begin
        $dumpfile("lub.vcd");
        $dumpvars(0, tb_load_use_branch);

        clk = 0;
        rst_n = 0;
        #15 rst_n = 1;
        #350;

        if (wrapper.dut.regfile_inst.regs[3] !== 32'd5) begin
            $display("FAIL load x3 = %0d, expected 5", wrapper.dut.regfile_inst.regs[3]);
            errors = errors + 1;
        end else begin
            $display("PASS load x3 = %0d", wrapper.dut.regfile_inst.regs[3]);
        end

        if (wrapper.dut.regfile_inst.regs[4] !== 32'd7) begin
            $display("FAIL branch-on-load x4 = %0d, expected 7 (branch should be taken via forwarded loaded value)", wrapper.dut.regfile_inst.regs[4]);
            errors = errors + 1;
        end else begin
            $display("PASS branch-on-load x4 = %0d", wrapper.dut.regfile_inst.regs[4]);
        end

        if (errors == 0)
            $display("ALL LOAD-USE-INTO-BRANCH TESTS PASSED");
        else
            $display("LOAD-USE-INTO-BRANCH TEST FAILURES: %0d", errors);
        $finish;
    end

    initial begin
        #50000;
        $display("ERROR: tb_load_use_branch timed out");
        $finish;
    end
endmodule
