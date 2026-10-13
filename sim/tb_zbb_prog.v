`timescale 1ns / 1ps
//
// tb_zbb_prog.v  Zbb / 隨機程式整合測試：逐支程式執行後，與 Python 參考模型的最終狀態逐字比對
//
// 資料檔（請加入 Vivado 的 Simulation Sources）
//   zbb_prog.hex          NP 支程式，每支 1024 字，依序串接
//   zbb_prog_expect.mem   NP 組預期狀態，每組 1056 字 = x0..x31 + dmem[0..1023]
// 內容：5 支 Zbb directed 程式（每個指令 × 邊界值）+ 30 支隨機 RV32I/Zbb 程式
//       （含 forwarding、load-use stall、分支 flush）。重新產生： python3 tools/gen_tests.py
//
// 每支程式：reset → 清 dmem → 載入 imem → 放開 reset → 跑 NCYC 個 cycle → 比對 x1..x31 與 dmem
// 成功時印出： ALL ZBB PROGRAM TESTS PASSED
//
module tb_zbb_prog;
    localparam MAXP = 64;
    localparam PW   = 1024;          // 每支程式的字數
    localparam EW   = 32 + 1024;     // 每組預期狀態的字數
    localparam NCYC = 2500;          // 每支程式執行的 cycle 數（最長的程式約 1000 條指令）

    reg clk   = 0;
    reg rst_n = 0;
    wire        illegal_flag;
    wire [31:0] illegal_pc;

    rv32i_pipeline #(.IMEM_FILE("program.hex")) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .illegal_out    (illegal_flag),
        .illegal_pc_out (illegal_pc)
    );

    always #5 clk = ~clk;

    reg [31:0] progmem [0:MAXP*PW-1];
    reg [31:0] expmem  [0:MAXP*EW-1];

    // ---- 在常見的 Vivado 模擬目錄中尋找資料檔 -------------------------
    reg [8*160-1:0] fpath_prog, fpath_exp;
    reg             fok;
    integer         fd;
    task try_open_prog;
        input [8*160-1:0] p;
        begin
            if (!fok) begin
                fd = $fopen(p, "r");
                if (fd != 0) begin $fclose(fd); fpath_prog = p; fok = 1; end
            end
        end
    endtask
    task try_open_exp;
        input [8*160-1:0] p;
        begin
            if (!fok) begin
                fd = $fopen(p, "r");
                if (fd != 0) begin $fclose(fd); fpath_exp = p; fok = 1; end
            end
        end
    endtask
    task locate_all;
        begin
            fok = 0;
            try_open_prog("zbb_prog.hex");
            try_open_prog("sim/zbb_prog.hex");
            try_open_prog("../sim/zbb_prog.hex");
            try_open_prog("../../../../sim/zbb_prog.hex");
            try_open_prog("../../../../../sim/zbb_prog.hex");
            try_open_prog("../../../../../../sim/zbb_prog.hex");
            try_open_prog("../../../../../../../sim/zbb_prog.hex");
            if (!fok) begin
                $display("ERROR: 找不到 zbb_prog.hex，請把 sim/zbb_prog.hex 加入 Simulation Sources");
                $finish;
            end
            fok = 0;
            try_open_exp("zbb_prog_expect.mem");
            try_open_exp("sim/zbb_prog_expect.mem");
            try_open_exp("../sim/zbb_prog_expect.mem");
            try_open_exp("../../../../sim/zbb_prog_expect.mem");
            try_open_exp("../../../../../sim/zbb_prog_expect.mem");
            try_open_exp("../../../../../../sim/zbb_prog_expect.mem");
            try_open_exp("../../../../../../../sim/zbb_prog_expect.mem");
            if (!fok) begin
                $display("ERROR: 找不到 zbb_prog_expect.mem，請把 sim/zbb_prog_expect.mem 加入 Simulation Sources");
                $finish;
            end
        end
    endtask

    integer p, i, np, perr, total_err, npass;

    initial begin
        for (i = 0; i < MAXP*PW; i = i + 1) progmem[i] = 32'bx;
        for (i = 0; i < MAXP*EW; i = i + 1) expmem[i]  = 32'bx;
        #1;                                   // 等 imem.v 自己的 initial 載入完成後再覆蓋
        locate_all;
        $readmemh(fpath_prog, progmem);
        $readmemh(fpath_exp,  expmem);
        np = 0;
        while (np < MAXP && progmem[np*PW] !== 32'bx) np = np + 1;
        if (np == 0) begin
            $display("ERROR: zbb_prog.hex 沒有讀到任何程式");
            $finish;
        end
        total_err = 0; npass = 0;

        for (p = 0; p < np; p = p + 1) begin
            rst_n = 0;
            for (i = 0; i < 1024; i = i + 1) dut.dmem_inst.mem[i] = 32'b0;
            for (i = 0; i < PW;   i = i + 1) dut.imem_inst.mem[i] = progmem[p*PW + i];
            repeat (3) @(posedge clk);
            #1 rst_n = 1;
            repeat (NCYC) @(posedge clk);
            #1;
            perr = 0;
            for (i = 1; i < 32; i = i + 1)               // x0 為硬接 0（regfile.v 只有 regs[1:31]）
                if (dut.regfile_inst.regs[i] !== expmem[p*EW + i]) begin
                    perr = perr + 1;
                    if (perr <= 5)
                        $display("FAIL prog %0d: x%0d = 0x%08h, expected 0x%08h", p, i, dut.regfile_inst.regs[i], expmem[p*EW + i]);
                end
            for (i = 0; i < 1024; i = i + 1)
                if (dut.dmem_inst.mem[i] !== expmem[p*EW + 32 + i]) begin
                    perr = perr + 1;
                    if (perr <= 5)
                        $display("FAIL prog %0d: dmem[%0d] = 0x%08h, expected 0x%08h", p, i, dut.dmem_inst.mem[i], expmem[p*EW + 32 + i]);
                end
            if (illegal_flag) begin
                perr = perr + 1;
                $display("FAIL prog %0d: 非預期的 illegal instruction, pc=0x%08h", p, illegal_pc);
            end
            if (perr == 0) npass = npass + 1;
            else           total_err = total_err + perr;
        end

        $display("programs run: %0d, passed: %0d", np, npass);
        if (total_err == 0) $display("ALL ZBB PROGRAM TESTS PASSED (%0d programs)", np);
        else                $display("ZBB PROGRAM TEST FAILURES: %0d", total_err);
        $finish;
    end
endmodule
