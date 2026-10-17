# 專題成果報告素材（RV32I 五級管線 CPU，PYNQ-ZU）

> 本文件把散在 README、開發紀錄、Vivado 報告裡的數據整理成一份，方便寫專題結果報告。
> 數字皆來自 `docs/vivado_reports/`、`pynq_5-stage-pipeline-CPU_TEST/` 的原始報告與開發紀錄；
> 標「估算」「推測」者表示未經逐項量測或驗證。
> 平台：PYNQ-ZU（xczu5eg-sfvc784-1-i）、Vivado 2022.2、PL 時脈 100 MHz。

---

## 1. 專題摘要

| 項目 | 內容 |
|---|---|
| 核心 | RV32I 五級管線（IF / ID / EX / MEM / WB），含 forwarding、load-use stall、EX 階段分支 flush |
| 擴充 | 非法指令偵測（sticky 旗標 + 首個非法 PC）、Zbb（17 個運算 + rori）、RV32M 的 MUL、自訂指令 XDOTP16 |
| 介面 | AXI4-Lite IP（`rv32i_pipelined_cpu`），ADDR_WIDTH = 6，BASE = 0x8000_0000；256 筆 trace buffer |
| 記憶體 | IMEM / DMEM 各 4 KB，Block Memory Generator（True Dual Port）；CPU 在 port B，PS 經 AXI BRAM Controller 在 port A |
| 驗證 | Python 黃金模型、11 個 testbench、突變測試、PYNQ 實板逐 cycle trace 比對 |
| 最終結果 | IP 1.6 於實板 Notebook v5：**52 / 52 PASS**（2026-10-17）；WNS +1.979 ns @ 100 MHz |

### 自訂指令 XDOTP16（custom-0，R-type，不累加版）

```
rd = rs1[15:0] * rs2[15:0] + rs1[31:16] * rs2[31:16]      （有號 int16 x2 內積，結果 32 位元）
```

設計取捨：先做不累加版，硬體小、風險低、不動 forwarding / hazard；累加版需要第三個讀取埠，
並修改 forwarding 與 hazard，時序也更吃緊（當時 WNS 僅 +1.995 ns）。
不累加版可用 `xdotp16 t,a,b ; add acc,acc,t` 兩條指令達成相同結果。

---

## 2. IP 版本演進

| 版本 | 內容 | 板測 |
|---|---|---|
| 1.0 ~ 1.2 | 早期版本，僅用於上板流程測試，無功能差異 | — |
| 1.3 | 新增自訂指令 XDOTP16；FEATURE bit2 | Notebook v3：40 / 40 |
| 1.4 | Phase 4 Stage 1：PS 可經 AXI 暫存器（0x30 / 0x34 / 0x38）在 CPU reset 時寫入 IMEM；FEATURE = 0x0F | Notebook v4：L1 ~ L7 通過 |
| 1.5 | Phase 4 Stage 2a：管線改為 BRAM 同步讀取（IMEM 位址 = `pc_next`；DMEM 讀寫移到 EX，store 於 EX 提交）；AXI 暫存器不變 | Notebook v4：48 項全過 |
| 1.6 | Phase 4 Stage 2b：CPU IP 對外開 `IMEM_BRAM` / `DMEM_BRAM` 兩組 BRAM master 介面，接 BMG + AXI BRAM Controller；移除 1.4 的載入暫存器；FEATURE = 0x17；預設程式改由 COE 初始化 | Notebook v5：52 / 52 |

### 關於 1.5 的「與前一版逐 cycle 完全相同」

IMEM 位址取 `pc_next`、DMEM 位址 / 寫入資料 / 寫入致能由 EX 階段產生，讓同步讀取的 BRAM 在對外行為上
與原本非同步讀取的記憶體一致。以 41 支程式 x 1500 cycle 做 trace 比對，結果完全相同。

---

## 3. 系統架構（IP 1.6）

```
            ┌────────────── Zynq PS ──────────────┐
            │         AXI4-Lite (ps8_0_axi_periph) │
            └──┬───────────────┬───────────────┬───┘
               │ M00           │ M01           │ M02
     0x8000_0000 (64K)   0x8001_0000 (4K)  0x8002_0000 (4K)
     ┌─────────▼────────┐ ┌────▼─────┐   ┌─────▼────┐
     │ rv32i_pipelined  │ │ imem_ctrl│   │ dmem_ctrl│   AXI BRAM Controller x2
     │ _cpu (S00_AXI)   │ └────┬─────┘   └─────┬────┘
     │                  │      │ PORTA         │ PORTA
     │  IMEM_BRAM ──────┼──► imem_bmg (PORTB)  │
     │  DMEM_BRAM ──────┼──────────────► dmem_bmg (PORTB)
     └──────────────────┘     Block Memory Generator x2（True Dual Port）
```

### AXI 暫存器表（相對 BASE 0x8000_0000）

| 偏移 | 名稱 | 說明 |
|---|---|---|
| 0x00 | CTRL | 寫 0 = reset、0x2 = reset + arm trace、0x1 = run；讀回 `{wb_rd, wb_we, rst_n}` |
| 0x04 | PC | 目前 PC |
| 0x08 | WBD | 最新寫回資料 |
| 0x0C | DMEM | DMEM 觀察值 |
| 0x10 | T_STATUS | [31] 支援 trace、[8:0] 已擷取筆數 |
| 0x14 | T_IDX | trace 讀取索引 |
| 0x18 | T_PC | 該筆 PC |
| 0x1C | T_WB | 該筆寫回資料 |
| 0x20 | T_META | [5:1] wb_rd、[0] wb_we |
| 0x24 | ILLEGAL | 非法指令 sticky 旗標 |
| 0x28 | ILLEGAL_PC | 第一個非法指令的 PC |
| 0x2C | FEATURE | bit0 illegal、bit1 MUL、bit2 XDOTP16、bit4 外部 BRAM（IP 1.6 讀到 0x17） |

### 位址與記憶體

| 區塊 | 位址 | 大小 |
|---|---|---|
| CPU 控制 / 除錯暫存器 | 0x8000_0000 | 64 KB |
| `imem_ctrl`（IMEM，PS 側） | 0x8001_0000 | 4 KB |
| `dmem_ctrl`（DMEM，PS 側） | 0x8002_0000 | 4 KB |

BMG 設定（`imem_bmg`、`dmem_bmg` 相同）：Stand Alone、True Dual Port、寬度 32、深度 1024、
32-bit address interface、Byte Write（8 bit）、Output Register 關閉、**Enable Port Type = Use ENA / ENB Pin**。
`imem_bmg` 載入 `bram_init/imem_board_program.coe`（Fill Remaining = 13，即 NOP）。

---

## 4. Vivado 實作結果

條件：routed、100 MHz、整個 `design_1_wrapper`（含 PS 與周邊 IP）。原始報告見 `docs/vivado_reports/`。

### 4.1 各階段資源 / 時序 / 功耗

| 指標 | MUL 版 | IP 1.3 / 1.4（XDOTP16，LUTRAM） | IP 1.5（內部 BRAM） | IP 1.6（BMG + AXI Ctrl） |
|---|---|---|---|---|
| CLB LUTs | — | 3877 | 3286 | 4650 |
| CLB Registers | — | 2174 | 2160 | 3691 |
| LUT as Distributed RAM | — | 864 | 352 | 352 |
| Block RAM（RAMB36） | — | 0 | 2 | 2 |
| DSP48E2 | 3 | 5 | 5 | 5 |
| WNS (ns) | +1.995 | +1.977 | +2.125 | +1.979 |
| WHS (ns) | +0.010 | +0.001 | +0.019 | +0.015 |
| Total power (W，估算) | — | 2.613 | 2.628 | 2.641 |
| CPU IP power (W) | — | 0.027 | 0.042 | 0.039 |

註：
- MUL 版只記錄了時序與 DSP，未保留 LUT / FF / 功耗。
- DSP48E2 = 3（MUL）+ 2（XDOTP16）= 5。
- WHS 在 XDOTP16 版僅 +0.001 ns，已滿足但餘裕很小，重跑 Implementation 時可能浮動。
- 功耗為 `report_power` 估算，Confidence = Medium；PS8 約 2.158 W，是總功耗的主體。

### 4.2 各階段變化的解讀

| 轉換 | 變化 | 原因 |
|---|---|---|
| 1.4 → 1.5 | LUT -591、Dist RAM 864 → 352、BRAM 0 → 2、WNS +0.148 ns | 記憶體從 LUT 實作改為 BRAM；BRAM 位址路徑不是關鍵路徑 |
| 1.5 → 1.6 | LUT +1364、FF +1531、WNS -0.146 ns | 增加兩個 AXI BRAM Controller 與 Interconnect 多出的兩個 Master 埠（推測，未逐模組拆分） |

### 4.3 關鍵路徑與頻率上限

- setup 關鍵路徑一直是 **EX 階段：forwarding → 乘法器（DSP48E2 串接）→ `alu_result`**。
  IP 1.5 資料路徑 7.594 ns；IP 1.6 資料路徑 7.745 ns、19 級邏輯。
- 依 WNS +1.979 ns 粗估頻率上限約 **125 MHz**（估算，未實際驗證）。
- IP 1.6 的 All user specified timing constraints are met。

### 4.4 IP 1.6 功耗分項

PS8 2.158 W、CPU IP 0.039 W、`ps8_0_axi_periph` 0.009 W、`dmem_bmg` 0.003 W、`imem_bmg` 0.002 W、
兩個 AXI BRAM Controller 各 0.002 W。Dynamic 2.216 W、Static 0.425 W、Junction 31.1 °C。

---

## 5. 驗證方法與結果

### 5.1 驗證層次

| 層次 | 工具 | 內容 |
|---|---|---|
| 黃金模型 | Python（`rv32i_model.py`） | ISA 層級逐指令模型，產生預期的寫回序列與記憶體狀態 |
| RTL 模擬 | iverilog / xsim，11 個 testbench | 見 5.2 |
| 突變測試 | 手動改壞 RTL | 確認測試真的會失敗，見 5.3 |
| 實板 | PYNQ Notebook | 逐 cycle trace 與黃金模型比對，見 5.4 |

### 5.2 Testbench 清單（全部 PASS）

`tb_rv32i_pipeline`、`tb_jalr`、`tb_extra_branches`、`tb_load_use_branch`、`tb_illegal`、`tb_zbb_unit`、
`tb_zbb_prog`（40 支程式，含 MUL 與 XDOTP16）、`tb_board_program`（上板 136 字程式）、`tb_imem_default`（內建預設內容）、
`tb_bram_timing`（BRAM 同步讀取時序邊界）、`tb_axi_bram_system`（CPU IP + BMG 行為模型的系統層級測試）。

### 5.3 突變測試

| 突變 | 預期被哪個測試抓到 | 結果 |
|---|---|---|
| MUL 改成 A + B | `tb_zbb_prog` | 失敗（抓到） |
| XDOTP16 改成 `xp0 - xp1` 或高半部誤接 | `tb_zbb_prog`、`tb_board_program` | 失敗（抓到） |
| imem 舊寫法（115 起填 NOP） | `tb_imem_default` | 失敗，21 項（抓到） |
| store 只寫低位元組 | `tb_axi_bram_system` | 抓到 |
| DMEM 字位址錯誤 | `tb_axi_bram_system` | 抓到 |
| IMEM 不超前取指 | `tb_axi_bram_system` | 抓到 |
| IMEM 誤開寫入 | `tb_axi_bram_system` | 抓到 |

### 5.4 實板測試進程

| 階段 | 通過項數 | 新增內容 |
|---|---|---|
| 基本 + trace | 16 / 16 | reset / run / 重跑、逐 cycle 對照 ISA 模型 |
| Zbb | 32 / 32 | zbb_unit、Python 黃金模型 |
| + illegal | 38 / 38 | ILLEGAL / ILLEGAL_PC / FEATURE 暫存器 |
| + MUL | 39 / 39 | 115 字程式、85 筆寫回、8 條非法指令 |
| + XDOTP16（IP 1.3） | 40 / 40 | 136 字程式、102 筆寫回、XDOTP16 10 筆全對；曾因 Bug 10 失敗一次 |
| Phase 4（IP 1.4 ~ 1.5） | 48 項 | PS 載入程式（L1 ~ L7），含 L6 的 8470 筆寫回比對 |
| IP 1.6（Notebook v5） | **52 / 52** | T1 ~ T8（40 項）+ L1 ~ L9 |

Notebook v5 的 L 系列：
- L1 FEATURE = 0x17
- L2 COE 初始化內容
- L3 PS 讀寫 DMEM
- L4 ~ L7 PS 載入程式並執行（含 40 支隨機程式、8470 筆寫回）
- L8 CPU 執行中 PS 讀取
- L9 還原開機程式

原始報告：`pynq_5-stage-pipeline-CPU_TEST/cpu_test_report_v5_ip1.6_52of52.json`。

---

## 6. Bug 與除錯紀錄

完整描述見 `docs/專題開發紀錄_與_Bug整理.txt`，這裡只列報告用的摘要。

### 6.1 一覽

| # | 階段 | 現象 | 根因 | 解法 |
|---|---|---|---|---|
| 1 | IP 打包 | Synthesis 找不到 module | component.xml 指向 IP 外的 `../src` | 檔案放進 IP 的 `hdl/`，路徑改為資料夾內 |
| 2 | IP 打包 | module 被當成標頭檔 | .v 項目帶 `isIncludeFile` | 取消 Is Include 後重新打包 |
| 3 | IP 打包 | 舊副本 / 舊路徑被使用 | imports 內有舊檔、repository 路徑舊 | 清除舊副本，Refresh IP Catalog |
| 4 | IP 打包 | 參數空白、ADDR_WIDTH = 4 | 頂層未被正確辨識，預設值太小 | 預設值改 6，Merge changes 重新辨識 |
| 5 | IP 打包 | Merge changes 無限循環（19-377） | File Groups 重複項目、參數不一致 | 清理後重新打包 |
| 6 | 合成 | 改了 RTL 但結果沒變 | OOC / ipshared 快取 | Reset Output Products，必要時刪 ipshared；用 `get_files -all` 驗證 |
| 7 | IP 打包 | 沒有 Upgrade Selected | 版本號沒變 | 每次 Re-Package 都升版 |
| 8 | BD | 不小心刪掉 design_1 | — | 先打包好 IP 再重建 BD，位址手動確認 |
| 9 | 上板 | 讀值全 0 / 用到舊 bitstream | `.bit` 與 `.hwh` 不成對 | 成對、同一次 build，上傳後重啟 kernel |
| 10 | 上板（XDOTP16） | 程式被截斷，PC 一路增加，後段全是 NOP | `imem.v` 先寫程式、後以 115 起的迴圈填 NOP，蓋掉第 115 ~ 135 字 | 先全部填 NOP 再寫程式；新增 `tb_imem_default` |
| 11 | 上板（IP 1.6） | PS 批次寫入 IMEM 後 word 0 變 NOP，L4 / L5 / L6a / L7 / L8 失敗 | `imem_bmg` 的 Enable Port Type = Always Enabled（與 `dmem_bmg` 唯一差異） | 改為 Use ENA / ENB Pin，重建 bitstream；IP 版本不變 |
| 12 | BD | BMG 深度改不動、Load Init File 灰色 | BRAM Controller 模式下深度由 controller 推導 | 改用 Stand Alone，手動設定深度與 COE |
| 13 | BD | 位址被重設、多出一顆 BMG | Validate 重設位址；Connection Automation 自動新增 | 手動設回位址（Tcl 檢查）、刪除多餘 BMG、controller 只留 1 個 BRAM 介面 |

### 6.2 三個最有代表性的案例

**Bug 10：模擬沒測到「合成進 bitstream 的內容」。**
`tb_board_program` 用 `readmemh` 從檔案載入程式，蓋過了 `imem.v` 的內建內容，因此沒測到內建預設值。
解法是新增 `tb_imem_default`，讓 `MEM_FILE` 指向不存在的檔案，只剩內建預設內容，並檢查前 136 字與其後的 NOP。
對舊寫法會失敗 21 項，修正後通過。
證明方式：把「前 115 字為新程式、其後全 NOP」餵給模擬，256 cycle 的 trace 與實板逐筆一致。

**Bug 11：只影響 word 0 的寫入錯誤，只有上板才會出現。**
- 現象：載入後讀回 `imem[0]` = 0x13（NOP），其餘正確。
- 縮小範圍：單獨寫 word 0 正常；批次寫入時，每個 16 位元組對齊的寫入都會多寫一份到 word 0，最後留下最後一次的值。
- 對照：DMEM 同樣批次寫入全部正確。用 Tcl 比對 `imem_ctrl` / `dmem_ctrl`、`imem_bmg` / `dmem_bmg` 所有 CONFIG 屬性，
  只有 `Enable_A` 不同（Always_Enabled vs Use_ENA_Pin）。
- 修正結果是實測確認的；機制為推測：BMG 沒有 ENA 腳位可接，controller 在傳輸第一個週期 we 已拉高、位址尚未更新時就造成誤寫。
- 模擬用的 BMG 行為模型沒有這種互動，所以模擬無法抓到。

**Bug 12 / 13：Vivado 工具行為。**
BRAM Controller 模式鎖住深度與初始化檔；Validate 與 Connection Automation 會改動位址與新增元件。
每次修改 BD 後，用 Tcl（`get_bd_addr_segs`、`get_bd_intf_nets`）重新檢查，比人工看畫面可靠。

---

## 7. 心得與教訓

1. **驗證要涵蓋實際上板的路徑。** 模擬若只從檔案載入程式，就漏掉合成進 bitstream 的預設內容（Bug 10）。
2. **用突變測試證明測試有效。** 故意改壞 RTL，看測試是否失敗。7 種突變全部被抓到。
3. **對稱元件用工具比對設定。** `imem` / `dmem` 理應對稱，用 Tcl 比對所有 CONFIG 屬性，比逐頁檢查畫面更快找到不對稱處（Bug 11）。
4. **改設計後用「不同於開機內容」的資料重新驗證。** 只跑開機程式會漏掉只影響特定位址的錯誤。
5. **黃金模型逐 cycle 比對 trace** 能直接定位問題，例如 Bug 10 一眼看出「前 115 字正確、之後全是 NOP」。
6. **擴充時先做最小改動版本。** XDOTP16 先做不累加版，並說明累加版的取捨（指令數 vs 硬體複雜度與時序）。
7. **IP 打包流程固定化可以省大量時間。** 覆蓋 `hdl/` → 確認 File Groups → 升版 Re-Package → Upgrade IP →
   Generate（Global）→ 用檔案內容確認主專案用到新檔 → Bitstream → 成對更新 bit / hwh。
8. **逐步改動、每步都能回歸。** Phase 4 拆成 Stage 1 / 2a / 2b，每一階段都有獨立的板測，出問題時範圍很小。

---

## 8. 限制與未來工作

### 已知限制

- **CPU 執行中由 PS 寫入 IMEM / DMEM 的行為尚未驗證**；目前只在 CPU reset 時載入程式（L8 只驗證了執行中「讀取」）。
- 記憶體只有 4 KB（IMEM、DMEM 各 1024 字），16 KB 版本尚未上板。
- 頻率上限 125 MHz 為依 WNS 的估算，未實際以更高時脈驗證。
- WHS 餘裕小（+0.015 ns），重跑 Implementation 可能浮動。
- 功耗為工具估算值（Confidence Medium），未實測。
- 尚未跑官方 riscv-arch-test；ISA 合規性目前由自建黃金模型與測試程式涵蓋。

### 未來工作

| 項目 | 說明 | 預期成本 / 風險 |
|---|---|---|
| FIR / kernel 週期數比較 | 同一段程式比較純 RV32I 與使用 XDOTP16 的 cycle 數，量化加速比 | 中；只需新增測試程式，不改硬體 |
| riscv-arch-test | 以官方測試套件證明 RV32I 合規 | 中高；需設定工具鏈與簽章比對 |
| 記憶體放大到 16 KB | 調整 BMG 深度與 controller 位址範圍，重跑 Vivado 與板測 | 中；要重跑完整流程 |
| XDOTP16 累加版 | 第三個讀取埠，修改 forwarding / hazard | 高；時序風險最大 |
| 執行中 PS 寫入記憶體 | 驗證 true dual port 在兩側同時存取下的行為 | 中 |

---

## 9. 參考檔案對照

| 內容 | 位置 |
|---|---|
| Vivado 報告（util / timing / power） | `docs/vivado_reports/ip1.5/`、`docs/vivado_reports/ip1.6/` |
| 完整 Bug 與時間線 | `docs/專題開發紀錄_與_Bug整理.txt` |
| IP 1.6 Vivado 操作清單 | `docs/PHASE4_STAGE2B_VIVADO.md` |
| IP 打包教訓 | `docs/IP_PACKAGING_LESSONS.md` |
| 實板測試報告（IP 1.6） | `pynq_5-stage-pipeline-CPU_TEST/cpu_test_report_v5_ip1.6_52of52.json` |
| 實板 Notebook | `pynq_5-stage-pipeline-CPU_TEST/RV32I_CPU_Board_Test_v5.ipynb` |
| COE 產生器 | `tools/gen_coe.py`；`bram_init/imem_board_program.coe` |
