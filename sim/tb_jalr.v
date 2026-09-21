`timescale 1ns / 1ps
//
// tb_jalr.v dedicated JALR regression test
//
// Program (see gen_extra_programs.py / jalr.hex):
//   0x00: lui  x1, 0x0
//   0x04: addi x1, x1, 0x40      ; x1 = 0x40 (jump target)
//   0x08: jalr x5, x1, 0         ; jump to x1+0 = 0x40, link x5 = pc+4 = 0x0c
//   0x0c: addi x2, x0, 99        ; must be FLUSHED (never executes)
//   0x10..0x3c: nop (12 nops, padding to reach 0x40)
//   0x40: addi x2, x0, 7         ; jalr target proven correct if x2 becomes 7
//   0x44: jal x0, spin
//   0x48: spin: jal x0, spin
//
// Pass criteria: x5 == 0x0c (correct link address) AND x2 == 7 (correct jump
// target, and the fall-through instruction at 0x0c was flushed, not executed).
//
module tb_jalr;
    reg clk;
    reg rst_n;

    rv32i_dut_jalr wrapper (
        .clk   (clk),
        .rst_n (rst_n)
    );

    always #5 clk = ~clk;

    integer errors = 0;

    initial begin
        $dumpfile("jalr.vcd");
        $dumpvars(0, tb_jalr);

        clk = 0;
        rst_n = 0;
        #15 rst_n = 1;
        #400;

        if (wrapper.dut.regfile_inst.regs[5] !== 32'h0000000c) begin
            $display("FAIL jalr link x5 = 0x%08h, expected 0x0000000c", wrapper.dut.regfile_inst.regs[5]);
            errors = errors + 1;
        end else begin
            $display("PASS jalr link x5 = 0x%08h", wrapper.dut.regfile_inst.regs[5]);
        end

        if (wrapper.dut.regfile_inst.regs[2] !== 32'd7) begin
            $display("FAIL jalr target x2 = %0d, expected 7 (jalr target not reached, or fall-through not flushed)", wrapper.dut.regfile_inst.regs[2]);
            errors = errors + 1;
        end else begin
            $display("PASS jalr target x2 = %0d", wrapper.dut.regfile_inst.regs[2]);
        end

        if (errors == 0)
            $display("ALL JALR TESTS PASSED");
        else
            $display("JALR TEST FAILURES: %0d", errors);
        $finish;
    end

    initial begin
        #50000;
        $display("ERROR: tb_jalr timed out");
        $finish;
    end
endmodule
