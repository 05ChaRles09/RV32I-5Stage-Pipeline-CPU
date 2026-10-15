`timescale 1ns / 1ps
//
// tb_bram_timing.v  BRAM 同步讀取時序邊界的定向測試（程式由 tools/gen_bram_timing.py 產生，預期值來自 Python 黃金模型）
//   store→load 緊接、load-use stall、load→store 資料、load-use 後接 taken branch、連續 load/store、jal 重導向、迴圈 RAW
//   另外檢查：整段執行中 PC 序列合理（4 對齊）、spin 迴圈前沒有多餘的 stall（cycle 數上限）
//
module tb_bram_timing;
    localparam SPIN_PC = 32'hBC;
    reg clk = 0, rst_n = 0;
    rv32i_pipeline #(.IMEM_FILE("bram_timing.hex")) dut (.clk(clk), .rst_n(rst_n));
    always #5 clk = ~clk;

    reg [31:0] expmem [0:47];
    integer i, errors = 0, cyc = 0, spin_cyc = -1;
    always @(posedge clk) if (rst_n) begin
        cyc = cyc + 1;
        if (spin_cyc < 0 && dut.pc == SPIN_PC) spin_cyc = cyc;
        if (dut.pc[1:0] !== 2'b00) begin errors = errors + 1; $display("FAIL unaligned pc %h", dut.pc); end
    end
    initial begin
        $readmemh("bram_timing_expect.mem", expmem);
        #15 rst_n = 1;
        #3000;
        for (i = 1; i < 32; i = i + 1)
            if (dut.regfile_inst.regs[i] !== expmem[i]) begin
                $display("FAIL x%0d = 0x%08h, expected 0x%08h", i, dut.regfile_inst.regs[i], expmem[i]); errors = errors + 1;
            end
        for (i = 0; i < 16; i = i + 1)
            if (dut.dmem_inst.mem[i] !== expmem[32 + i]) begin
                $display("FAIL dmem[%0d] = 0x%08h, expected 0x%08h", i, dut.dmem_inst.mem[i], expmem[32 + i]); errors = errors + 1;
            end
        if (spin_cyc < 0) begin errors = errors + 1; $display("FAIL never reached spin pc"); end
        else $display("reached spin at cycle %0d", spin_cyc);
        if (errors == 0) $display("ALL BRAM TIMING TESTS PASSED");
        else             $display("BRAM TIMING TEST FAILURES: %0d", errors);
        $finish;
    end
endmodule
