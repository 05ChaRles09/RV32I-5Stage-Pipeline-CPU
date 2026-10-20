`timescale 1ns / 1ps
//
// tb_archtest.v  riscv-arch-test 用 testbench（記憶體放大為 2 MB 的獨立 rv32i_pipeline）
//   plusargs：+imem=<指令 hex> +dmem=<資料 hex（字索引 0 = DMEM 位址 0x200000）> +halt=<self_loop 位址，十進位>
//             +sigidx=<簽章起點的 DMEM 字索引> +siglen=<簽章字數> +out=<輸出檔> [+maxcyc=<上限>]
//   動作：reset 放開後執行，直到 self_loop 指令第一次進入 EX（用 ex_pc / ex_valid，避免 wrong-path 預取），
//         再等 30 個 cycle 讓最後的 store 完成，然後把簽章字（每行 8 位十六進位）寫到 +out。
//   輸出一行：ARCHTEST cycles=<n> illegal=<0/1> status=OK；逾時印 ARCHTEST TIMEOUT
//
module tb_archtest;
    reg clk = 0, rst_n = 0;
    wire ill;
    rv32i_pipeline #(.IMEM_ADDR_WIDTH(21), .DMEM_ADDR_WIDTH(21), .IMEM_FILE("none.hex")) dut (.clk(clk), .rst_n(rst_n), .illegal_out(ill));
    always #5 clk = ~clk;

    reg [8*300-1:0] imemf, dmemf, outf;
    integer halt = -1, sigidx = 0, siglen = 0, maxcyc = 20000000;
    integer cyc = 0, hit = -1, post = 0, i, fd;

    initial begin
        if (!$value$plusargs("imem=%s", imemf)) begin $display("missing +imem"); $finish; end
        if (!$value$plusargs("dmem=%s", dmemf)) begin $display("missing +dmem"); $finish; end
        if (!$value$plusargs("halt=%d", halt))  begin $display("missing +halt"); $finish; end
        if (!$value$plusargs("sigidx=%d", sigidx)) begin $display("missing +sigidx"); $finish; end
        if (!$value$plusargs("siglen=%d", siglen)) begin $display("missing +siglen"); $finish; end
        if (!$value$plusargs("out=%s", outf))   begin $display("missing +out"); $finish; end
        if ($value$plusargs("maxcyc=%d", maxcyc)) ;
        #1;
        $readmemh(imemf, dut.imem_inst.mem);
        $readmemh(dmemf, dut.dmem_inst.mem);
        #14 rst_n = 1;
    end

    always @(posedge clk) if (rst_n) begin
        cyc = cyc + 1;
        if (hit < 0) begin
            if (dut.ex_valid && dut.ex_pc == halt) hit = cyc;
        end else begin
            post = post + 1;
            if (post == 30) begin
                fd = $fopen(outf, "w");
                for (i = 0; i < siglen; i = i + 1) $fwrite(fd, "%08x\n", dut.dmem_inst.mem[sigidx + i]);
                $fclose(fd);
                $display("ARCHTEST cycles=%0d illegal=%0d status=OK", hit, ill);
                $finish;
            end
        end
        if (cyc > maxcyc) begin $display("ARCHTEST TIMEOUT"); $finish; end
    end
endmodule
