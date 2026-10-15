
`timescale 1 ns / 1 ps

	module rv32i_pipelined_cpu_v1_0_S00_AXI #
	(
		// Users to add parameters here
        parameter IMEM_FILE = "program.hex",
		// User parameters ends
		// Do not modify the parameters beyond this line

		// Width of S_AXI data bus
		parameter integer C_S_AXI_DATA_WIDTH	= 32,
		// Width of S_AXI address bus
		parameter integer C_S_AXI_ADDR_WIDTH	= 6
	)
	(
		// Users to add ports here

		// User ports ends
		// Do not modify the ports beyond this line

		// Global Clock Signal
		input wire  S_AXI_ACLK,
		// Global Reset Signal. This Signal is Active LOW
		input wire  S_AXI_ARESETN,
		// Write address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
		// Write channel Protection type. This signal indicates the
    		// privilege and security level of the transaction, and whether
    		// the transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_AWPROT,
		// Write address valid. This signal indicates that the master signaling
    		// valid write address and control information.
		input wire  S_AXI_AWVALID,
		// Write address ready. This signal indicates that the slave is ready
    		// to accept an address and associated control signals.
		output wire  S_AXI_AWREADY,
		// Write data (issued by master, acceped by Slave) 
		input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
		// Write strobes. This signal indicates which byte lanes hold
    		// valid data. There is one write strobe bit for each eight
    		// bits of the write data bus.    
		input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
		// Write valid. This signal indicates that valid write
    		// data and strobes are available.
		input wire  S_AXI_WVALID,
		// Write ready. This signal indicates that the slave
    		// can accept the write data.
		output wire  S_AXI_WREADY,
		// Write response. This signal indicates the status
    		// of the write transaction.
		output wire [1 : 0] S_AXI_BRESP,
		// Write response valid. This signal indicates that the channel
    		// is signaling a valid write response.
		output wire  S_AXI_BVALID,
		// Response ready. This signal indicates that the master
    		// can accept a write response.
		input wire  S_AXI_BREADY,
		// Read address (issued by master, acceped by Slave)
		input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
		// Protection type. This signal indicates the privilege
    		// and security level of the transaction, and whether the
    		// transaction is a data access or an instruction access.
		input wire [2 : 0] S_AXI_ARPROT,
		// Read address valid. This signal indicates that the channel
    		// is signaling valid read address and control information.
		input wire  S_AXI_ARVALID,
		// Read address ready. This signal indicates that the slave is
    		// ready to accept an address and associated control signals.
		output wire  S_AXI_ARREADY,
		// Read data (issued by slave)
		output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
		// Read response. This signal indicates the status of the
    		// read transfer.
		output wire [1 : 0] S_AXI_RRESP,
		// Read valid. This signal indicates that the channel is
    		// signaling the required read data.
		output wire  S_AXI_RVALID,
		// Read ready. This signal indicates that the master can
    		// accept the read data and response information.
		input wire  S_AXI_RREADY
	);

	// AXI4LITE signals
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
	reg  	axi_awready;
	reg  	axi_wready;
	reg [1 : 0] 	axi_bresp;
	reg  	axi_bvalid;
	reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
	reg  	axi_arready;
	reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
	reg [1 : 0] 	axi_rresp;
	reg  	axi_rvalid;

	// Example-specific design signals
	// local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	// ADDR_LSB is used for addressing 32/64 bit registers/memories
	// ADDR_LSB = 2 for 32 bits (n downto 2)
	// ADDR_LSB = 3 for 64 bits (n downto 3)
	localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
	localparam integer OPT_MEM_ADDR_BITS = 3;
	//----------------------------------------------
	//-- Signals for user logic register space example
	//------------------------------------------------
	//-- Number of Slave Registers 4
	reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
	wire	 slv_reg_rden;
	wire	 slv_reg_wren;
	reg [C_S_AXI_DATA_WIDTH-1:0]	 reg_data_out;
	integer	 byte_index;
	reg aw_en;

	// Trace buffer state (declared early; logic below)
	reg [8:0]  tr_wptr;
	reg [7:0]  tr_ridx;
	reg        tr_armed;
	reg [31:0] tr_pc_mem  [0:255];
	reg [31:0] tr_wbd_mem [0:255];
	reg [5:0]  tr_meta_mem[0:255];
	wire       tr_full = tr_wptr[8];

    wire [31:0] pc_out_wire, wb_data_out_wire, dmem_rdata_out_wire;
    wire [4:0] wb_rd_out_wire;
    wire        illegal_out_wire;
    wire [31:0] illegal_pc_out_wire;
    wire wb_we_out_wire;
    
	// I/O Connections assignments

	assign S_AXI_AWREADY	= axi_awready;
	assign S_AXI_WREADY	= axi_wready;
	assign S_AXI_BRESP	= axi_bresp;
	assign S_AXI_BVALID	= axi_bvalid;
	assign S_AXI_ARREADY	= axi_arready;
	assign S_AXI_RDATA	= axi_rdata;
	assign S_AXI_RRESP	= axi_rresp;
	assign S_AXI_RVALID	= axi_rvalid;
	// Implement axi_awready generation
	// axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	// de-asserted when reset is low.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awready <= 1'b0;
	      aw_en <= 1'b1;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // slave is ready to accept write address when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_awready <= 1'b1;
	          aw_en <= 1'b0;
	        end
	        else if (S_AXI_BREADY && axi_bvalid)
	            begin
	              aw_en <= 1'b1;
	              axi_awready <= 1'b0;
	            end
	      else           
	        begin
	          axi_awready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_awaddr latching
	// This process is used to latch the address when both 
	// S_AXI_AWVALID and S_AXI_WVALID are valid. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_awaddr <= 0;
	    end 
	  else
	    begin    
	      if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
	        begin
	          // Write Address latching 
	          axi_awaddr <= S_AXI_AWADDR;
	        end
	    end 
	end       

	// Implement axi_wready generation
	// axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	// S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	// de-asserted when reset is low. 

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_wready <= 1'b0;
	    end 
	  else
	    begin    
	      if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en )
	        begin
	          // slave is ready to accept write data when 
	          // there is a valid write address and write data
	          // on the write address and data bus. This design 
	          // expects no outstanding transactions. 
	          axi_wready <= 1'b1;
	        end
	      else
	        begin
	          axi_wready <= 1'b0;
	        end
	    end 
	end       

	// Implement memory mapped register select and write logic generation
	// The write data is accepted and written to memory mapped registers when
	// axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	// select byte enables of slave registers while writing.
	// These registers are cleared when reset (active low) is applied.
	// Slave register write enable is asserted when valid address and data are available
	// and the slave is ready to accept the write address and write data.
	assign slv_reg_wren = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;

	// Write logic: CTRL (0x00) bit0 = rst_n (0 reset / 1 run), bit1 = trace arm pulse.
	// TRACE_IDX (0x14) is written in the trace section below.
	reg tr_arm_pulse;
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      slv_reg0 <= 0;
	      tr_arm_pulse <= 1'b0;
	    end
	  else begin
	    tr_arm_pulse <= 1'b0;
	    if (slv_reg_wren && axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h0 && S_AXI_WSTRB[0])
	      begin
	        slv_reg0[0]  <= S_AXI_WDATA[0];
	        tr_arm_pulse <= S_AXI_WDATA[1];
	      end
	  end
	end

	// ---------------- Instruction memory loader (Phase 4 Stage 1) ----------------
	// 0x30 IMEM_ADDR : word index (0..1023)
	// 0x34 IMEM_DATA : write -> imem[IMEM_ADDR] = data, IMEM_ADDR auto-increments. Accepted only while CTRL.rst_n = 0.
	// 0x38 IMEM_STATUS: [31] sticky "write rejected because CPU running" (clear by writing 0x38), [15:0] words written
	reg [9:0]  imem_idx;
	reg [15:0] imem_cnt;
	reg        imem_rej;
	wire       imem_sel_data = slv_reg_wren && axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'hD && S_AXI_WSTRB == 4'hF;
	wire       imem_we_w     = imem_sel_data && !slv_reg0[0];
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 ) begin
	    imem_idx <= 10'd0; imem_cnt <= 16'd0; imem_rej <= 1'b0;
	  end else begin
	    if (slv_reg_wren && axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'hC && S_AXI_WSTRB[0])
	      imem_idx <= S_AXI_WDATA[9:0];
	    else if (imem_we_w) begin
	      imem_idx <= imem_idx + 10'd1;
	      imem_cnt <= imem_cnt + 16'd1;
	    end
	    if (imem_sel_data && slv_reg0[0]) imem_rej <= 1'b1;
	    if (slv_reg_wren && axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'hE) begin
	      imem_rej <= 1'b0; imem_cnt <= 16'd0;
	    end
	  end
	end

	// Implement write response logic generation
	// The write response and response valid signals are asserted by the slave 
	// when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	// This marks the acceptance of address and indicates the status of 
	// write transaction.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_bvalid  <= 0;
	      axi_bresp   <= 2'b0;
	    end 
	  else
	    begin    
	      if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID)
	        begin
	          // indicates a valid write response is available
	          axi_bvalid <= 1'b1;
	          axi_bresp  <= 2'b0; // 'OKAY' response 
	        end                   // work error responses in future
	      else
	        begin
	          if (S_AXI_BREADY && axi_bvalid) 
	            //check if bready is asserted while bvalid is high) 
	            //(there is a possibility that bready is always asserted high)   
	            begin
	              axi_bvalid <= 1'b0; 
	            end  
	        end
	    end
	end   

	// Implement axi_arready generation
	// axi_arready is asserted for one S_AXI_ACLK clock cycle when
	// S_AXI_ARVALID is asserted. axi_awready is 
	// de-asserted when reset (active low) is asserted. 
	// The read address is also latched when S_AXI_ARVALID is 
	// asserted. axi_araddr is reset to zero on reset assertion.

	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_arready <= 1'b0;
	      axi_araddr  <= 32'b0;
	    end 
	  else
	    begin    
	      if (~axi_arready && S_AXI_ARVALID)
	        begin
	          // indicates that the slave has acceped the valid read address
	          axi_arready <= 1'b1;
	          // Read address latching
	          axi_araddr  <= S_AXI_ARADDR;
	        end
	      else
	        begin
	          axi_arready <= 1'b0;
	        end
	    end 
	end       

	// Implement axi_arvalid generation
	// axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
	// S_AXI_ARVALID and axi_arready are asserted. The slave registers 
	// data are available on the axi_rdata bus at this instance. The 
	// assertion of axi_rvalid marks the validity of read data on the 
	// bus and axi_rresp indicates the status of read transaction.axi_rvalid 
	// is deasserted on reset (active low). axi_rresp and axi_rdata are 
	// cleared to zero on reset (active low).  
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rvalid <= 0;
	      axi_rresp  <= 0;
	    end 
	  else
	    begin    
	      if (axi_arready && S_AXI_ARVALID && ~axi_rvalid)
	        begin
	          // Valid read data is available at the read data bus
	          axi_rvalid <= 1'b1;
	          axi_rresp  <= 2'b0; // 'OKAY' response
	        end   
	      else if (axi_rvalid && S_AXI_RREADY)
	        begin
	          // Read data is accepted by the master
	          axi_rvalid <= 1'b0;
	        end                
	    end
	end    

	// Implement memory mapped register select and read logic generation
	// Slave register read enable is asserted when valid address is available
	// and the slave is ready to accept the read address.
    assign slv_reg_rden = axi_arready & S_AXI_ARVALID & ~axi_rvalid;

	always @(*)
	begin
	      case ( axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
	        4'h0 : reg_data_out = {25'b0, wb_rd_out_wire, wb_we_out_wire, slv_reg0[0]};
	        4'h1 : reg_data_out = pc_out_wire;
	        4'h2 : reg_data_out = wb_data_out_wire;
	        4'h3 : reg_data_out = dmem_rdata_out_wire;
	        4'h4 : reg_data_out = {tr_full, 22'b0, tr_wptr};      // [31]=full, [8:0]=count
	        4'h5 : reg_data_out = {24'b0, tr_ridx};
	        4'h6 : reg_data_out = tr_pc_mem[tr_ridx];
	        4'h7 : reg_data_out = tr_wbd_mem[tr_ridx];
	        4'h8 : reg_data_out = {26'b0, tr_meta_mem[tr_ridx]};  // [5:1]=wb_rd, [0]=wb_we
        4'h9 : reg_data_out = {31'b0, illegal_out_wire};       // 0x24 sticky illegal flag
        4'hA : reg_data_out = illegal_pc_out_wire;             // 0x28 PC of first illegal instr
        4'hB : reg_data_out = 32'h0000_000F;                   // 0x2C feature bits: [0]=illegal regs, [1]=RV32M MUL, [2]=custom XDOTP16, [3]=PS-writable IMEM
        4'hC : reg_data_out = {22'b0, imem_idx};               // 0x30 IMEM_ADDR (word index)
        4'hD : reg_data_out = 32'h0;                           // 0x34 IMEM_DATA (write-only)
        4'hE : reg_data_out = {imem_rej, 15'b0, imem_cnt};     // 0x38 IMEM_STATUS: [31]=write rejected (CPU was running), [15:0]=words written
	        default : reg_data_out = 0;
	      endcase
	end

	// Output register or memory read data
	always @( posedge S_AXI_ACLK )
	begin
	  if ( S_AXI_ARESETN == 1'b0 )
	    begin
	      axi_rdata  <= 0;
	    end 
	  else
	    begin    
	      // When there is a valid read address (S_AXI_ARVALID) with 
	      // acceptance of read address by the slave (axi_arready), 
	      // output the read dada 
	      if (slv_reg_rden)
	        begin
	          axi_rdata <= reg_data_out;     // register read data
	        end   
	    end
	end    



    // ---------------- Trace buffer (256 cycles) ----------------
    // Usage: write CTRL=0x2 (reset + arm), then CTRL=0x1 (run).
    // Each clock with rst_n=1, until full: sample {pc, wb_data, wb_rd, wb_we}.
    always @( posedge S_AXI_ACLK )
    begin
      if ( S_AXI_ARESETN == 1'b0 ) begin
        tr_wptr <= 9'd0; tr_armed <= 1'b0;
      end else if (tr_arm_pulse) begin
        tr_wptr <= 9'd0; tr_armed <= 1'b1;
      end else if (tr_armed && slv_reg0[0] && !tr_full) begin
        tr_pc_mem  [tr_wptr[7:0]] <= pc_out_wire;
        tr_wbd_mem [tr_wptr[7:0]] <= wb_data_out_wire;
        tr_meta_mem[tr_wptr[7:0]] <= {wb_rd_out_wire, wb_we_out_wire};
        tr_wptr <= tr_wptr + 9'd1;
      end
    end

    always @( posedge S_AXI_ACLK )
    begin
      if ( S_AXI_ARESETN == 1'b0 ) tr_ridx <= 8'd0;
      else if (slv_reg_wren && axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 4'h5 && S_AXI_WSTRB[0])
        tr_ridx <= S_AXI_WDATA[7:0];
    end

	// Add user logic here
    rv32i_pipeline #(
        .IMEM_FILE(IMEM_FILE)
    ) rv32i_pipeline_inst (
        .clk(S_AXI_ACLK),
        .rst_n(slv_reg0[0]),
        .pc_out(pc_out_wire),
        .wb_data_out(wb_data_out_wire),
        .wb_rd_out(wb_rd_out_wire),
        .wb_we_out(wb_we_out_wire),
        .dmem_rdata_out(dmem_rdata_out_wire),
        .illegal_out(illegal_out_wire),
        .illegal_pc_out(illegal_pc_out_wire),
        .imem_we(imem_we_w),
        .imem_waddr(imem_idx),
        .imem_wdata(S_AXI_WDATA)
    );
    
	// User logic ends

	endmodule
