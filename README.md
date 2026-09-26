# RV32I 5-Stage Pipeline CPU on PYNQ-ZU

本專案實作一個基於 **RISC-V RV32I ISA** 的 **5-stage pipeline CPU**，目標平台為 **PYNQ-ZU**。

目前專案核心為 **RV32I 五級管線 CPU RTL**；**AXI-Lite、AXI/BRAM 與 PYNQ-ZU 實板整合尚未完成測試**，相關內容在本 README 中均標示為後續開發項目。

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

- **IF**：由 PC 取得 instruction，正常情況下 PC + 4。
- **ID**：解碼 opcode/funct3/funct7，讀取 Register File，產生 immediate 與控制訊號。
- **EX**：執行 ALU 運算、計算 Load/Store 位址，以及 Branch/Jump target。
- **MEM**：執行 Data Memory 的 Load / Store。
- **WB**：將 ALU result 或 Memory read data 寫回 Register File。

## Main Components

- Program Counter (PC)
- Instruction Memory (IMEM)
- Data Memory (DMEM)
- Register File（32 × 32-bit，x0 固定為 0）
- Control Unit
- Immediate Generator
- ALU / ALU Control
- IF/ID、ID/EX、EX/MEM、MEM/WB Pipeline Registers
- Hazard Detection Unit
- Forwarding Unit
- Branch / Jump control
- Stall / Flush logic

> PC 目前直接實作在 CPU pipeline RTL 中，不需要另外拆成獨立的 `pc.v` module。

## Pipeline Hazard Handling

### Data Hazard / Forwarding

前後指令存在資料相依時，Forwarding Unit 會利用前面 pipeline stage 的結果進行資料前推，以降低不必要的 stall。

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

Load data 尚未準備完成時，由 Hazard Detection Unit 產生 stall / bubble。

### Control Hazard

Branch / Jump 改變 PC 時，CPU 需要重新導向 PC 並 flush 不再有效的 pipeline instruction。

## RV32I

目前 CPU 以 **RV32I** 為主要 ISA，涵蓋基本 integer instruction 類型，包括：

- R-Type arithmetic / logic
- I-Type arithmetic / immediate
- Load / Store
- Branch
- JAL / JALR
- LUI / AUIPC

實際支援指令以目前 RTL 與 testbench 為準。

## PYNQ-ZU Architecture

目標 SoC 架構：

```text
             Processing System (PS)
        ┌─────────────────────────┐
        │ ARM Processor           │
        │ Linux / PYNQ            │
        └────────────┬────────────┘
                     │
                    AXI
                     │
        ┌────────────▼────────────┐
        │ Programmable Logic (PL) │
        │                         │
        │   RISC-V CPU Core       │
        │   Instruction Memory    │
        │   Data Memory           │
        │                         │
        └─────────────────────────┘
```

PYNQ-ZU 的 **PS** 負責 ARM/Linux/PYNQ 軟體環境，RISC-V CPU 主要實作於 **PL**。

## AXI-Lite Status

**目前尚未完成 AXI-Lite 實板測試。**

下一階段預計先在 CPU 外部加入 AXI4-Lite Slave Wrapper，讓 PS 可以：

- 控制 CPU Reset / Run
- 讀取 PC
- 讀取 Write-Back 資料
- 讀取 CPU status / debug information

預計架構：

```text
ARM / PYNQ
    │
 AXI4-Lite
    │
    ▼
CPU AXI-Lite Wrapper
    │
    ▼
RV32I 5-Stage CPU
```

> 目前 README 不宣稱上述 AXI-Lite integration 已經在 PYNQ-ZU 實板成功運作。

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

實際檔案名稱可能依 Vivado project 結構調整。

## Verification Status

目前主要驗證方向：

- RV32I instruction execution
- ALU operation
- Register File read / write
- 5-stage pipeline behavior
- Data forwarding
- Load-use stall
- Branch / Jump
- Pipeline flush
- Memory access

PYNQ-ZU、AXI-Lite、AXI/BRAM 的實板驗證尚未列為已完成項目。

## Roadmap

### Phase 1 — RV32I 5-Stage Pipeline

- [x] RV32I CPU datapath
- [x] 5-stage pipeline
- [x] Control Unit
- [x] Hazard Detection
- [x] Forwarding
- [x] Branch / Jump handling
- [ ] Continue verification / debugging

### Phase 2 — AXI-Lite

```text
PS / ARM
   ↓
AXI4-Lite
   ↓
CPU Wrapper
   ↓
RV32I CPU
```

目標是先完成 PS ↔ CPU 的 control/debug communication。

### Phase 3 — RISC-V Extensions

預計研究與實作：

- **RV32M：MUL**
- **Zbb：CLZ / CTZ / CPOP**
- **Zbb：MIN / MAX**
- **Zbb：ANDN / ORN / XNOR**
- **Zbb：ROL / ROR**
- **Custom `XDOTP16`**

其中 `XDOTP16` 預計作為自訂 instruction，用於展示 instruction decode、datapath 與 ALU/functional unit 的硬體擴充。

### Phase 4 — AXI / BRAM Integration

後續目標：

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

目標是讓 PS/PYNQ 可以協助載入 instruction/data，並與 RISC-V CPU 進行更完整的 SoC 整合。

## Technical Topics

本專案涉及：

- RISC-V RV32I ISA
- Computer Architecture
- CPU Datapath
- 5-stage Pipeline
- Pipeline Registers
- Hazard Detection
- Data Forwarding
- Control Hazard / Data Hazard
- Verilog / SystemVerilog RTL Design
- FPGA Design
- PYNQ-ZU
- PS / PL SoC Architecture
- AXI / AXI-Lite
- BRAM

## Oral Presentation Focus

本專題口試主要可以從以下方向說明：

1. **Pipeline**：為什麼拆成 IF / ID / EX / MEM / WB，以及 pipeline register 的作用。
2. **Datapath**：PC → IMEM → Register File → ALU → DMEM → WB 的資料流。
3. **Hazard**：Data Hazard、Load-Use Hazard、Control Hazard，以及 Forwarding / Stall / Flush。
4. **RISC-V ISA**：opcode、funct3、funct7 與 Control Unit 的解碼流程。
5. **FPGA / PYNQ-ZU**：PS 與 PL 的分工，以及後續 AXI / BRAM integration。

## Project Status

| 項目 | 狀態 |
|---|---|
| RV32I CPU | ✅ |
| 5-stage Pipeline | ✅ |
| Datapath | ✅ |
| Control Unit | ✅ |
| Hazard Detection | ✅ |
| Forwarding | ✅ |
| Branch / Jump | ✅ |
| Simulation / Testbench | 🔄 持續驗證 |
| PYNQ-ZU 實板測試 | 🔄 開發中 |
| AXI-Lite | 🔄 尚未實板驗證 |
| RV32M MUL | 📌 後續 |
| Zbb | 📌 後續 |
| XDOTP16 | 📌 後續 |
| AXI / BRAM | 📌 後續 |

---

## Author

**RV32I 5-Stage Pipeline CPU**  
Platform: PYNQ-ZU  
HDL: Verilog / SystemVerilog  
ISA: RISC-V RV32I
