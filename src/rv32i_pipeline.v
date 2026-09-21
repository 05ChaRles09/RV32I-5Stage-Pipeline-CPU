// rv32i_pipeline.v 5-stage pipelined RV32I
// Stages: IF -> ID -> EX -> MEM -> WB
// Features: EX/MEM+MEM/WB forwarding (load-safe), load-use stall, branch/jump flush
// (branch resolved in EX stage). Keep the single-cycle rv32i_top.v as golden reference.
`timescale 1ns / 1ps

module rv32i_pipeline #(
    parameter IMEM_FILE = "program.hex"
)(
    input  wire        clk,
    input  wire        rst_n,
    // observable outputs (also prevent synthesis from pruning pipeline logic)
    output wire [31:0] pc_out,           // current program counter
    output wire [31:0] wb_data_out,      // writeback data (final)
    output wire [4:0]  wb_rd_out,        // writeback destination register
    output wire        wb_we_out,        // writeback enable (valid & reg_write)
    output wire [31:0] dmem_rdata_out    // data memory read data
);
    // ============================================================
    // IF stage
    // ============================================================
    reg  [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] if_instr;

    imem #(
        .ADDR_WIDTH(12),
        .MEM_FILE(IMEM_FILE)
    ) imem_inst (
        .addr  (pc),
        .instr (if_instr)
    );

    // ============================================================
    // IF/ID register
    // ============================================================
    wire        if_id_stall;
    wire        if_id_flush;
    wire        if_valid = 1'b1;

    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] id_instr;
    wire        id_valid;

    if_id_reg if_id_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall        (if_id_stall),
        .flush        (if_id_flush),
        .pc_in        (pc),
        .pc_plus4_in  (pc_plus4),
        .instr_in     (if_instr),
        .valid_in     (if_valid),
        .pc_out       (id_pc),
        .pc_plus4_out (id_pc_plus4),
        .instr_out    (id_instr),
        .valid_out    (id_valid)
    );

    // ============================================================
    // ID stage decode fields, read regs, generate imm & control
    // ============================================================
    wire [6:0] id_opcode  = id_instr[6:0];
    wire [4:0] id_rd      = id_instr[11:7];
    wire [2:0] id_funct3  = id_instr[14:12];
    wire [4:0] id_rs1     = id_instr[19:15];
    wire [4:0] id_rs2     = id_instr[24:20];
    wire [6:0] id_funct7  = id_instr[31:25];

    wire        id_reg_write, id_mem_read, id_mem_write, id_branch,
               id_jump, id_jalr, id_alu_src, id_mem_to_reg;
    wire [3:0]  id_alu_control;
    wire        id_uses_rs1, id_uses_rs2;
    wire [1:0]  id_wb_sel, id_alu_a_sel;

    control_unit ctrl_inst (
        .opcode      (id_opcode),
        .funct3      (id_funct3),
        .funct7      (id_funct7),
        .reg_write   (id_reg_write),
        .mem_read    (id_mem_read),
        .mem_write   (id_mem_write),
        .branch      (id_branch),
        .jump        (id_jump),
        .jalr        (id_jalr),
        .alu_src     (id_alu_src),
        .mem_to_reg  (id_mem_to_reg),
        .alu_control (id_alu_control),
        .uses_rs1     (id_uses_rs1),
        .uses_rs2     (id_uses_rs2),
        .wb_sel       (id_wb_sel),
        .alu_a_sel    (id_alu_a_sel)
    );

    wire [31:0] id_imm;
    imm_gen imm_gen_inst (
        .instr (id_instr),
        .imm   (id_imm)
    );

    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;

    // writeback ports (driven from MEM/WB)
    wire        wb_reg_write_eff;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    regfile regfile_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .we       (wb_reg_write_eff),
        .rs1_addr (id_rs1),
        .rs2_addr (id_rs2),
        .rd_addr  (wb_rd),
        .rd_data  (wb_data),
        .rs1_data (id_rs1_data),
        .rs2_data (id_rs2_data)
    );

    // ============================================================
    // ID/EX register
    // ============================================================
    wire        id_ex_flush;
    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus4;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_imm;
    wire [4:0]  ex_rs1, ex_rs2, ex_rd;
    wire [2:0]  ex_funct3;
    wire [3:0]  ex_alu_control;
    wire        ex_reg_write, ex_mem_read, ex_mem_write, ex_mem_to_reg,
                ex_alu_src, ex_branch, ex_jump, ex_jalr, ex_valid,
                ex_uses_rs1, ex_uses_rs2;
    wire [1:0]  ex_wb_sel, ex_alu_a_sel;

    id_ex_reg id_ex_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (id_ex_flush),
        .pc_in           (id_pc),
        .pc_plus4_in     (id_pc_plus4),
        .rs1_data_in     (id_rs1_data),
        .rs2_data_in     (id_rs2_data),
        .imm_in          (id_imm),
        .rs1_in          (id_rs1),
        .rs2_in          (id_rs2),
        .rd_in           (id_rd),
        .funct3_in       (id_funct3),
        .alu_control_in  (id_alu_control),
        .reg_write_in    (id_reg_write),
        .mem_read_in     (id_mem_read),
        .mem_write_in    (id_mem_write),
        .mem_to_reg_in   (id_mem_to_reg),
        .alu_src_in      (id_alu_src),
        .branch_in       (id_branch),
        .jump_in         (id_jump),
        .jalr_in         (id_jalr),
        .valid_in        (id_valid),
        .uses_rs1_in     (id_uses_rs1),
        .uses_rs2_in     (id_uses_rs2),
        .wb_sel_in        (id_wb_sel),
        .alu_a_sel_in     (id_alu_a_sel),
        .pc_out          (ex_pc),
        .pc_plus4_out    (ex_pc_plus4),
        .rs1_data_out    (ex_rs1_data),
        .rs2_data_out    (ex_rs2_data),
        .imm_out         (ex_imm),
        .rs1_out         (ex_rs1),
        .rs2_out         (ex_rs2),
        .rd_out          (ex_rd),
        .funct3_out      (ex_funct3),
        .alu_control_out (ex_alu_control),
        .reg_write_out   (ex_reg_write),
        .mem_read_out    (ex_mem_read),
        .mem_write_out   (ex_mem_write),
        .mem_to_reg_out  (ex_mem_to_reg),
        .alu_src_out     (ex_alu_src),
        .branch_out      (ex_branch),
        .jump_out        (ex_jump),
        .jalr_out        (ex_jalr),
        .valid_out       (ex_valid),
        .uses_rs1_out    (ex_uses_rs1),
        .uses_rs2_out    (ex_uses_rs2),
        .wb_sel_out      (ex_wb_sel),
        .alu_a_sel_out   (ex_alu_a_sel)
    );

    // ============================================================
    // EX stage  forwarding muxes + ALU + branch resolution
    // ============================================================
    // forward-declare EX/MEM and MEM/WB outputs (driven by the register
    // instances below, consumed here by the forwarding muxes) so there is
    // no implicit 1-bit wire / redeclaration mismatch.
    wire [4:0]  ex_mem_rd;
    wire        ex_mem_reg_write, ex_mem_mem_read, ex_mem_valid;
    wire [4:0]  mem_wb_rd;
    wire        mem_wb_reg_write, mem_wb_valid;

    wire [1:0] forward_a, forward_b;
    wire [31:0] ex_mem_alu_result_wb;  // = ex/mem alu result (or load data, see below)
    wire [31:0] mem_wb_wb_data;

    forwarding_unit fwd_inst (
        .id_ex_rs1        (ex_rs1),
        .id_ex_rs2        (ex_rs2),
        .id_ex_uses_rs1   (ex_uses_rs1),
        .id_ex_uses_rs2   (ex_uses_rs2),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_reg_write (ex_mem_reg_write),
        .ex_mem_mem_read  (ex_mem_mem_read),
        .ex_mem_valid     (ex_mem_valid),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_reg_write (mem_wb_reg_write),
        .mem_wb_valid     (mem_wb_valid),
        .forward_a        (forward_a),
        .forward_b        (forward_b)
    );

    // forwarded operands
    wire [31:0] fwd_rs1 =
        (forward_a == 2'b10) ? ex_mem_alu_result_wb :
        (forward_a == 2'b01) ? mem_wb_wb_data :
                               ex_rs1_data;

    wire [31:0] fwd_rs2 =
        (forward_b == 2'b10) ? ex_mem_alu_result_wb :
        (forward_b == 2'b01) ? mem_wb_wb_data :
                               ex_rs2_data;

    // store data forwarded too (sw of just-produced value)
    wire [31:0] ex_store_data = fwd_rs2;

    // ALU input A selection (rs1 fwd / pc / zero for LUI)
    wire [31:0] alu_a =
        (ex_alu_a_sel == 2'b01) ? ex_pc :
        (ex_alu_a_sel == 2'b10) ? 32'b0 :
                                 fwd_rs1;

    wire [31:0] alu_b = ex_alu_src ? ex_imm : fwd_rs2;

    wire [31:0] ex_alu_result;
    wire        ex_alu_zero;

    alu alu_inst (
        .A           (alu_a),
        .B           (alu_b),
        .ALU_Control (ex_alu_control),
        .Result      (ex_alu_result),
        .Zero        (ex_alu_zero)
    );

    // branch resolution (uses forwarded operands)
    wire        ex_taken;
    wire [31:0] ex_target;

    branch_unit branch_inst (
        .pc        (ex_pc),
        .rs1_value (fwd_rs1),
        .rs2_value (fwd_rs2),
        .imm       (ex_imm),
        .funct3    (ex_funct3),
        .branch    (ex_branch),
        .jump      (ex_jump),
        .jalr      (ex_jalr),
        .valid     (ex_valid),
        .taken     (ex_taken),
        .target    (ex_target)
    );

    // ============================================================
    // EX/MEM register
    // ============================================================
    wire [31:0] ex_mem_alu_result;
    wire [31:0] ex_mem_store_data;
    wire [31:0] ex_mem_branch_target;
    wire [31:0] ex_mem_pc_plus4;
    wire [31:0] ex_mem_imm;
    wire        ex_mem_branch_taken, ex_mem_mem_write, ex_mem_mem_to_reg, ex_mem_jump;
    wire [1:0]  ex_mem_wb_sel;
    wire [2:0]  ex_mem_funct3;

    ex_mem_reg ex_mem_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .alu_result_in    (ex_alu_result),
        .store_data_in    (ex_store_data),
        .branch_target_in (ex_target),
        .pc_plus4_in      (ex_pc_plus4),
        .imm_in           (ex_imm),
        .branch_taken_in  (ex_taken),
        .reg_write_in     (ex_reg_write),
        .mem_read_in      (ex_mem_read),
        .mem_write_in     (ex_mem_write),
        .mem_to_reg_in    (ex_mem_to_reg),
        .jump_in           (ex_jump),
        .valid_in          (ex_valid),
        .wb_sel_in         (ex_wb_sel),
        .rd_in             (ex_rd),
        .funct3_in         (ex_funct3),
        .alu_result_out    (ex_mem_alu_result),
        .store_data_out    (ex_mem_store_data),
        .branch_target_out (ex_mem_branch_target),
        .pc_plus4_out      (ex_mem_pc_plus4),
        .imm_out           (ex_mem_imm),
        .branch_taken_out  (ex_mem_branch_taken),
        .reg_write_out     (ex_mem_reg_write),
        .mem_read_out      (ex_mem_mem_read),
        .mem_write_out     (ex_mem_mem_write),
        .mem_to_reg_out    (ex_mem_mem_to_reg),
        .jump_out           (ex_mem_jump),
        .valid_out          (ex_mem_valid),
        .wb_sel_out         (ex_mem_wb_sel),
        .rd_out             (ex_mem_rd),
        .funct3_out         (ex_mem_funct3)
    );

    // forwarding value from EX/MEM stage (ALU result; load data comes from MEM next)
    assign ex_mem_alu_result_wb = ex_mem_alu_result;

    // ============================================================
    // MEM stage  data memory
    // ============================================================
    wire [31:0] dmem_rdata;
    wire        mem_write_eff = ex_mem_valid && ex_mem_mem_write;

    dmem #(
        .ADDR_WIDTH(12)
    ) dmem_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .mem_read  (ex_mem_mem_read),
        .mem_write (mem_write_eff),
        .addr      (ex_mem_alu_result),
        .wdata     (ex_mem_store_data),
        .rdata     (dmem_rdata)
    );

    // ============================================================
    // MEM/WB register
    // ============================================================
    wire [31:0] mem_wb_alu_result;
    wire [31:0] mem_wb_mem_rdata;
    wire [31:0] mem_wb_pc_plus4;
    wire [31:0] mem_wb_imm;
    wire        mem_wb_mem_to_reg, mem_wb_jump;
    wire [1:0]  mem_wb_wb_sel;
    wire [2:0]  mem_wb_funct3;

    mem_wb_reg mem_wb_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .alu_result_in   (ex_mem_alu_result),
        .mem_rdata_in    (dmem_rdata),
        .pc_plus4_in     (ex_mem_pc_plus4),
        .imm_in          (ex_mem_imm),
        .reg_write_in    (ex_mem_reg_write),
        .mem_to_reg_in  (ex_mem_mem_to_reg),
        .jump_in          (ex_mem_jump),
        .valid_in         (ex_mem_valid),
        .wb_sel_in       (ex_mem_wb_sel),
        .rd_in           (ex_mem_rd),
        .funct3_in       (ex_mem_funct3),
        .alu_result_out   (mem_wb_alu_result),
        .mem_rdata_out    (mem_wb_mem_rdata),
        .pc_plus4_out     (mem_wb_pc_plus4),
        .imm_out          (mem_wb_imm),
        .reg_write_out    (mem_wb_reg_write),
        .mem_to_reg_out  (mem_wb_mem_to_reg),
        .jump_out         (mem_wb_jump),
        .valid_out        (mem_wb_valid),
        .wb_sel_out       (mem_wb_wb_sel),
        .rd_out           (mem_wb_rd),
        .funct3_out       (mem_wb_funct3)
    );

    // ============================================================
    // WB stage writeback data selection
    // ============================================================
    // wb_sel: 00=ALU, 01=MEM, 10=PC+4
    assign wb_data =
        (mem_wb_wb_sel == 2'b01) ? mem_wb_mem_rdata :
        (mem_wb_wb_sel == 2'b10) ? mem_wb_pc_plus4 :
                                   mem_wb_alu_result;

    assign wb_reg_write_eff = mem_wb_valid && mem_wb_reg_write;
    assign wb_rd            = mem_wb_rd;

    // MEM/WB forwarding value (final writeback data)
    assign mem_wb_wb_data = wb_data;

    // ============================================================
    // Hazard + flush control
    // ============================================================
    // load-use stall
    wire load_use_stall;
    hazard_unit hazard_inst (
        .id_ex_mem_read   (ex_mem_read),
        .id_ex_rd          (ex_rd),
        .id_ex_valid       (ex_valid),
        .if_id_rs1         (id_rs1),
        .if_id_rs2         (id_rs2),
        .if_id_uses_rs1   (id_uses_rs1),
        .if_id_uses_rs2   (id_uses_rs2),
        .if_id_valid       (id_valid),
        .stall             (load_use_stall)
    );
    assign if_id_stall = load_use_stall;

    // stall -> also bubble ID/EX so the stalled instr isn't re-launched into EX
    // branch/jump flush (resolved in EX)
    wire flush = ex_valid && (ex_taken || ex_jump);
    wire [31:0] redirect_pc = ex_target;

    assign if_id_flush = flush;
    assign id_ex_flush = flush | load_use_stall;

    // ============================================================
    // PC update  (priority: reset > flush > stall > normal)
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h00000000;
        end else if (flush) begin
            pc <= redirect_pc;
        end else if (!if_id_stall) begin
            pc <= pc_plus4;
        end
        // if stall: hold pc
    end

    // ============================================================
    // observable outputs tap real pipeline state so synthesis keeps it
    // ============================================================
    assign pc_out         = pc;
    assign wb_data_out    = wb_data;
    assign wb_rd_out      = wb_rd;
    assign wb_we_out      = wb_reg_write_eff;
    assign dmem_rdata_out = dmem_rdata;
endmodule
