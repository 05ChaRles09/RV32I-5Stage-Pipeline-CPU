`timescale 1ns / 1ps
//
// tb_extra_branches.v dedicated signed/unsigned branch + AUIPC regression test
//
// Program (see gen_extra_programs.py / extra.hex) covers:
//   - BLT  taken  (signed: -4 < 7)
//   - BGE  false  (signed: -4 >= 7 is false -> fall-through executed)
//   - BLTU false (unsigned: 0xFFFFFFFF < 7 is false -> fall-through)
//   - BGEU taken  (unsigned: 0xFFFFFFFF >= 7 is true -> branch taken)
//   - AUIPC (x7 = pc of auipc instruction + 0)
//
module tb_extra_branches;
    reg clk;
    reg rst_n;

    rv32i_dut_extra wrapper (
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
            got = wrapper.dut.regfile_inst.regs[idx];
            if (got !== exp) begin
                $display("FAIL %-22s x%0d = %0d (0x%08h), expected %0d (0x%08h)",
                         name, idx, got, got, exp, exp);
                errors = errors + 1;
            end else begin
                $display("PASS %-22s x%0d = %0d", name, idx, got);
            end
        end
    endtask

    initial begin
        $dumpfile("extra.vcd");
        $dumpvars(0, tb_extra_branches);

        clk = 0;
        rst_n = 0;
        #15 rst_n = 1;
        #1000;

        check("blt taken x3",      3, 5);
        check("bge not taken x4",  4, 7);
        check("bltu false x5",     5, 9);
        check("auipc x7",         7, 32'h00000040);

        if (errors == 0)
            $display("ALL EXTRA BRANCH TESTS PASSED");
        else
            $display("EXTRA BRANCH TEST FAILURES: %0d", errors);
        $finish;
    end

    initial begin
        #50000;
        $display("ERROR: tb_extra_branches timed out");
        $finish;
    end
endmodule
