`timescale 1ns / 1ps
//
// tb_zbb_unit.v  Zbb 功能單元測試（經由 ALU 的 ALU_Control[5]=1 路徑）
//
// 資料檔：zbb_vectors.mem（請加入 Vivado 的 Simulation Sources）
//   每筆 4 個 hex 字： op  a  b  expected      (op = ALU_Control[4:0])
//   標準答案由 tools/rv32i_model.py 產生，涵蓋 17 個 Zbb 運算 × 邊界值 / 隨機值 / 所有移位量
//
// 成功時印出： ALL ZBB UNIT TESTS PASSED
//
module tb_zbb_unit;
    localparam MAXV = 20000;
    reg [31:0] vec [0:4*MAXV-1];
    reg [31:0] a, b;
    reg [5:0]  ctl;
    wire [31:0] res;
    wire        zero;

    alu dut (.A(a), .B(b), .ALU_Control(ctl), .Result(res), .Zero(zero));

    // ---- 在常見的 Vivado 模擬目錄中尋找資料檔 -------------------------
    reg [8*160-1:0] fpath;
    reg             fok;
    integer         fd;
    task try_open;
        input [8*160-1:0] p;
        begin
            if (!fok) begin
                fd = $fopen(p, "r");
                if (fd != 0) begin
                    $fclose(fd);
                    fpath = p;
                    fok   = 1;
                end
            end
        end
    endtask
    task locate_zbb_vectors;
        begin
            fok = 0;
            try_open("zbb_vectors.mem");
            try_open("sim/zbb_vectors.mem");
            try_open("../sim/zbb_vectors.mem");
            try_open("../../../../sim/zbb_vectors.mem");
            try_open("../../../../../sim/zbb_vectors.mem");
            try_open("../../../../../../sim/zbb_vectors.mem");
            try_open("../../../../../../../sim/zbb_vectors.mem");
        end
    endtask

    integer i, nvec, errors;
    reg [31:0] exp;
    initial begin
        for (i = 0; i < 4*MAXV; i = i + 1) vec[i] = 32'bx;
        locate_zbb_vectors;
        if (!fok) begin
            $display("ERROR: 找不到 zbb_vectors.mem，請把 sim/zbb_vectors.mem 加入 Simulation Sources");
            $finish;
        end
        $readmemh(fpath, vec);
        nvec = 0; errors = 0;
        while (nvec < MAXV && vec[4*nvec+3] !== 32'bx) nvec = nvec + 1;
        if (nvec == 0) begin
            $display("ERROR: zbb_vectors.mem 沒有讀到任何向量");
            $finish;
        end
        for (i = 0; i < nvec; i = i + 1) begin
            ctl = {1'b1, vec[4*i][4:0]};
            a   = vec[4*i+1];
            b   = vec[4*i+2];
            exp = vec[4*i+3];
            #1;
            if (res !== exp) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("FAIL op=%0d a=0x%08h b=0x%08h got=0x%08h expected=0x%08h", vec[4*i][4:0], a, b, res, exp);
            end
        end
        $display("zbb vectors checked: %0d, failures: %0d", nvec, errors);
        if (errors == 0) $display("ALL ZBB UNIT TESTS PASSED");
        else             $display("ZBB UNIT TEST FAILURES: %0d", errors);
        $finish;
    end
endmodule
