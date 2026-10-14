`timescale 1ns / 1ps
//
// tb_imem_default.v  imem.v 內建（寫死）程式的完整性檢查
//   MEM_FILE 指向不存在的檔案 → $readmemh 失敗 → 只剩內建預設內容（= 合成進 bitstream 的內容）
//   預期：mem[0..135] == board_program.hex，其後全為 NOP（0x00000013）
//   （過去曾因 NOP 填充迴圈蓋掉內建程式尾端而在實板上被截斷，這個測試專門防止再發生）
//
module tb_imem_default;
    reg  [31:0] addr = 0;
    wire [31:0] instr;
    imem #(.ADDR_WIDTH(12), .MEM_FILE("__no_such_file__.hex")) u (.addr(addr), .instr(instr));
    reg [31:0] ref [0:135];
    integer i, errors = 0;
    initial begin
        $readmemh("board_program.hex", ref);
        #1;
        for (i = 0; i < 136; i = i + 1) begin
            addr = i * 4; #1;
            if (instr !== ref[i]) begin errors = errors + 1; $display("FAIL word %0d: imem=%08h expect=%08h", i, instr, ref[i]); end
        end
        addr = 136 * 4; #1; if (instr !== 32'h00000013) begin errors = errors + 1; $display("FAIL word 136 is not NOP"); end
        addr = 1023 * 4; #1; if (instr !== 32'h00000013) begin errors = errors + 1; $display("FAIL word 1023 is not NOP"); end
        if (errors == 0) $display("ALL IMEM DEFAULT TESTS PASSED (136 words)");
        else             $display("IMEM DEFAULT TEST FAILURES: %0d", errors);
        $finish;
    end
endmodule
