# Phase 4 Stage 2b（IP 1.6）— Vivado 操作指南

本文件記錄 **實際在 PYNQ-ZU 上驗證通過（Notebook v5：52/52 PASS）** 的 Vivado 2022.2 流程，包含踩過的坑。
介面名稱依 Vivado 2022.2；若選項位置略有不同，以「要達到的效果」與每步的檢查點為準。

## 0. 目標與最終架構

IMEM / DMEM 各改成一顆 Block Memory Generator（BMG）。CPU 接在 BMG 的 port B；PS 經 AXI BRAM Controller 接在 port A，
所以 PS 可以直接載入程式、讀寫 DMEM。

```text
 Zynq PS ──M_AXI_HPM0_LPD── ps8_0_axi_periph ──M00── rv32i_pipelined_cpu_0 (S00_AXI：控制／除錯)
                                   │
                                   ├──M01── imem_ctrl ──BRAM_PORTA── imem_bmg ──BRAM_PORTB── rv32i_pipelined_cpu_0/IMEM_BRAM
                                   └──M02── dmem_ctrl ──BRAM_PORTA── dmem_bmg ──BRAM_PORTB── rv32i_pipelined_cpu_0/DMEM_BRAM
```

| 區塊 | 位址 | Range | 備註 |
|---|---|---|---|
| `rv32i_pipelined_cpu_0/S00_AXI` | `0x8000_0000` | 64K | 控制／除錯暫存器（不變） |
| `imem_ctrl/S_AXI` | `0x8001_0000` | 4K | IMEM，PS 可讀寫 |
| `dmem_ctrl/S_AXI` | `0x8002_0000` | 4K | DMEM，PS 可讀寫 |

Notebook v5 cell ① 的 `IMEM_BASE = 0x80010000`、`DMEM_BASE = 0x80020000` 必須與 Address Editor 一致。

## 1. 先決條件

- 有可運作的 IP 1.5 設計（`design_1`：Zynq PS、`ps8_0_axi_periph`、`rv32i_pipelined_cpu_0`）。
- 模擬通過：`sim/run_xsim.bat` 全部 PASS（含 `tb_axi_bram_system`）。

## 2. 更新並重新打包 IP（版本 1.6）

1. 把 `src/*.v`、`axi/rv32i_pipelined_cpu_v1_0.v`、`axi/rv32i_pipelined_cpu_v1_0_S00_AXI.v` 覆蓋到 IP 資料夾的 `hdl/`。
   **不要**把 `sim/bmg_tdp_model.v` 加進 IP（只用於模擬）。
2. IP Packager → File Groups：確認 Synthesis / Simulation 的檔案清單沒有多出檔案，Merge changes。
3. Ports and Interfaces：頂層應有 `imem_bram_*`、`dmem_bram_*` 兩組埠（各 `addr[31:0] clk rst en we[3:0] din[31:0] dout[31:0]`）。
   - Vivado 通常會自動辨識成 `xilinx.com:interface:bram_rtl`（Master）介面 `IMEM_BRAM`、`DMEM_BRAM`，檢查埠對應即可。
   - 若沒有辨識：Add Bus Interface → `bram_rtl`（`xilinx.com:interface:bram:1.0`）、Mode = **Master**；
     Port Mapping：`ADDR→*_bram_addr`、`CLK→*_bram_clk`、`DIN→*_bram_din`、`DOUT→*_bram_dout`、`EN→*_bram_en`、`RST→*_bram_rst`、`WE→*_bram_we`。
4. Review and Package → 版本改成 **1.6** 並 Re-Package（版本號不變 BD 不會提示 Upgrade）。
5. 主專案：Report IP Status → Upgrade Selected。`rv32i_pipelined_cpu_0` 上會出現 `IMEM_BRAM`、`DMEM_BRAM` 兩個介面。

## 3. Block Design 要加的元件

- 兩顆 **Block Memory Generator**：`imem_bmg`、`dmem_bmg`
- 兩顆 **AXI BRAM Controller**：`imem_ctrl`、`dmem_ctrl`

> Connection Automation 可能自動多長出一顆 BMG（例如 `dmem_ctrl_bram`），接好後把多出來的刪掉；總共只留 `imem_bmg`、`dmem_bmg`。

## 4. BMG 設定（`imem_bmg`、`dmem_bmg` 相同，只有 COE 不同）

兩顆都用 **Stand Alone** 模式。原因：BRAM Controller 模式下 Write Depth 由 controller 範圍推導（常停在 2048 或 8192 改不動），
`Load Init File` 也是灰色，Tcl 設定會被忽略（`IP_Flow 19-3374`）。

**Basic**

| 選項 | 值 |
|---|---|
| Interface Type | Native |
| Mode | **Stand Alone** |
| Memory Type | **True Dual Port RAM** |
| **Generate address interface with 32 bits** | **勾選**（CPU 與 controller 送的是位元組位址） |
| Common Clock | 不勾 |
| Enable Byte Write | **勾選**，Byte Size = **8** |
| ECC | None |

**Port A Options 與 Port B Options（兩邊一樣）**

| 選項 | 值 |
|---|---|
| Write Width / Read Width | 32 |
| Write Depth | **1024**（4 KB） |
| Operating Mode | Write First（Read First 在此組態不可選也沒關係，見下） |
| **Enable Port Type** | **Use ENA Pin（Port B：Use ENB Pin）** |
| Primitives Output Register / Core Output Register | **都不勾**（讀取延遲必須是 1 個週期） |
| RSTA / RSTB Pin | 不勾 |

**Other Options**

| 選項 | `imem_bmg` | `dmem_bmg` |
|---|---|---|
| Load Init File | **勾選**，`bram_init/imem_board_program.coe` | 不載入（預設 0） |
| Fill Remaining Memory Locations | 勾選，Remaining Memory Locations (Hex) = `13`（NOP） | — |

關鍵檢查點：

- **Enable Port Type 一定要是 Use ENA/ENB Pin。** 設成 Always Enabled 時 BMG 的 ENA 腳位消失、AXI BRAM Controller 的 `en` 沒有地方接，
  PS 批次寫入時 word 0 會被誤寫（IMEM 第一個指令變成 NOP，見第 10 節與開發紀錄 Bug 11）。
- **Output Register 絕對不能開。** 開了讀取延遲變 2，CPU 取指會整個錯位。
- Operating Mode：CPU 不會在同一個埠、同一個週期讀寫同一個位址，所以 Write First / Read First 功能上等價。
- 位址介面必須是 32 位元位元組位址；深度 1024 時 BMG 用位址的 `[11:2]`。

## 5. AXI BRAM Controller 設定（`imem_ctrl`、`dmem_ctrl`）

- Protocol：**AXI4LITE**；Data Width：32；ECC 關閉。
- **Number of BRAM interfaces = 1**（預設會有 PORTA / PORTB，PORTB 是多餘的；留著會佔用 BMG 的 port B）。
- 記憶體深度由 Address Editor 的位址範圍決定（4K → 1024 字），要與 BMG 深度一致。

## 6. 接線

| 來源 | 接到 |
|---|---|
| `imem_ctrl/BRAM_PORTA` | `imem_bmg/BRAM_PORTA` |
| `dmem_ctrl/BRAM_PORTA` | `dmem_bmg/BRAM_PORTA` |
| `rv32i_pipelined_cpu_0/IMEM_BRAM` | `imem_bmg/BRAM_PORTB` |
| `rv32i_pipelined_cpu_0/DMEM_BRAM` | `dmem_bmg/BRAM_PORTB` |
| `imem_ctrl/S_AXI`、`dmem_ctrl/S_AXI` | `ps8_0_axi_periph`（Run Connection Automation，M01、M02） |
| 時脈與 reset | 與 CPU IP 同一組：`pl_clk0`、`rst_ps8_0_99M/peripheral_aresetn` |

用 Tcl Console 驗證四條 BRAM 連線（每行都要有對應的 BMG 腳位）：

```tcl
foreach p {imem_ctrl/BRAM_PORTA dmem_ctrl/BRAM_PORTA rv32i_pipelined_cpu_0/IMEM_BRAM rv32i_pipelined_cpu_0/DMEM_BRAM} {
  set n [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins $p]]
  puts "$p -> [get_bd_intf_pins -quiet -of_objects $n]"
}
```

## 7. 位址（Address Editor）

依第 0 節的表格設定：`imem_ctrl` = `0x80010000`、`dmem_ctrl` = `0x80020000`，Range 都是 **4K**。
**每次修改 BMG 設定或 Validate 之後，位址可能被 Vivado 重設**（曾變成 `0x81000000`／`0x82000000`），請用 Tcl 檢查：

```tcl
foreach s [get_bd_addr_segs -of_objects [get_bd_addr_spaces zynq_ultra_ps_e_0/Data]] {
  puts "$s offset=[get_property offset $s] range=[get_property range $s]"
}
```

預期輸出：`SEG_imem_ctrl_Mem0 offset=0x0080010000 range=0x1000`、`SEG_dmem_ctrl_Mem0 offset=0x0080020000 range=0x1000`、
`SEG_rv32i_pipelined_cpu_0_S00_AXI_reg offset=0x0080000000 range=0x10000`。

## 8. Validate Design（F6）— 預期的訊息

| 訊息 | 意義 | 處理 |
|---|---|---|
| BD 41-759：`*_bram_dout` 未連接 | CPU 的 BRAM 介面沒接到 BMG | 接到 `BRAM_PORTB`（真的要處理） |
| BD 41-237：`MASTER_TYPE` 不一致（BMG 為 `BRAM_CTRL`、CPU 介面為 `OTHER`） | BMG 是 BRAM Controller 模式時的提示 | 提示性警告，不影響功能；不需為此重新打包 IP |
| `rsta_busy`／`rstb_busy` 沒接 | 輸出沒有使用 | 可忽略 |

## 9. 產生 bitstream 並上板

1. Generate Output Products（Global）→ Create HDL Wrapper（Let Vivado manage）→ Implementation → Bitstream。
2. 檢查 Utilization：Block RAM Tile = **2**；WNS ≥ 0。
3. 報告輸出：
   ```tcl
   open_run impl_1
   report_utilization    -file util_v16.txt
   report_timing_summary -file timing_v16.txt
   report_power          -file power_v16.txt
   ```
4. 匯出成對的 `.bit` 與 `.hwh`（同一次 build、同檔名前綴），複製到 PYNQ 同一資料夾，重啟 Jupyter kernel。
5. 上傳 `sim/zbb_prog.hex` 到 `/home/xilinx/jupyter_notebooks/`（L7 需要），執行 `RV32I_CPU_Board_Test_v5.ipynb`（cell ① 的 bit 檔名要與實際相同）。

**驗收結果（IP 1.6）：** Notebook v5 共 52 項全過；LUT 4,650、FF 3,691、Distributed RAM 352、BRAM 2、DSP 5、
WNS +1.979 ns、WHS +0.015 ns、2.641 W。原始報告在 `docs/vivado_reports/ip1.6/`，板測報告為
`pynq_5-stage-pipeline-CPU_TEST/cpu_test_report_v5_ip1.6_52of52.json`。

## 10. 踩雷整理

| 症狀 | 原因 | 解法 |
|---|---|---|
| BMG Write Depth 一直是 2048／8192，RSTA Pin 鎖住 | BRAM Controller 模式下由 controller 範圍推導 | 改用 Stand Alone，手動設深度 1024 |
| Load Init File 灰色、Tcl 設定被忽略（`IP_Flow 19-3374`） | BRAM Controller 模式鎖住初始化檔 | 改用 Stand Alone |
| L4~L8 失敗：程式少執行第一個指令；讀回 `imem[0]` 變成 `0x13` | `imem_bmg` 的 Enable Port Type = Always Enabled；批次寫入時每個 16 位元組對齊的寫入都會多寫一份到 word 0 | 改為 Use ENA Pin／Use ENB Pin（開發紀錄 Bug 11） |
| 位址又變成 `0x81000000`／`0x82000000` | Validate 時 Vivado 重新分配 | 手動設回並用 Tcl 檢查（第 7 節） |
| 多出一顆 BMG（`dmem_ctrl_bram`） | Connection Automation 自動建立 | 刪除多出的 BMG |
| controller 有 PORTB | Number of BRAM interfaces 預設 2 | 設成 1 |
| `MASTER_TYPE` 警告 | BRAM Controller 模式的介面型別不同 | 可忽略 |

找設定差異的技巧：imem / dmem 設計上對稱，用 Tcl 比對所有 CONFIG 屬性，只印出不同的項目：

```tcl
foreach pair {{imem_ctrl dmem_ctrl} {imem_bmg dmem_bmg}} {
  lassign $pair a b
  puts "=== $a vs $b ==="
  foreach p [list_property [get_bd_cells $a] CONFIG.*] {
    set va [get_property $p [get_bd_cells $a]]
    set vb [get_property $p [get_bd_cells $b]]
    if {$va ne $vb} { puts "$p  $a=$va  $b=$vb" }
  }
}
```

預期只有名稱與 COE 相關欄位（`Component_Name`、`Coe_File`、`Load_Init_File`）不同。

## 11. 除錯順序（出問題時）

1. `FEATURE`（`0x2C`）讀到 `0x17`？不是 → 還是舊 bitstream／舊 IP。
2. L2：讀回 IMEM 前 136 字 = 板測程式？不是 → AXI BRAM Controller／位址／COE 初始化有問題（PS 這一側）；全 0 代表 COE 沒載入。
3. L3：DMEM 寫入圖樣能讀回？不是 → 位址或位元組寫入問題（PS 這一側）。
4. T2：run 後 PC 變動且停在 spin？不是 → CPU 這一側：先檢查 BMG **Output Register 是否被勾**、**32-bit address interface 是否勾選**、BMG 深度與 controller 範圍是否一致。
5. L4~L7：結果不對但 PC 正常 → 載入後讀回 `imem[0:6]`，看 word 0 是不是正確的第一個指令（`Enable Port Type` 問題）；
   再看 trace 前幾筆與整塊 DMEM 的差異字（Notebook 會印出前幾個差異字）。整字都錯多半是位元組寫入致能（`we[3:0]`）或位址偏移。
