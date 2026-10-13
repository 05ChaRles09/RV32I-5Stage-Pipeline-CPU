# Vivado 2022.2 使用指南（不需 iverilog / Python）

## 模擬（xsim）
1. 新增 Simulation Source：`src/*.v` 與 `sim/tb_*.v`，把 `sim/*.hex`、`sim/*.mem` 加為 Simulation Source 資料檔。
2. 或在 Windows 於 `sim/` 執行 `run_xsim.bat`（Linux 用 `run_xsim.sh`），先 call Vivado 的 `settings64`。
3. 7 個 testbench 都應印出 `ALL ... PASSED`：`tb_rv32i_pipeline`、`tb_jalr`、`tb_extra_branches`、`tb_load_use_branch`、`tb_illegal`、`tb_zbb_unit`、`tb_zbb_prog`（38 支程式，含 MUL）。
4. `sim/zbb_*.mem/.hex` 已預先產生；只有要改測試內容時才需 `python3 tools/gen_tests.py`。

## 打包 IP / 上板
- IP 資料夾放在不含空白的路徑（例：`D:\\FPGA\\ip_repo_rv32i`），`component.xml` 檔案路徑用 `hdl/`。
- 頂層 `axi/rv32i_pipelined_cpu_v1_0.v` 的 `C_S00_AXI_ADDR_WIDTH` 必須是 **6**（10 個暫存器，到 0x2C）。
- 更新 RTL 後：Re-Package IP → Block Design 內 Refresh IP / Upgrade → Generate Output Products（Global）→ 重新 Implementation → Bitstream。
- 上板：`design_1_wrapper.bit` 與 `design_1.hwh` 必須是**同一次 build** 的成對檔案、同檔名前綴，並重啟 Jupyter kernel。
- Notebook：`pynq_5-stage-pipeline-CPU_TEST/RV32I_CPU_Board_Test_v2.ipynb`，其 PROGRAM 與 `imem.v` 內建程式相同（`board_program.hex`）。
