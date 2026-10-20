# RV32I 5-Stage Pipeline CPU on PYNQ-ZU

本專案以 Verilog/SystemVerilog 實作基於 **RISC-V RV32I ISA** 的 **五級管線 CPU**，並擴充 **Zbb**、**RV32M `MUL`** 與自訂指令 **`XDOTP16`**，目標平台為 **PYNQ-ZU**。CPU 已封裝為 AXI4-Lite IP，可透過 PYNQ / Jupyter 控制並讀取除錯資訊，且已在 PYNQ-ZU 實板上執行內建測試程式。

> **最新實板測試結果：40/40 PASS（Notebook v3）。** 測試包含 reset/run、重複執行、256 筆 trace buffer 逐 cycle 與 ISA 黃金模型比對、Zbb／`MUL`／`XDOTP16` 逐指令結果驗證，以及非法指令偵測。此結果代表目前測試程式與測試情境通過，不代表所有指令與所有邊界情況均已完整驗證（見〈驗證範圍與限制〉）。

## Architecture

```text
PC
 ↓
IF  ── Instruction Fetch
 ↓
IF/ID
 ↓
ID  ── Instruction Decode / Register Read
 ↓
ID/EX
 ↓
EX  ── ALU / Branch / Address Calculation
 ↓
EX/MEM
 ↓
MEM ── Data Memory Access
 ↓
MEM/WB
 ↓
WB  ── Write Back
 ↓
Register File
```

### Five Pipeline Stages

- **IF（取指）**：依照 PC 從 Instruction Memory 取得指令，正常情況下下一個 PC 為 PC + 4。
- **ID（解碼）**：解碼 opcode、funct3、funct7，讀取 Register File，產生 immediate 與控制訊號；不認得的指令標記為 illegal。
- **EX（執行）**：執行 ALU（含 Zbb、`MUL`、`XDOTP16`）、計算 Load/Store 位址，以及 Branch/Jump target。
- **MEM（記憶體存取）**：執行 Data Memory 的 Load / Store。
- **WB（寫回）**：將 ALU result 或 Memory read data 寫回目的暫存器。

## Main Components

- Program Counter（PC）
- Instruction Memory（IMEM，內建測試程式）
- Data Memory（DMEM）
- Register File（32 × 32-bit，`x0` 固定為 0）
- Control Unit（含非法指令偵測）
- Immediate Generator
- ALU / ALU Control（含 `zbb_unit`）
- IF/ID、ID/EX、EX/MEM、MEM/WB Pipeline Registers
- Hazard Detection Unit
- Forwarding Unit
- Branch / Jump control
- Stall / Flush logic
- AXI4-Lite CPU control/debug wrapper
- Trace buffer（256 筆）
- Illegal-instruction 回報（sticky 旗標與第一個非法 PC）

> PC 目前直接實作於 CPU pipeline RTL 中，不需要另外拆成獨立的 `pc.v` module。

## Pipeline Hazard Handling

### Data Hazard / Forwarding

當前後指令存在資料相依時，Forwarding Unit 可將較新 pipeline stage 的結果前推至後續運算，減少不必要的等待。

```text
EX/MEM ──┐
         ├──→ Forwarding Unit ──→ ALU
MEM/WB ──┘
```

### Load-Use Hazard

例如：

```asm
lw  x5, 0(x1)
add x6, x5, x2
```

當 Load 資料尚未準備完成時，Hazard Detection Unit 會產生 stall / bubble。測試程式涵蓋 load 後接 ALU、`MUL`、`XDOTP16` 與分支的相依情境。

### Control Hazard

Branch / Jump 改變 PC 時，CPU 會重新導向 PC，並 flush 不再有效的 pipeline instruction，避免錯誤路徑指令產生不正確的架構狀態。測試程式特別在「被跳過的 shadow 指令」放入 `MUL`／`XDOTP16`，確認被 flush 的指令不會提交。

## Supported ISA

### RV32I

- R-Type arithmetic / logic
- I-Type arithmetic / immediate
- `LW` / `SW`
- Branch
- `JAL` / `JALR`
- `LUI` / `AUIPC`

### Zbb（17 個運算 + `rori`）

`ANDN`、`ORN`、`XNOR`、`MIN`、`MINU`、`MAX`、`MAXU`、`ROL`、`ROR`、`RORI`、`CLZ`、`CTZ`、`CPOP`、`SEXT.B`、`SEXT.H`、`ZEXT.H`、`REV8`、`ORC.B`

### RV32M（僅 `MUL`）

- `MUL`：單週期，取 32×32 乘積的低 32 位元，合成後使用 3 個 DSP48E2（MUL 版 Vivado 結果；加上 `XDOTP16` 後整體為 5 個）。
- `MULH` / `MULHSU` / `MULHU` / `DIV*` / `REM*` 尚未實作，會被視為 **illegal**。

### 自訂指令 `XDOTP16`

| 項目 | 內容 |
|---|---|
| Opcode | custom-0（`0001011`） |
| 格式 | R-type，`funct7 = 0000000`、`funct3 = 000` |
| 運算 | `rd = rs1[15:0] × rs2[15:0] + rs1[31:16] × rs2[31:16]` |
| 資料型態 | 有號 int16 × 2 內積，結果為 32 位元（超出範圍時回繞） |
| 延遲 | 單週期（EX 級完成） |
| 其他 `funct7` / `funct3` | 視為 illegal |

> 累加版（`rd += 內積`）需第三個讀取埠並修改 forwarding / hazard，目前未實作；可用 `xdotp16 t, a, b` 加 `add acc, acc, t` 兩條指令達成相同結果。

### Illegal Instruction 行為

- 不認得的指令（未定義的 opcode／funct 組合、`FENCE`、`ECALL`、全零字、`LB`/`SB` 等）視為 NOP，不寫 register、不寫 memory。
- 第一次遇到時設起 sticky 旗標，並記錄第一個非法指令的 PC；reset 後清除。

## PYNQ-ZU Architecture

目標 SoC 架構如下。PS 端執行 ARM/Linux/PYNQ，PL 端實作 RISC-V CPU 與控制／除錯介面。

```text
             Processing System (PS)
        ┌─────────────────────────┐
        │ ARM Processor           │
        │ Linux / PYNQ / Jupyter  │
        └────────────┬────────────┘
                     │
                 AXI4-Lite
                     │
        ┌────────────▼────────────┐
        │ Programmable Logic (PL) │
        │                         │
        │ CPU AXI4-Lite Wrapper   │
        │          │              │
        │ RV32I 5-Stage CPU        │
        │ ├─ Instruction Memory   │
        │ ├─ Data Memory          │
        │ ├─ Trace Buffer         │
        │ └─ Illegal Report       │
        └─────────────────────────┘
```

Notebook 使用的 bitstream 路徑與位址為：

```python
BIT  = "/home/xilinx/jupyter_notebooks/design_1_wrapper.bit"
BASE = 0x80000000
SIZE = 0x10000
```

請確認 `.bit` 與同名 `.hwh` 為同一次 Vivado 匯出的配對檔案。替換 bitstream 後，請先在 Jupyter 選擇 **Kernel → Restart**，再重新載入 Overlay，以免使用舊的 Overlay／metadata 狀態。

## AXI-Lite Status

**AXI4-Lite 控制／除錯介面已通過 Notebook v3 的 PYNQ-ZU 實板測試。** 測試程式可透過 memory-mapped register 控制 CPU reset/run，讀取 PC、write-back 資料與 DMEM readback，讀取 256 筆 trace buffer，並讀取非法指令回報與功能旗標。

> **目前限制：** CPU 的 Instruction Memory 仍由硬體設計／內建測試程式提供（`src/imem.v` 內寫死的 136 字程式）。現有 Notebook 並未證明可由 Python 將任意程式寫入 CPU 的 Instruction Memory。透過 AXI4-Lite 控制 CPU 與讀取除錯資訊，和透過 PS 任意載入指令程式，是兩項不同的功能。

### AXI4-Lite Register Map

位址相對於 CPU IP base address `0x80000000`（AXI 位址寬度 6 bit，`C_S00_AXI_ADDR_WIDTH = 6`）。若更換 RTL／bitstream，請重新確認暫存器映射。

| Offset | 名稱 | 用途 |
|---:|---|---|
| `0x00` | `CTRL` | 寫入 `0`：assert reset；寫入 `1`：解除 reset 並執行；測試 trace 時先寫入 `2` 作為 arm/clear，再寫入 `1` 執行。讀回 `{wb_rd, wb_we, rst_n}` |
| `0x04` | `PC` | 讀取目前 Program Counter |
| `0x08` | `WBD` | 讀取 write-back data 取樣值 |
| `0x0C` | `DMEM` | 讀取 Data Memory readback 取樣值 |
| `0x10` | `T_STATUS` | Trace 狀態；bit 31 表示支援 trace，`[8:0]` 回報擷取筆數 |
| `0x14` | `T_IDX` | 寫入欲選取的 trace entry index |
| `0x18` | `T_PC` | 讀取所選 trace entry 的 PC |
| `0x1C` | `T_WB` | 讀取所選 trace entry 的 write-back data |
| `0x20` | `T_META` | 讀取 trace metadata；以 `(meta >> 1) & 31` 取得 `wb_rd`，以 `meta & 1` 取得 `wb_we` |
| `0x24` | `ILLEGAL` | 非法指令 sticky flag（bit 0）；reset 後清除 |
| `0x28` | `ILLEGAL_PC` | 第一個非法指令的 PC |
| `0x2C` | `FEATURE` | 功能旗標：bit 0 = illegal 暫存器、bit 1 = RV32M `MUL`、bit 2 = 自訂 `XDOTP16`、bit 3 = （IP 1.4 的 AXI 載入 IMEM，IP 1.6 已移除）、bit 4 = 外部 BRAM IMEM/DMEM（目前讀值 `0x17`） |

測試輸出中的 trace status 為 `0x80000100`，代表已啟用 trace，且擷取到 256 筆紀錄。

## Project Structure

```text
.
├── src/                  CPU RTL（pipeline、ALU、zbb_unit、control_unit、imem、dmem …）
├── axi/                  AXI4-Lite IP 頂層與 S00_AXI wrapper（含 trace / illegal 暫存器、IMEM/DMEM 的 BRAM master 介面）
├── bram_init/            Block Memory Generator 初始化檔（COE，由 tools/gen_coe.py 產生）
├── sim/                  Testbench、測試資料（.hex / .mem）、run_xsim.bat / run_xsim.sh
├── tools/                Python 黃金模型與測試資料產生器、riscv-arch-test 執行器（選用，Vivado 流程不需要）
├── arch_test/            riscv-arch-test 目標環境（target/）與執行結果摘要（results/summary.json）
├── pynq_5-stage-pipeline-CPU_TEST/
│                         板上測試 Notebook、.bit / .hwh、測試報告 JSON
├── docs/                 Vivado 使用指南、Stage 2b 操作與踩雷、IP 打包踩雷紀錄、開發紀錄與 Bug 整理、專題成果報告素材（PROJECT_REPORT_MATERIALS.md）、XDOTP16 效益量測（XDOTP16_BENCHMARK.md）
│   └── vivado_reports/   各 IP 版本的 util / timing / power 原始報告（ip1.5、ip1.6）
├── constrs/              constraints.xdc（整合設計：不需額外約束，內含說明）、constraints_standalone.xdc（單獨合成 CPU 核心用）
└── README.md
```

- 使用 Vivado 2022.2 即可模擬（xsim）與打包 IP，**不需要 iverilog 或 Python**；`sim/` 內的測試資料已預先產生。
- 實板測試請連同對應的 `.bit`／`.hwh` 與 `cpu_test_report` 一併保存，讓結果可以重現。
- 詳細步驟見 [`docs/VIVADO_GUIDE.md`](docs/VIVADO_GUIDE.md)，IP 打包常見問題見 [`docs/IP_PACKAGING_LESSONS.md`](docs/IP_PACKAGING_LESSONS.md)。

## Verification Status

### 模擬（11 個 testbench；內部記憶體模式 10 個 + 系統層級 1 個）

在 `sim/` 執行 `run_xsim.bat`（Windows）或 `run_xsim.sh`（Linux），需先載入 Vivado 環境。

| Testbench | 驗證內容 |
|---|---|
| `tb_rv32i_pipeline` | 基本 RV32I 程式 |
| `tb_jalr` | `JALR` |
| `tb_extra_branches` | 各種 Branch、`AUIPC` |
| `tb_load_use_branch` | load-use 並緊接 branch |
| `tb_illegal` | 非法指令為 NOP、不得寫 register/memory、旗標與第一個 PC |
| `tb_zbb_unit` | Zbb 各運算單元：邊界值 + 隨機，共約 1.4 萬組向量 |
| `tb_zbb_prog` | 40 支程式（directed + 30 支隨機），涵蓋 Zbb、`MUL`、`XDOTP16`、forwarding、load-use、branch flush，與 Python 黃金模型比對最終暫存器與記憶體 |
| `tb_board_program` | 上板用 136 字程式的整合驗證（暫存器、DMEM、第一個非法 PC、spin 前所需 cycle） |
| `tb_imem_default` | `imem.v` 內建（寫死）程式完整性，也就是合成進 bitstream 的內容 |
| `tb_bram_timing` | BRAM 同步讀取的時序邊界：store→load 緊接、load-use stall 時取指保持、load 結果當 store 資料、load-use 後接 taken branch、jal 重導向、迴圈 RAW（預期值由 Python 黃金模型產生） |
| `tb_axi_bram_system` | Stage 2b 系統層級：CPU IP（`EXTERNAL_MEM=1`）+ 兩個 BMG 行為模型（`sim/bmg_tdp_model.v`，port A 當 PS）。COE 式初始化程式執行、PS 讀回 IMEM / DMEM、PS 清空 DMEM 並載入另一支程式後執行、執行中 PS 讀 DMEM 不影響 CPU（只用於模擬，不要加進 IP） |

另有效益量測 `tb_bench`（`sim/run_bench.py`）：3 個 kernel x 4 種實作共 12 支程式（含重複版），DMEM 結果與黃金模型逐字一致，並量測週期數，結果見 [`docs/XDOTP16_BENCHMARK.md`](docs/XDOTP16_BENCHMARK.md)。

測試有效性以突變測試確認：故意把 `MUL` 改成加法、把 `XDOTP16` 改成減法或接錯半字，以及重現 `imem.v` 填充迴圈的舊錯誤，對應測試都會失敗。

### PYNQ-ZU 實板測試結果（Notebook v3：40/40 PASS）

測試程式 136 字，產生 102 筆 write-back、9 條非法指令（第一個非法 PC `0x1F4`），spin 迴圈位於 `0x21C`。

| 測試 | 驗證內容 | 結果 |
|---|---|---|
| T1 | Assert reset，確認 PC 回到 `0x0` | PASS |
| T2a | Run 控制成功，`CTRL[0] = 1` | PASS |
| T2b | PC 停在預期 spin-loop 區域（`0x21C` 起） | PASS |
| T3a / T3b | 再次 reset 後 PC 回 `0x0`；重複 reset/run 五次結果一致 | PASS |
| T4a | Trace buffer 填入 256 筆紀錄 | PASS |
| T4b | Write-back 序列與 ISA 黃金模型一致（102 筆） | PASS |
| T4c–T4e | 第 0 筆 PC 為 `0x0`；PC 皆 4-byte 對齊且在程式範圍內；最後 16 cycle 在 spin-loop 內 | PASS |
| T4f | 由 trace 重建的 `x1`–`x31` 與黃金模型一致 | PASS |
| T5 | 再次執行後，逐 cycle trace 完全一致 | PASS |
| T6a / T6b | 執行後 reset 回 `0x0`；reset 後重跑 trace 相同 | PASS |
| T7 | Zbb 18 項、`MUL`（11 筆）、`XDOTP16`（10 筆）逐筆硬體結果與黃金模型一致，共 20 項 | PASS |
| T8a–T8f | illegal 旗標：reset 為 0、執行後設起（sticky）、第一個 PC = `0x1F4`、不被後續非法指令覆蓋、reset 後清除、重跑再次回報 | PASS |
| **總計** | | **40/40 PASS** |

測試報告：[`pynq_5-stage-pipeline-CPU_TEST/cpu_test_report_v3_xdotp16_40of40.json`](pynq_5-stage-pipeline-CPU_TEST/cpu_test_report_v3_xdotp16_40of40.json)。較早期的版本紀錄：基本 + trace 16/16 → Zbb 32/32 → 加 illegal 38/38 → 加 `MUL` 39/39（[`cpu_test_report_v2_mul_39of39.json`](pynq_5-stage-pipeline-CPU_TEST/cpu_test_report_v2_mul_39of39.json)）。

### PYNQ-ZU 實板測試結果（Notebook v5，IP 1.6：52/52 PASS）

Stage 2b 的 bitstream（IMEM / DMEM 為 BMG，PS 經 AXI BRAM Controller 存取）。T1~T8 與前一版相同（40 項）；L1~L9 為新增，驗證 PS 對 BRAM 的存取：

| 測試 | 驗證內容 | 結果 |
|---|---|---|
| T1~T8 | 與 Notebook v3 相同：reset／run、trace、Zbb 18 項、`MUL`、`XDOTP16`、illegal 旗標 | 40/40 PASS |
| L1 | `FEATURE` = `0x17`（bit 4：外部 BRAM） | PASS |
| L2a / L2b | PS 讀回 IMEM：前 136 字 = 板測程式（COE 初始化正確）、其餘為 NOP | PASS |
| L3a / L3b | PS 寫入 DMEM 整塊 1024 字圖樣後讀回一致；清空後全為 0 | PASS |
| L4 | PS 載入小程式（`add`/`sw`/`lw`/`mul`/`xdotp16`）：寫回序列與整塊 DMEM 皆與黃金模型一致 | PASS |
| L5 | 再載入另一支程式（`sub`）：`DMEM[0]` = 41 | PASS |
| L6a / L6b | 載回 136 字板測程式：102 筆寫回、整塊 DMEM 與黃金模型一致 | PASS |
| L7 | 批次載入 `zbb_prog.hex` 的 40 支程式：8,470 筆寫回、1,529 個 DMEM 字與黃金模型一致 | PASS |
| L8 | CPU 執行中 PS 反覆讀 DMEM，CPU 結果不受影響 | PASS |
| L9 | 還原板測程式後 PC 停在 spin 迴圈 | PASS |
| **總計** | | **52/52 PASS** |

測試報告：[`pynq_5-stage-pipeline-CPU_TEST/cpu_test_report_v5_ip1.6_52of52.json`](pynq_5-stage-pipeline-CPU_TEST/cpu_test_report_v5_ip1.6_52of52.json)。本結果是以 Notebook v5 原樣（`load_program` 不補寫 word 0）、在 `imem_bmg` 的 Enable Port Type 為 Use ENA Pin 的 bitstream 上取得；先前 Enable Port Type 設成 Always Enabled 時，L4~L8 會因 IMEM word 0 被誤寫而失敗（開發紀錄 Bug 11）。

### Vivado 時序與資源

Vivado 2022.2，裝置 `xczu5eg-sfvc784-1-i`（PYNQ-ZU），Implementation 完成後（Routed）的結果。

| 版本 | WNS | WHS | DSP48E2 |
|---|---:|---:|---:|
| 含 `MUL`（不含 `XDOTP16`） | +1.995 ns | +0.010 ns | 3 |
| 含 `XDOTP16`（Notebook v3 使用的 build） | +1.977 ns | +0.001 ns | 5 |

含 `XDOTP16` 版本（整個 `design_1_wrapper`，含 PS 與 AXI 周邊）的資源使用量：

| 資源 | 使用量 | 使用率 |
|---|---:|---:|
| CLB LUTs | 3,877 | 3.31 % |
| 　LUT as Logic | 2,947 | 2.52 % |
| 　LUT as Memory（Distributed RAM 864 + Shift Register 66） | 930 | 1.61 % |
| CLB Registers（Flip-Flop） | 2,174 | 0.93 % |
| DSP48E2 | 5 | 0.40 % |
| Block RAM / URAM | 0 | 0.00 % |
| CARRY8 | 46 | 0.31 % |

- DSP48E2 共 5 個：`MUL` 3 個 + `XDOTP16` 2 個。
- 以上數字是 **Stage 1（LUTRAM、組合讀取）** 的量測結果：Instruction / Data Memory 與 Register File 以 Distributed RAM 實作，不使用 Block RAM。Stage 2a 之後的重新量測結果見下一小節。
- 所有時序皆已滿足，但 hold slack 僅 +0.001 ns，不同 Implementation run 之間可能浮動。
- 設計時脈為 PL clock 100 MHz（10 ns 約束）。以 setup slack +1.977 ns 粗估，關鍵路徑約 8 ns（約 125 MHz 上限）；此為依 slack 的估算。另外，PYNQ-ZU 板上 PL0 的實際來源是 IOPLL（約 1500 MHz ÷ 8 = 187.5 MHz），與 Block Design 設定的 100 MHz 不同；XDOTP16 效益量測的第一次實板測試因此是在 187.498 MHz 下全部通過，超出 100 MHz 約束的簽核範圍，僅代表此板此溫度下可運作，不是時序保證。Notebook v5 與 Benchmark 現在載入後會先把 PL 時脈設為 100 MHz，並已在 100 MHz 重跑通過（v5 52/52、Benchmark 24/24）（見 [`docs/XDOTP16_BENCHMARK.md`](docs/XDOTP16_BENCHMARK.md) 3b 節）。

#### Stage 2a（IP 1.5）：IMEM/DMEM 改為 BRAM 同步讀取後重新量測

同一裝置、同樣 100 MHz 約束、Routed 結果。Vivado 將 IMEM、DMEM 各推論為 1 個 RAMB36E2。

| 項目 | Stage 1（IP 1.4，LUTRAM） | Stage 2a（IP 1.5，BRAM） | 變化 |
|---|---:|---:|---:|
| CLB LUTs | 3,877 | 3,286 | −591（−15 %） |
| LUT as Distributed RAM | 864 | 352 | −512 |
| CLB Registers | 2,174 | 2,160 | −14 |
| Block RAM Tile（RAMB36） | 0 | 2 | +2（1.39 %） |
| DSP48E2 | 5 | 5 | 0 |
| WNS | +1.977 ns | +2.125 ns | +0.148 ns |
| WHS | +0.001 ns | +0.019 ns | +0.018 ns |
| Total On-Chip Power | 2.613 W | 2.628 W | +0.015 W（估算，Confidence Medium） |

- 兩個 RAMB36 對應 IMEM 4 KB、DMEM 4 KB；LUT 與 Distributed RAM 的減少即為記憶體搬進 BRAM 的結果，剩下的 Distributed RAM 以 trace buffer 為主（推測）。
- 時序沒有變差：setup 最差路徑仍是「EX/MEM 控制 → forwarding → 乘法器（3 個 DSP48E2 串接）→ `alu_result`」，資料路徑 7.594 ns；新增的「EX 位址 → BRAM」路徑沒有成為關鍵路徑。
- 功耗差異在估算誤差內：CPU IP 估計 0.042 W（上一版 0.027 W），其中 Block RAM 0.002 W；總量仍由 PS8（2.158 W）主導。
- 板上測試：Notebook v4 共 48 項全過（含 L6：40 支程式、8470 筆寫回與黃金模型一致）。

#### Stage 2b（IP 1.6）：IMEM/DMEM 改為 BMG + AXI BRAM Controller 後重新量測

同一裝置、同樣 100 MHz 約束、Routed 結果（`design_1_wrapper`，含 PS、兩個 AXI BRAM Controller 與擴增後的 AXI Interconnect）。原始報告見 [`docs/vivado_reports/`](docs/vivado_reports/)。

| 項目 | IP 1.4（LUTRAM） | IP 1.5（BRAM，內部） | IP 1.6（BMG + AXI BRAM Controller） |
|---|---:|---:|---:|
| CLB LUTs | 3,877 | 3,286 | 4,650 |
| LUT as Distributed RAM | 864 | 352 | 352 |
| CLB Registers | 2,174 | 2,160 | 3,691 |
| Block RAM Tile（RAMB36） | 0 | 2 | 2 |
| DSP48E2 | 5 | 5 | 5 |
| WNS | +1.977 ns | +2.125 ns | +1.979 ns |
| WHS | +0.001 ns | +0.019 ns | +0.015 ns |
| Total On-Chip Power | 2.613 W | 2.628 W | 2.641 W |

- LUT 與暫存器比 IP 1.5 增加（+1,364 LUT、+1,531 FF）：新增的是兩個 AXI BRAM Controller 與多出兩個 Master 埠的 AXI Interconnect（含 AXI4→AXI4-Lite 協定轉換），這些是讓 PS 能存取 BRAM 的代價；CPU 核心本身與 IP 1.5 相同（此為依架構的推測，未做逐模組的資源拆分）。BRAM 仍是 2 個 RAMB36（IMEM、DMEM 各 4 KB）。
- 時序全部滿足（All user specified timing constraints are met）：setup 最差路徑仍是「EX forwarding → 乘法器（DSP48E2 串接）→ `alu_result`」，資料路徑 7.745 ns、19 級邏輯；依 WNS +1.979 ns 粗估上限約 125 MHz（估算，非實測）。WHS 僅 +0.015 ns，不同 Implementation run 之間可能浮動。
- 功耗（Vivado 估算，Confidence Medium）：Dynamic 2.216 W（PS8 2.158 W、CPU IP 0.039 W、兩個 BMG 各約 0.002~0.003 W、兩個 AXI BRAM Controller 各 0.002 W、Interconnect 0.009 W）、Static 0.425 W、Junction 31.1 °C。總量仍由 PS8 主導。

### 功耗（Vivado 預估，`report_power`；以下為 Stage 1 / IP 1.4 build）

| 項目 | 功耗 |
|---|---:|
| Total On-Chip Power | 2.613 W |
| Dynamic | 2.189 W |
| 　其中 PS8（ARM 處理器系統） | 2.158 W |
| 　其中 `rv32i_pipelined_cpu_0`（本 CPU IP） | 0.027 W |
| Device Static | 0.425 W |
| Junction Temperature | 31.1 °C |

- 總功耗幾乎全由 PS8（Zynq 的 ARM 處理器）佔用；本 CPU IP 約 0.027 W，只佔總量約 1%。
- 這是 Vivado 的預設活動率估算（Confidence Level：Medium，內部節點活動率未用模擬 SAIF 校正），僅供參考，非板上實測。

### riscv-arch-test（官方 ISA 合規測試，模擬）

| 套件 | PASS | 預期 FAIL（未實作） |
|---|---|---|
| RV32I（38） | 32 | 6（`lb/lbu/lh/lhu/sb/sh`，核心只有 `lw/sw`） |
| RV32M（8） | 1（`mul`） | 7（`mulh*` / `div*` / `rem*`） |
| Zbb（18） | 18 | 0 |

核心支援的 **51 / 51 項全部通過**。I / M 以官方 `reference_output` 比對；Zbb 以 QEMU 8.2.2 為參考（QEMU 先以 46 項官方簽章驗證，46/46 相同）。突變測試 9/10 被抓到；未抓到的 load-use stall 屬流水線 hazard，由自建 testbench 負責。方法、重現步驟與限制見 [`docs/ARCH_TEST.md`](docs/ARCH_TEST.md)。

### 驗證範圍與限制

目前已在實板上驗證內建測試程式的執行結果、控制／除錯介面、特定程式的 trace 與 ISA 黃金模型一致性，Zbb / `MUL` / `XDOTP16` 的指定運算與非法指令偵測，以及 PS 經 AXI BRAM Controller 載入並執行不同程式（40 支隨機程式與黃金模型逐筆一致）。

目前測試結果**尚不能單獨證明**：

- 完整的 ISA compliance：riscv-arch-test 已通過（核心支援的 51 項全過，僅在模擬、2 MB 記憶體下執行，見 [`docs/ARCH_TEST.md`](docs/ARCH_TEST.md)），但尚未在實板上跑，也不涵蓋核心未實作的指令
- 所有 forwarding、load-use stall、branch flush 情境均已完整覆蓋
- 實際可達的最高時脈（目前只有依 slack 的估算）、板上實測功耗，以及不同 Vivado run 之間 hold slack（目前僅 +0.001 ns）的穩定性
- CPU 執行中由 PS 寫入 IMEM／DMEM 的行為（目前只在 CPU reset 時載入程式；執行中只測了 PS 讀取）
- 更大的記憶體（目前 IMEM／DMEM 各 4 KB；參數化，尚未以 16 KB 上板）

上述項目應分別透過專用測試與 Vivado 報告確認。

## Roadmap

### Phase 1 — RV32I 5-Stage Pipeline

- [x] RV32I 五級管線 CPU RTL
- [x] Control Unit
- [x] Hazard Detection 與 Forwarding 邏輯
- [x] Branch / Jump 控制邏輯
- [x] PYNQ-ZU 實板執行內建測試程式
- [x] Reset / Run 與重複執行測試
- [x] Trace write-back event 與 ISA 黃金模型比對
- [x] 由 trace 重建暫存器並與黃金模型比對
- [x] `JALR`、Branch / `AUIPC`、load-use 接 branch、非法指令的獨立 testbench
- [x] 隨機程式（含 forwarding / load-use / branch flush）與 Python 黃金模型比對
- [ ] 針對各類 RV32I 指令補齊完整的獨立測試程式與 compliance test
- [x] 含 `XDOTP16` 版本的 Vivado 時序（WNS / WHS）與資源（LUT / FF / DSP）已量測，功耗為 Vivado 預估值

### Phase 2 — AXI-Lite Control / Debug

基本控制／除錯介面已完成實板測試。

```text
PS / ARM
   ↓
AXI4-Lite
   ↓
CPU Wrapper
   ↓
RV32I CPU
```

- [x] 透過 AXI4-Lite 控制 CPU reset/run
- [x] 讀取 PC、write-back 與 DMEM 除錯資訊
- [x] 讀取 trace buffer 並進行逐 cycle 比對
- [x] 非法指令回報與功能旗標暫存器
- [x] 打包為 Vivado IP 並整理打包注意事項（見 `docs/`）
- [ ] 將 RTL、Notebook、`.bit` 與 `.hwh` 版本配對管理
- [ ] 自動彙整測試結果並保存每次執行報告

### Phase 3 — RISC-V Extensions

- [x] **riscv-arch-test**：RV32I / `MUL` / Zbb 共 51 項核心支援的測試全部通過（模擬；詳見 `docs/ARCH_TEST.md`）

- [x] **RV32M：`MUL`**（單週期、低 32 位元；`MULH*` / `DIV*` / `REM*` 仍視為 illegal）
- [x] **Zbb：`CLZ` / `CTZ` / `CPOP`**
- [x] **Zbb：`MIN` / `MAX`**
- [x] **Zbb：`ANDN` / `ORN` / `XNOR`**
- [x] **Zbb：`ROL` / `ROR`**
- [x] **Custom `XDOTP16`**（不累加版，模擬與實板皆通過）
- [ ] `XDOTP16` 累加版（`rd += 內積`，需第三個讀取埠與 forwarding / hazard 修改）
- [x] 以 FIR / 內積 / 矩陣乘比較使用與未使用 `XDOTP16` 的週期數（RTL 模擬：比純標量快 1.5～1.8 倍；實板 24/24 PASS（100 MHz 下重跑亦通過），板上週期數與模擬一致；見 [`docs/XDOTP16_BENCHMARK.md`](docs/XDOTP16_BENCHMARK.md)）

`XDOTP16` 作為自訂指令，用於展示 instruction decode、datapath 與 ALU／functional unit 的硬體擴充。

### Phase 4 — AXI / BRAM Integration

後續目標是讓 PS/PYNQ 能更完整地管理指令與資料記憶體，並支援載入及執行不同測試程式。

```text
             PS / ARM
                 │
                AXI
                 │
        AXI Interconnect
                 │
        AXI BRAM Controller
                 │
                BRAM
                 ▲
                 │
          RISC-V CPU Core
```

**IP 版本紀錄（Phase 4）**

| IP 版本 | 內容 | 板測 |
|---|---|---|
| 1.3 | 新增自訂指令 `XDOTP16`（FEATURE bit 2） | Notebook v3：40/40 |
| 1.4 | Stage 1：PS 經 AXI 暫存器載入 IMEM（FEATURE `0xF`） | Notebook v4 L1~L7 通過 |
| 1.5 | Stage 2a：pipeline 改為 BRAM 同步讀取（IMEM 位址 = `pc_next`；DMEM 讀寫移到 EX） | Notebook v4：48 項全過 |
| 1.6 | Stage 2b：CPU IP 開 BRAM master 介面，接 BMG + AXI BRAM Controller；移除 1.4 的載入暫存器；FEATURE `0x17` | Notebook v5：**52/52 PASS** |

**Stage 1（IP 1.4，已上板；IP 1.6 起被取代）— PS 可寫入的指令記憶體**：`imem` 新增寫入埠，PS 在 CPU reset 時經 AXI 暫存器 `0x30/0x34/0x38` 載入程式。IP 1.6 改由 BRAM 取代，這三個暫存器已移除。

**Stage 2a（模擬完成）— pipeline 改為 BRAM 同步讀取**：IMEM 位址接 `pc_next`（stall 時保持 `pc`，讀出的指令與 `pc` 同拍對齊）；DMEM 的位址／寫入資料／寫入致能改由 EX 階段驅動（專用加法器 `rs1 + imm`），讀出資料在 MEM 階段出現。store 在 EX 提交是安全的（EX 內的指令不會是推測執行），所以 store 後緊接 load 不需要額外 bypass。與改動前逐 cycle 比對（41 支程式 × 1500 cycle）結果完全相同，沒有增加 stall。記憶體大小以 `IMEM_ADDR_WIDTH` / `DMEM_ADDR_WIDTH` 參數化（預設 12 = 4 KB，14 = 16 KB 已通過同一組測試）。

**Stage 2b（IP 1.6，已上板驗證，Notebook v5 共 52 項全過）— Block Memory Generator + AXI BRAM Controller**：CPU IP 對外開兩組 BRAM master 介面（`imem_bram_*` 唯讀、`dmem_bram_*` 讀寫；32 位元**位元組位址**、`we[3:0]` 位元組寫入致能、讀取延遲 1 個週期，與 Stage 2a 的 pipeline 時序一致）。每塊記憶體是一個 true-dual-port BMG：port B 給 CPU，port A 經 AXI BRAM Controller 給 PS。PS 因此可以直接載入程式、讀寫 DMEM，不再受 256 筆 trace 的限制；預設程式改由 COE（`bram_init/imem_board_program.coe`）初始化，因此 `imem_bmg` 使用 Stand Alone 模式（BRAM Controller 模式不允許載入 COE）；兩顆 BMG 都是 32 位元、深度 1024（4 KB）、Output Register 關閉、**Enable Port Type 必須是 Use ENA/ENB Pin**（設成 Always Enabled 會讓 PS 批次寫入時 word 0 被誤寫，見開發紀錄 Bug 11）。`EXTERNAL_MEM` 參數預設為 IP 模式 1；測試用的獨立 `rv32i_pipeline` 預設 0（內部記憶體），所以原本的 testbench 完全不用改。操作步驟與踩雷見 [`docs/PHASE4_STAGE2B_VIVADO.md`](docs/PHASE4_STAGE2B_VIVADO.md)。

```text
             PS / ARM
                 │ AXI
        AXI Interconnect ──────────────┐
          │              │             │
   AXI BRAM Ctrl     AXI BRAM Ctrl   CPU IP（AXI-Lite 控制/除錯 + 兩組 BRAM master）
          │ port A       │ port A       │ imem_bram (port B, 唯讀)
        IMEM BMG ◄───────┼──────────────┘
        DMEM BMG ◄───────┴──── dmem_bram (port B)
```

- [x] Stage 1（IP 1.4）：PS 經 AXI 暫存器載入程式（已上板，IP 1.6 起移除）
- [x] Stage 1 上板驗證（Notebook v4：L1~L7）
- [x] Stage 2a：pipeline 同步讀取 IMEM/DMEM（`tb_bram_timing`、既有測試全過）
- [x] Stage 2a 上板驗證與重新量測資源／時序（BRAM 2 個 RAMB36；Notebook v4 共 48 項全過）
- [x] Stage 2b RTL 與系統層級模擬（`tb_axi_bram_system`）
- [x] Stage 2b Vivado 整合與上板驗證（Notebook v5：T1~T8 + L1~L9，共 52 項全過）
- [x] 驗證記憶體初始化（COE）、PS 讀寫、執行中 PS 讀取不影響 CPU
- [ ] 尚未驗證：CPU 執行中 PS 寫入 IMEM／DMEM 的行為（目前只在 CPU reset 時載入程式）

## Technical Topics

RISC-V RV32I · RV32M · Zbb · Custom Instruction · Computer Architecture · 5-Stage Pipeline · Datapath · Register File · ALU · DSP48E2 · Pipeline Registers · Data Forwarding · Hazard Detection · Load-Use Stall · Branch/Jump Control · Pipeline Flush · Illegal Instruction Detection · Verilog/SystemVerilog · Vivado · IP Packager · FPGA · PYNQ-ZU · PS/PL · AXI4-Lite · Trace Buffer · BRAM

## Author

**Yu-Chen Chao**
RV32I 5-Stage Pipeline CPU

Platform: PYNQ-ZU

HDL: Verilog / SystemVerilog

ISA: RISC-V RV32I + Zbb + RV32M (`MUL`) + custom `XDOTP16`
