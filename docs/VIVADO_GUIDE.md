# Vivado 2022.2 使用指南（不需 iverilog / Python）

## 模擬（xsim）
1. 新增 Simulation Source：`src/*.v` 與 `sim/tb_*.v`，把 `sim/*.hex`、`sim/*.mem` 加為 Simulation Source 資料檔。
2. 或在 Windows 於 `sim/` 執行 `run_xsim.bat`（Linux 用 `run_xsim.sh`），先 call Vivado 的 `settings64`。
3. 11 個 testbench 都應印出 `ALL ... PASSED`：`tb_rv32i_pipeline`、`tb_jalr`、`tb_extra_branches`、`tb_load_use_branch`、`tb_illegal`、`tb_zbb_unit`、`tb_zbb_prog`（40 支程式，含 MUL 與 XDOTP16）、`tb_board_program`（上板用 136 字程式的整合驗證）、`tb_imem_default`（imem 內建程式完整性；bitstream 實際使用的就是這份內建程式）、`tb_bram_timing`（BRAM 同步讀取時序邊界）、`tb_axi_imem_load`（經 AXI 暫存器載入程式；需要 `axi/rv32i_pipelined_cpu_v1_0_S00_AXI.v`，run_xsim 已自動加入）。
4. `sim/zbb_*.mem/.hex` 已預先產生；只有要改測試內容時才需 `python3 tools/gen_tests.py`。

## 打包 IP / 上板
- IP 資料夾放在不含空白的路徑（例：`D:\\FPGA\\ip_repo_rv32i`），`component.xml` 檔案路徑用 `hdl/`。
- 頂層 `axi/rv32i_pipelined_cpu_v1_0.v` 的 `C_S00_AXI_ADDR_WIDTH` 必須是 **6**（13 個暫存器，到 0x38；位址仍在 6 位元範圍內，不必改寬度）。
- 更新 RTL 後：Re-Package IP → Block Design 內 Refresh IP / Upgrade → Generate Output Products（Global）→ 重新 Implementation → Bitstream。
- 上板：`design_1_wrapper.bit` 與 `design_1.hwh` 必須是**同一次 build** 的成對檔案、同檔名前綴，並重啟 Jupyter kernel。
- Notebook：`pynq_5-stage-pipeline-CPU_TEST/RV32I_CPU_Board_Test_v4.ipynb`，其 PROGRAM 與 `imem.v` 內建程式相同（`board_program.hex`）。

## XDOTP16 上板步驟（RTL 已更新，bitstream 需重做）
1. 把 `src/*.v` 與 `axi/*.v` 覆蓋到 IP 資料夾的 `hdl/`（或 Re-Package IP 重新加入），確認 `C_S00_AXI_ADDR_WIDTH = 6`。
2. Re-Package IP → BD 內 Upgrade IP → Generate Output Products（Global）→ Implementation → Bitstream；檢查 WNS ≥ 0、DSP48E2 數量（MUL 3 個 + XDOTP16 約 2 個）。
3. 把新的 `design_1_wrapper.bit` 與 `design_1.hwh` 一起複製到 PYNQ 的同一資料夾，重啟 Jupyter kernel。
4. 執行 `RV32I_CPU_Board_Test_v4.ipynb`：feature 暫存器（0x2C）應讀到 `0xF`（舊版 bitstream 為 `0x7`），PROGRAM 為 136 字、102 筆寫回、9 條非法指令（第一個 PC `0x1F4`，spin PC `0x21C`）。
