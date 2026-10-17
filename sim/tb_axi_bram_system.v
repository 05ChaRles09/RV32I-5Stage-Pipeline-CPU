`timescale 1ns / 1ps
//
// tb_axi_bram_system.v  Stage 2b 系統層級測試：CPU IP（EXTERNAL_MEM=1）+ 兩個 BMG 行為模型（port A 當 PS、port B 接 CPU）
//   1. FEATURE = 0x17
//   2. IMEM 以 board_program.hex 初始化（等同 COE）→ 經 AXI 放開 reset 執行 → x1..x31 與 dmem[0..15] 對照 board_program_expect.mem
//   3. PS（port A）讀回 IMEM 全內容 = 初始化內容；PS 能讀出 CPU 寫入 DMEM 的結果
//   4. reset → PS 清空 DMEM、載入 bram_timing.hex → 執行 → x1..x31 與 dmem[0..15] 對照 bram_timing_expect.mem，並讀回整塊 DMEM 其餘為 0
//   5. 執行中 PS 讀 DMEM 不影響 CPU（CPU 結果不變）
//
module tb_axi_bram_system;
    reg clk = 0, aresetn = 0;
    always #5 clk = ~clk;

    // ---- AXI-Lite master (CPU control registers) ----
    reg [5:0] awaddr, araddr; reg [31:0] wdata; reg awvalid=0, wvalid=0, arvalid=0, bready=1, rready=1;
    wire awready, wready, bvalid, arready, rvalid; wire [31:0] rdata; wire [1:0] bresp, rresp;
    // ---- CPU <-> BMG ----
    wire [31:0] i_addr, i_din, i_dout, d_addr, d_din, d_dout; wire i_clk, i_rst, i_en, d_clk, d_rst, d_en; wire [3:0] i_we, d_we;
    // ---- PS side of the BMGs (port A) ----
    reg        i_ena = 0, d_ena = 0; reg [3:0] i_wea = 0, d_wea = 0; reg [31:0] i_addra = 0, d_addra = 0, i_dina = 0, d_dina = 0;
    wire [31:0] i_douta, d_douta;

    rv32i_pipelined_cpu_v1_0 #(.EXTERNAL_MEM(1)) dut (
        .imem_bram_addr(i_addr), .imem_bram_clk(i_clk), .imem_bram_rst(i_rst), .imem_bram_en(i_en), .imem_bram_we(i_we), .imem_bram_din(i_din), .imem_bram_dout(i_dout),
        .dmem_bram_addr(d_addr), .dmem_bram_clk(d_clk), .dmem_bram_rst(d_rst), .dmem_bram_en(d_en), .dmem_bram_we(d_we), .dmem_bram_din(d_din), .dmem_bram_dout(d_dout),
        .s00_axi_aclk(clk), .s00_axi_aresetn(aresetn),
        .s00_axi_awaddr(awaddr), .s00_axi_awprot(3'b0), .s00_axi_awvalid(awvalid), .s00_axi_awready(awready),
        .s00_axi_wdata(wdata), .s00_axi_wstrb(4'hF), .s00_axi_wvalid(wvalid), .s00_axi_wready(wready),
        .s00_axi_bresp(bresp), .s00_axi_bvalid(bvalid), .s00_axi_bready(bready),
        .s00_axi_araddr(araddr), .s00_axi_arprot(3'b0), .s00_axi_arvalid(arvalid), .s00_axi_arready(arready),
        .s00_axi_rdata(rdata), .s00_axi_rresp(rresp), .s00_axi_rvalid(rvalid), .s00_axi_rready(rready));

    bmg_tdp_model #(.DEPTH_WORDS(1024), .INIT_FILE("board_program.hex")) imem_bmg (
        .clka(clk), .ena(i_ena), .wea(i_wea), .addra(i_addra), .dina(i_dina), .douta(i_douta),
        .clkb(i_clk), .enb(i_en), .web(i_we), .addrb(i_addr), .dinb(i_din), .doutb(i_dout));
    bmg_tdp_model #(.DEPTH_WORDS(1024), .INIT_FILE("")) dmem_bmg (
        .clka(clk), .ena(d_ena), .wea(d_wea), .addra(d_addra), .dina(d_dina), .douta(d_douta),
        .clkb(d_clk), .enb(d_en), .web(d_we), .addrb(d_addr), .dinb(d_din), .doutb(d_dout));

    task wr(input [5:0] a, input [31:0] d); begin
        @(posedge clk); #1 awaddr = a; wdata = d; awvalid = 1; wvalid = 1;
        @(posedge clk); while (!(awready && wready)) @(posedge clk);
        #1 awvalid = 0; wvalid = 0;
        @(posedge clk); while (!bvalid) @(posedge clk);
        #1;
    end endtask
    reg [31:0] rd_val;
    task rd(input [5:0] a); begin
        @(posedge clk); #1 araddr = a; arvalid = 1;
        @(posedge clk); while (!arready) @(posedge clk);
        #1 arvalid = 0;
        while (!rvalid) @(posedge clk);
        rd_val = rdata; @(posedge clk); #1;
    end endtask

    // PS access through port A (what the AXI BRAM Controller does): byte address = word*4
    task ps_iw(input [9:0] w, input [31:0] d); begin @(posedge clk); #1 i_ena=1; i_wea=4'hF; i_addra={20'b0,w,2'b00}; i_dina=d; @(posedge clk); #1 i_ena=0; i_wea=0; end endtask
    task ps_dw(input [9:0] w, input [31:0] d); begin @(posedge clk); #1 d_ena=1; d_wea=4'hF; d_addra={20'b0,w,2'b00}; d_dina=d; @(posedge clk); #1 d_ena=0; d_wea=0; end endtask
    reg [31:0] ps_val;
    task ps_ir(input [9:0] w); begin @(posedge clk); #1 i_ena=1; i_wea=0; i_addra={20'b0,w,2'b00}; @(posedge clk); #1 i_ena=0; @(posedge clk); #1 ps_val=i_douta; end endtask
    task ps_dr(input [9:0] w); begin @(posedge clk); #1 d_ena=1; d_wea=0; d_addra={20'b0,w,2'b00}; @(posedge clk); #1 d_ena=0; @(posedge clk); #1 ps_val=d_douta; end endtask

    reg [31:0] expmem [0:47];
    reg [31:0] prog [0:1023];
    reg [31:0] ref_i [0:1023];
    integer errors = 0, i;
    `define REGS dut.rv32i_pipelined_cpu_v1_0_S00_AXI_inst.rv32i_pipeline_inst.regfile_inst.regs
    task check(input [255:0] name, input [31:0] got, input [31:0] exp); begin
        if (got !== exp) begin $display("FAIL %0s: got 0x%08h expected 0x%08h", name, got, exp); errors = errors + 1; end
    end endtask
    task check_state(input [255:0] tag); integer k; begin
        for (k = 1; k < 32; k = k + 1) if (`REGS[k] !== expmem[k]) begin $display("FAIL %0s x%0d = 0x%08h expected 0x%08h", tag, k, `REGS[k], expmem[k]); errors = errors + 1; end
        for (k = 0; k < 16; k = k + 1) begin
            ps_dr(k); if (ps_val !== expmem[32+k]) begin $display("FAIL %0s dmem[%0d] (PS read) = 0x%08h expected 0x%08h", tag, k, ps_val, expmem[32+k]); errors = errors + 1; end
        end
    end endtask

    initial begin
        #23 aresetn = 1;
        rd(6'h2C); check("FEATURE", rd_val, 32'h17);
        // ---- 2/3. run the COE-style initialised board program ----
        $readmemh("board_program_expect.mem", expmem);
        $readmemh("board_program.hex", ref_i);
        wr(6'h00, 1); #6000;
        check_state("board");
        for (i = 0; i < 136; i = i + 1) begin ps_ir(i); if (ps_val !== ref_i[i]) begin errors = errors + 1; $display("FAIL imem readback word %0d", i); end end
        // ---- 4. reset, PS clears DMEM and loads a different program through port A ----
        wr(6'h00, 0);
        $readmemh("bram_timing.hex", prog);
        for (i = 0; i < 1024; i = i + 1) begin ps_dw(i, 32'h0); ps_iw(i, prog[i]); end
        for (i = 0; i < 1024; i = i + 1) begin ps_ir(i); if (ps_val !== prog[i]) begin errors = errors + 1; $display("FAIL imem load word %0d", i); end end
        $readmemh("bram_timing_expect.mem", expmem);
        wr(6'h00, 1);
        // ---- 5. PS keeps reading DMEM while the CPU runs ----
        for (i = 0; i < 40; i = i + 1) ps_dr(i % 16);
        #3000;
        check_state("bram_timing");
        for (i = 16; i < 1024; i = i + 1) begin ps_dr(i); if (ps_val !== 32'h0) begin errors = errors + 1; $display("FAIL dmem[%0d] not 0 (0x%08h)", i, ps_val); end end
        if (errors == 0) $display("ALL AXI BRAM SYSTEM TESTS PASSED");
        else             $display("AXI BRAM SYSTEM TEST FAILURES: %0d", errors);
        $finish;
    end
    initial begin #20000000; $display("TIMEOUT"); $finish; end
endmodule
