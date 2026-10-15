`timescale 1ns / 1ps
// tb_axi_imem_load.v  Phase 4 Stage 1: load a program through the AXI-Lite wrapper (0x30/0x34/0x38) and run it.
//   1. default program runs on power-up (FEATURE = 0xF)
//   2. CPU in reset -> load a new 4-instruction program -> run -> x1/x2/x3 match
//   3. write to IMEM_DATA while running is rejected (sticky flag, memory unchanged)
//   4. reload a different program (reset again) -> new result
module tb_axi_imem_load;
    reg clk = 0, aresetn = 0;
    always #5 clk = ~clk;
    reg [5:0] awaddr, araddr; reg [31:0] wdata; reg awvalid=0, wvalid=0, arvalid=0, bready=1, rready=1;
    wire awready, wready, bvalid, arready, rvalid; wire [31:0] rdata; wire [1:0] bresp, rresp;
    rv32i_pipelined_cpu_v1_0_S00_AXI #(.C_S_AXI_DATA_WIDTH(32), .C_S_AXI_ADDR_WIDTH(6), .IMEM_FILE("__none__.hex")) dut (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(aresetn),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(3'b0), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(4'hF), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(3'b0), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready));

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

    integer errors = 0, i;
    task check(input [255:0] name, input [31:0] got, input [31:0] exp); begin
        if (got !== exp) begin $display("FAIL %0s: got 0x%08h expected 0x%08h", name, got, exp); errors = errors + 1; end
    end endtask
    task load(input [31:0] w0, input [31:0] w1, input [31:0] w2, input [31:0] w3); begin
        wr(6'h30, 0); wr(6'h34, w0); wr(6'h34, w1); wr(6'h34, w2); wr(6'h34, w3);
        for (i = 0; i < 12; i = i + 1) wr(6'h34, 32'h00000013);   // NOP pad
        wr(6'h34, 32'h0000006f);                                  // spin: jal x0,0
    end endtask

    initial begin
        #23 aresetn = 1;
        rd(6'h2C); check("FEATURE", rd_val, 32'h0000000F);
        // default program runs
        wr(6'h00, 1); repeat (300) @(posedge clk);
        if (dut.rv32i_pipeline_inst.regfile_inst.regs[1] === 32'h0) begin $display("FAIL default program did not run"); errors = errors + 1; end
        // ---- load program A while in reset ----
        wr(6'h00, 0);
        load(32'h00500093 /*addi x1,x0,5*/, 32'h00700113 /*addi x2,x0,7*/, 32'h002081b3 /*add x3,x1,x2*/, 32'h00302023 /*sw x3,0(x0)*/);
        rd(6'h38); check("IMEM_STATUS cnt", rd_val, 32'h00000011);
        rd(6'h30); check("IMEM_ADDR", rd_val, 32'h00000011);
        wr(6'h00, 1); repeat (60) @(posedge clk);
        check("x1", dut.rv32i_pipeline_inst.regfile_inst.regs[1], 5);
        check("x2", dut.rv32i_pipeline_inst.regfile_inst.regs[2], 7);
        check("x3", dut.rv32i_pipeline_inst.regfile_inst.regs[3], 12);
        check("dmem0", dut.rv32i_pipeline_inst.dmem_inst.mem[0], 12);
        // ---- write while running: rejected ----
        wr(6'h30, 0); wr(6'h34, 32'h00900093);
        rd(6'h38); check("rejected flag", rd_val[31], 1);
        repeat (20) @(posedge clk);
        check("imem[0] unchanged", dut.rv32i_pipeline_inst.imem_inst.mem[0], 32'h00500093);
        check("imem_idx not advanced", dut.imem_idx, 0);
        check("x1 unchanged", dut.rv32i_pipeline_inst.regfile_inst.regs[1], 5);
        wr(6'h38, 0); rd(6'h38); check("status cleared", rd_val, 0);
        // ---- reload program B ----
        wr(6'h00, 0);
        load(32'h02a00093 /*addi x1,x0,42*/, 32'h00100113 /*addi x2,x0,1*/, 32'h402081b3 /*sub x3,x1,x2*/, 32'h00000013);
        wr(6'h00, 1); repeat (60) @(posedge clk);
        check("B x1", dut.rv32i_pipeline_inst.regfile_inst.regs[1], 42);
        check("B x3", dut.rv32i_pipeline_inst.regfile_inst.regs[3], 41);
        if (errors == 0) $display("ALL AXI IMEM LOAD TESTS PASSED");
        else $display("AXI IMEM LOAD TESTS FAILED: %0d errors", errors);
        $finish;
    end
    initial begin #2000000; $display("TIMEOUT"); $finish; end
endmodule
