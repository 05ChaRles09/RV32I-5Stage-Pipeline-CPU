`timescale 1ns / 1ps
//
// tb_board_program.v  上板測試程式（board_program.hex = imem.v 內建程式）的整合驗證
//   資料檔：board_program.hex、board_program_expect.mem（x0..x31 + dmem[0..15]，由 tools/gen_board_test.py 產生）
//   檢查：最終 x1..x31、dmem[0..15]、第一個 illegal PC、spin 前所需 cycle 數（trace buffer 為 256 筆，需 <= 240）
//
module tb_board_program;
    localparam SPIN_PC    = 32'h21C;   // 與 gen_board_test.py 輸出的 spin PC 相同
    localparam FIRST_ILL  = 32'h1F4;
    reg clk = 0, rst_n = 0;
    wire        illegal_flag;
    wire [31:0] illegal_pc;

    rv32i_pipeline #(.IMEM_FILE("board_program.hex")) dut (
        .clk(clk), .rst_n(rst_n), .illegal_out(illegal_flag), .illegal_pc_out(illegal_pc));

    always #5 clk = ~clk;

    reg [31:0] expmem [0:47];
    integer i, errors = 0, cyc = 0, spin_cyc = -1;

    always @(posedge clk) if (rst_n) begin
        cyc = cyc + 1;
        if (spin_cyc < 0 && dut.pc == SPIN_PC) spin_cyc = cyc;
    end

    initial begin
        $readmemh("board_program_expect.mem", expmem);
        #15 rst_n = 1;
        #4000;
        for (i = 1; i < 32; i = i + 1)
            if (dut.regfile_inst.regs[i] !== expmem[i]) begin
                $display("FAIL x%0d = 0x%08h, expected 0x%08h", i, dut.regfile_inst.regs[i], expmem[i]);
                errors = errors + 1;
            end
        for (i = 0; i < 16; i = i + 1)
            if (dut.dmem_inst.mem[i] !== expmem[32 + i]) begin
                $display("FAIL dmem[%0d] = 0x%08h, expected 0x%08h", i, dut.dmem_inst.mem[i], expmem[32 + i]);
                errors = errors + 1;
            end
        if (illegal_flag !== 1'b1 || illegal_pc !== FIRST_ILL) begin
            $display("FAIL illegal flag=%b pc=0x%08h, expected 1 / 0x%08h", illegal_flag, illegal_pc, FIRST_ILL);
            errors = errors + 1;
        end
        $display("cycles until spin PC: %0d (trace buffer 256, need <= 240)", spin_cyc);
        if (spin_cyc < 0 || spin_cyc > 240) begin
            $display("FAIL program too long for the 256-entry trace buffer"); errors = errors + 1;
        end
        if (errors == 0) $display("ALL BOARD PROGRAM TESTS PASSED");
        else             $display("BOARD PROGRAM TEST FAILURES: %0d", errors);
        $finish;
    end
endmodule
