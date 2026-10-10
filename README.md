# RV32I 5-Stage Pipeline CPU on PYNQ-ZU

本專案以 Verilog/SystemVerilog 實作基於 **RISC-V RV32I ISA** 的 **五級管線 CPU**，目標平台為 **PYNQ-ZU**。目前已完成 CPU 核心 RTL，並透過 AXI4-Lite 控制／除錯介面在 PYNQ-ZU FPGA 實板執行內建測試程式。

> **最新實板測試結果：16/16 PASS。** 新版含 trace buffer 的 bitstream 已通過 Notebook 中的 reset/run、資料觀察、trace 擷取、ISA 黃金模型比對與重複執行測試。此結果代表目前測試程式與測試情境通過，不代表所有 RV32I 指令及所有邊界情況均已完整驗證。

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
- **ID（解碼）**：解碼 opcode、funct3、funct7，讀取 Register File，產生 immediate 與控制訊號。
- **EX（執行）**：執行 ALU 運算、計算 Load/Store 位址，以及 Branch/Jump target。
- **MEM（記憶體存取）**：執行 Data Memory 的 Load / Store。
- **WB（寫回）**：將 ALU result 或 Memory read data 寫回目的暫存器。

## Main Components

- Program Counter（PC）
- Instruction Memory（IMEM）
- Data Memory（DMEM）
- Register File（32 × 32-bit，`x0` 固定為 0）
- Control Unit
- Immediate Generator
- ALU / ALU Control
- IF/ID、ID/EX、EX/MEM、MEM/WB Pipeline Registers
- Hazard Detection Unit
- Forwarding Unit
- Branch / Jump control
- Stall / Flush logic
- AXI4-Lite CPU control/debug wrapper
- Trace buffer（除錯版本）

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

當 Load 資料尚未準備完成時，Hazard Detection Unit 需要產生適當的 stall / bubble。相關控制邏輯仍應搭配獨立測試程式，持續驗證不同資料相依情境。

### Control Hazard

Branch / Jump 改變 PC 時，CPU 需要重新導向 PC，並 flush 不再有效的 pipeline instruction，避免錯誤路徑指令產生不正確的架構狀態。

## RV32I

目前 CPU 以 **RV32I** 為主要 ISA，設計涵蓋下列基本指令類型：

- R-Type arithmetic / logic
- I-Type arithmetic / immediate
- Load / Store
- Branch
- JAL / JALR
- LUI / AUIPC

實際支援的指令與 funct 組合，仍應以目前 RTL 及各項 testbench 的驗證範圍為準；目前的 16/16 實板測試不等同於完整 RV32I compliance test。

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
        │ └─ Trace Buffer*         │
        └─────────────────────────┘
```

`*` Trace buffer 存在於目前用於測試的除錯版本。

目前 Notebook 使用的 bitstream 路徑為：

```python
BIT  = "/home/xilinx/jupyter_notebooks/design_1_wrapper.bit"
BASE = 0x80000000
SIZE = 0x10000
```

請確認 `.bit` 與同名 `.hwh` 為同一次 Vivado 匯出的配對檔案。替換 bitstream 後，請先在 Jupyter 選擇 **Kernel → Restart**，再重新載入 Overlay，以免使用舊的 Overlay／metadata 狀態。

## AXI-Lite Status

**AXI4-Lite 控制／除錯介面已通過目前 Notebook 的 PYNQ-ZU 實板測試。** 測試程式可透過 memory-mapped register 控制 CPU reset/run，讀取 PC、write-back 資料及 DMEM readback，並在新版除錯 bitstream 中讀取 trace buffer。

目前已確認的實板測試結果為 **16/16 PASS**，涵蓋：

- Reset 後 PC 回到 `0x0`
- Run 控制可正常釋放 reset
- PC 進入預期的 spin-loop 區域
- 可觀察到 `JAL` 返回位址 `0xA0`
- 可觀察到 Data Memory readback 值 `42`（`0x2A`）
- Trace buffer 擷取 256 筆紀錄
- 26 筆非 `x0` 的 write-back event 與 ISA 黃金模型一致
- 由 trace 重建的 `x1`–`x31` 暫存器結果與黃金模型一致
- 重複執行的 trace 一致，reset 後亦可重新執行並重現相同 trace

> **目前限制：** CPU 的 Instruction Memory 仍由硬體設計／內建測試程式提供。現有 Notebook 並未證明可直接由 Python 將任意程式寫入 CPU 的 Instruction Memory。透過 AXI4-Lite 控制 CPU 與讀取除錯資訊，和透過 PS 任意載入指令程式，是兩項不同的功能。

### AXI4-Lite Register Map（目前 trace 測試版本）

以下 offset 依照目前通過 16/16 測試的 Notebook。位址是相對於 CPU IP base address `0x80000000`；若更換 RTL／bitstream，請重新確認暫存器映射。

| Offset | 名稱 | 用途 |
|---:|---|---|
| `0x00` | `CTRL` | 寫入 `0`：assert reset；寫入 `1`：解除 reset 並執行；測試 trace 時先寫入 `2` 作為 arm/clear，再寫入 `1` 執行 |
| `0x04` | `PC` | 讀取目前 Program Counter |
| `0x08` | `WBD` | 讀取 write-back data 取樣值 |
| `0x0C` | `DMEM` | 讀取 Data Memory readback 取樣值 |
| `0x10` | `T_STATUS` | Trace 狀態；bit 31 表示支援 trace，低位元回報擷取筆數 |
| `0x14` | `T_IDX` | 寫入欲選取的 trace entry index |
| `0x18` | `T_PC` | 讀取所選 trace entry 的 PC |
| `0x1C` | `T_WB` | 讀取所選 trace entry 的 write-back data |
| `0x20` | `T_META` | 讀取 trace metadata；Notebook 以 `(meta >> 1) & 31` 取得 `wb_rd`，以 `meta & 1` 取得 `wb_we` |

測試輸出中的 trace status 為 `0x80000100`，代表該版本已啟用 trace，且擷取到 256 筆紀錄。

## Project Structure

```text
rv32i_pipeline/
├── source/
│   └── CPU RTL / Verilog / SystemVerilog
├── sim/
│   └── Testbench / simulation files
├── constrs/
│   └── FPGA constraints
└── README.md
```

實際檔案名稱與資料夾可能依目前 Vivado project／GitHub repository 結構調整。建議將實板測試 Notebook、對應的 `.bit`／`.hwh` 版本資訊及 `cpu_test_report.json` 一併保存，讓結果可以重現。

## Verification Status

### PYNQ-ZU 實板測試結果

| 測試 | 驗證內容 | 結果 |
|---|---|---|
| T1 | Assert reset，確認 PC 回到 `0x0` | PASS |
| T2a | Run 控制成功，`CTRL[0] = 1` | PASS |
| T2b | PC 停在預期的 spin-loop 區域 | PASS |
| T2c | Write-back 取樣可觀察到 `JAL` 返回位址 `0xA0` | PASS |
| T2d | Data Memory readback 可觀察到 `42`（`0x2A`） | PASS |
| T3a | 再次 reset 後 PC 回到 `0x0` | PASS |
| T3b | 重複 reset/run 五次，結果一致 | PASS |
| T4a | Trace buffer 填入 256 筆紀錄 | PASS |
| T4b | Write-back event 與 ISA 黃金模型比對，共 26 筆 | PASS |
| T4c | Trace 第 0 筆的 PC 為 `0x0` | PASS |
| T4d | Trace PC 均為 4-byte 對齊，且位於預期程式範圍 | PASS |
| T4e | 最後 16 個 cycle 位於預期 spin-loop 區域 | PASS |
| T4f | 由 trace 重建的 `x1`–`x31` 與黃金模型一致 | PASS |
| T5 | 再次執行後，逐 cycle trace 完全一致 | PASS |
| T6a | 執行後 reset，PC 回到 `0x0` | PASS |
| T6b | Reset 後重跑，trace 與第一次相同 | PASS |
| **總計** | **目前 Notebook 所包含的測試** | **16/16 PASS** |

### 驗證範圍與限制

目前已在實板上驗證內建測試程式的執行結果、控制／除錯介面，以及特定程式的 trace 與 ISA 黃金模型一致性。接下來仍應補上各類指令與 pipeline hazard 的獨立 directed tests。

目前測試結果**尚不能單獨證明**：

- 所有合法 RV32I 指令編碼與所有邊界情況均通過完整 compliance test
- 所有 forwarding、load-use stall、branch flush 情境均已完整覆蓋
- 已完成時序收斂、最高時脈、功耗或 FPGA 資源使用量評估
- PYNQ 可任意下載程式至 CPU Instruction Memory
- CPU 已透過 AXI BRAM Controller 與 PS 共用外部 BRAM

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
- [ ] 針對各類 RV32I 指令增加獨立測試程式
- [ ] 針對 forwarding、load-use stall、branch flush 與邊界情境增加 directed tests
- [ ] 整理 Vivado timing 與 resource utilization 報告

### Phase 2 — AXI-Lite Control / Debug

目前已完成基本控制／除錯介面的實板測試，下一步是持續改善可測試性與版本管理。

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
- [x] 讀取新版 trace buffer 並進行逐 cycle 比對
- [ ] 將 RTL、Notebook、`.bit` 與 `.hwh` 版本配對管理
- [ ] 自動彙整測試結果並保存每次執行報告

### Phase 3 — RISC-V Extensions

預計研究與實作，完成後需另行驗證：

- [ ] **RV32M：`MUL`**
- [ ] **Zbb：`CLZ` / `CTZ` / `CPOP`**
- [ ] **Zbb：`MIN` / `MAX`**
- [ ] **Zbb：`ANDN` / `ORN` / `XNOR`**
- [ ] **Zbb：`ROL` / `ROR`**
- [ ] **Custom `XDOTP16`**

其中 `XDOTP16` 預計作為自訂指令，用於展示 instruction decode、datapath 與 ALU／functional unit 的硬體擴充。

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

- [ ] 定義 CPU 與 PS 可存取記憶體的介面及位址映射
- [ ] 驗證記憶體初始化、存取仲裁與 CPU/PS 控制權
- [ ] 讓 PS 載入不同測試程式並執行比對

## Technical Topics

RISC-V RV32I · Computer Architecture · 5-Stage Pipeline · Datapath · Register File · ALU · Pipeline Registers · Data Forwarding · Hazard Detection · Load-Use Stall · Branch/Jump Control · Pipeline Flush · Verilog/SystemVerilog · Vivado · FPGA · PYNQ-ZU · PS/PL · AXI4-Lite · Trace Buffer · BRAM

## Author

**Yu-Chen Chao**
RV32I 5-Stage Pipeline CPU
Platform: PYNQ-ZU
HDL: Verilog / SystemVerilog
ISA: RISC-V RV32I
