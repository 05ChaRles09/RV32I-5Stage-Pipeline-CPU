`timescale 1ns / 1ps
//
// tb_bench.v  XDOTP16 效益量測用 testbench（由 sim/run_bench.sh 或 run_bench.bat 對每支程式各跑一次）
//   plusargs：+hex=<程式.hex> +dmem=<DMEM 初始內容> +expect=<DMEM 預期最終內容> +spin=<spin PC，十進位> +tag=<標籤>
//   動作：reset 放開後開始計 cycle，直到「位於 spin PC 的 jal x0,0 第一次進入 EX 階段」為止（用 ex_pc / ex_valid，
//         而不是 IF 的 pc：IF 會在分支尚未解析時先預取到 spin 位址，那是 wrong-path，不算完成），
//         再多等 20 個 cycle 讓最後一筆 store 完成，然後比對整塊 DMEM（1024 字）。
//   輸出一行：BENCH tag=.. cycles=.. stall=.. flush=.. mismatch=..；全部一致時印出 ALL BENCH PASSED
//   cycles    = reset 放開後到 spin 指令進入 EX 的 cycle 數（含 pipeline 填充；第 1 個 cycle 起算）
//   stall     = load-use stall 的 cycle 數；flush = taken branch / jal 造成的 flush cycle 數（各浪費 1 個 IF 槽，EX 解析 → 2 個 bubble）
//
module tb_bench;
    reg clk = 0, rst_n = 0;
    rv32i_pipeline dut (.clk(clk), .rst_n(rst_n));
    always #5 clk = ~clk;

    reg [8*200-1:0] hexf, dmf, expf, tag;
    integer spin = -1, i, mismatch = 0, cyc = 0, spin_cyc = -1, n_stall = 0, n_flush = 0, post = 0;
    reg [31:0] expmem [0:1023];
    reg done = 0;

    initial begin
        if (!$value$plusargs("hex=%s", hexf)) begin $display("missing +hex"); $finish; end
        if (!$value$plusargs("dmem=%s", dmf)) begin $display("missing +dmem"); $finish; end
        if (!$value$plusargs("expect=%s", expf)) begin $display("missing +expect"); $finish; end
        if (!$value$plusargs("spin=%d", spin)) begin $display("missing +spin"); $finish; end
        if (!$value$plusargs("tag=%s", tag)) tag = "?";
        #1;                                   // imem/dmem 的 initial 區塊已在 time 0 跑完；此時覆蓋內容（reset 尚未放開）
        $readmemh(hexf, dut.imem_inst.mem);
        $readmemh(dmf, dut.dmem_inst.mem);
        $readmemh(expf, expmem);
        #14 rst_n = 1;
    end

    always @(posedge clk) if (rst_n && !done) begin
        if (spin_cyc < 0) begin
            cyc = cyc + 1;
            if (dut.if_id_stall) n_stall = n_stall + 1;
            if (dut.if_id_flush) n_flush = n_flush + 1;
            if (dut.ex_valid && dut.ex_pc == spin) spin_cyc = cyc;
        end else begin
            post = post + 1;
            if (post == 20) begin
                for (i = 0; i < 1024; i = i + 1)
                    if (dut.dmem_inst.mem[i] !== expmem[i]) mismatch = mismatch + 1;
                $display("BENCH tag=%0s cycles=%0d stall=%0d flush=%0d mismatch=%0d", tag, spin_cyc, n_stall, n_flush, mismatch);
                if (mismatch == 0) $display("ALL BENCH PASSED");
                else               $display("BENCH FAILURES: %0d", mismatch);
                done = 1;
                $finish;
            end
        end
        if (cyc > 3000000) begin $display("BENCH TIMEOUT tag=%0s", tag); $finish; end
    end
endmodule
