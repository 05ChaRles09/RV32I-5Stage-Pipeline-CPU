# riscv-arch-test 合規測試

本文件說明如何以官方 [riscv-arch-test](https://github.com/riscv-non-isa/riscv-arch-test) 測試套件驗證本 CPU 的 ISA 合規性，以及實際結果。

## 1. 結果摘要

| 套件 | 測試數 | PASS | 預期 FAIL（核心未實作） | 參考簽章來源 |
|---|---|---|---|---|
| RV32I | 38 | 32 | 6 | 官方 `reference_output`（old-framework-2.x） |
| RV32M | 8 | 1（`mul-01`） | 7 | 官方 `reference_output`（old-framework-2.x） |
| Zbb | 18 | 18 | 0 | QEMU 8.2.2（見 §4） |
| **合計** | **64** | **51** | **13** | |

- **核心支援的 51 項測試全部通過**（簽章逐字相同）。
- 13 項「預期 FAIL」都是本專題**刻意不實作**的指令（見 §3），不是 bug。
- `fence-01` 通過，過程中 illegal 旗標為 1：`fence` 目前被當成 NOP 執行（illegal-as-NOP 設計），不影響簽章。
- 最長測試 `bgeu-01` 為 10463 cycles；51 項通過測試共比對 18512 個簽章字組。

## 2. 如何重現

需要的工具（Debian/Ubuntu）：

```bash
sudo apt install gcc-riscv64-unknown-elf qemu-system-misc iverilog
```

取得測試套件（**不放進本 repo**，體積超過 1 GB）：

```bash
git clone --depth 1 --branch old-framework-2.x https://github.com/riscv-non-isa/riscv-arch-test <dir2>
git clone --depth 1 --branch 3.9.1            https://github.com/riscv-non-isa/riscv-arch-test <dir3>
```

執行（約 4 分鐘）：

```bash
python3 tools/run_archtest.py --arch-test <dir2> --arch-test3 <dir3> --validate-qemu
# 只跑單一測試：  --only add-01
# 結果：arch_test/results/summary.json（work/ 內為中間檔，已列入 .gitignore）
```

突變測試（驗證 arch-test 真的抓得到 RTL 錯誤，見 §5）：

```bash
python3 tools/archtest_mutation.py --arch-test <dir2> --arch-test3 <dir3>
```

## 3. 不支援的 13 項測試

| 測試 | 原因 |
|---|---|
| `lb` / `lbu` / `lh` / `lhu` `-align-01` | 核心只有 `lw` / `sw`，沒有位元組／半字載入 |
| `sb` / `sh` `-align-01` | 同上，沒有位元組／半字儲存 |
| `mulh` / `mulhsu` / `mulhu` | RV32M 只實作低 32 位元的 `MUL` |
| `div` / `divu` / `rem` / `remu` | 沒有除法器 |

這些指令在核心中被視為 illegal 並當 NOP 執行，因此測試簽章必然與參考不同。列為 Roadmap 的後續項目。

## 4. 測試方法

### 4.1 目標環境（`arch_test/target/`）
- `model_test.h`：`RVMODEL_HALT` 為 `self_loop: j self_loop`；`begin_signature` / `end_signature` 標出簽章區段。
- `link.ld`：Harvard 配置，IMEM 位於 `0x0`（2 MB），DMEM（`.data`）位於 `0x200000`（2 MB）。
- `wrap/arch_test.h`：包裝官方標頭，補上 `LAX` 巨集，繞過 GNU as 13 對 `la x0, …` 的拒絕（`jalr-01` 需要）。
- `link_qemu.ld`：只給 QEMU 參考執行使用（RAM 在 `0x80000000`）。

### 4.2 模擬流程
`sim/tb_archtest.v` 例化 `rv32i_pipeline`（`IMEM/DMEM_ADDR_WIDTH=21`，內部記憶體）。程式載入後執行，直到 `ex_pc` 到達 `self_loop`，再多跑 30 個 cycle 讓流水線內的 store 完成，最後把簽章區段傾印出來，由 `run_archtest.py` 與參考簽章逐字比對。

### 4.3 Zbb 的參考簽章
官方 2.x 分支沒有 B 擴充的參考輸出，3.9.1 版本有測試但沒有參考輸出。因此 Zbb 以 **QEMU 8.2.2**（`-M virt -cpu rv32,zbb=true`）執行同一份 ELF，並用 monitor 的 `pmemsave` 傾印簽章作為獨立參考。

為證明 QEMU 值得信任，`--validate-qemu` 會對 2.x 的 I/M 測試同樣產生 QEMU 簽章，與官方 `reference_output` 比對：**46 / 46 完全相同**。

## 5. 突變測試：arch-test 的偵測能力

對 RTL 副本逐一植入錯誤，確認 arch-test 會失敗：

| 植入的錯誤 | 結果 | 失敗的測試 |
|---|---|---|
| `SUB` 改成 `ADD` | 抓到 | `sub-01` |
| `SRA` 改成邏輯右移 | 抓到 | `sra-01`, `srai-01` |
| `SLTU` 改成有號比較 | 抓到 | `sltu-01`, `sltiu-01` |
| `SLL` 位移量只取 4 位元 | 抓到 | `sll-01`, `slli-01` |
| `MUL` 改成 `A+B` | 抓到 | `mul-01` |
| `BLTU` 改成有號比較 | 抓到 | `bltu-01` |
| `BGE` 改成 `BGT` | 抓到 | `bge-01` |
| forwarding：MEM/WB 轉送 A 失效 | 抓到 | `add-01`, `and-01`, `xor-01` |
| **load-use stall 關閉** | **沒抓到** | —— |
| Zbb `clz` 結果錯一位 | 抓到 | `clz-01` |

**9 / 10 被抓到。** 沒抓到的 load-use stall 並不代表 stall 沒用：riscv-arch-test 是 *ISA 層級*測試，每個測試的資料相依大多已被指令間隔隔開，不會刻意製造「load 後立刻使用」的 hazard。這類流水線 hazard 由本專題自建的 `tb_bram_timing`（關閉 stall 時 5 個失敗）與 `tb_zbb_prog`（48 個失敗）負責涵蓋。

## 6. 限制
- **只在模擬中執行**，使用 2 MB 內部記憶體；尚未在 4 KB 的實板 BRAM 上跑（程式與簽章都超過 4 KB），待 Roadmap 的 16 KB 記憶體之後再評估。
- 屬 ISA 層級合規，不涵蓋 AXI 介面、時序與流水線 hazard 的所有組合（這些由自建 testbench 與實板測試覆蓋）。
- B 擴充只測 Zbb 的 18 項（RV32 適用者）；Zba / Zbs / Zbc 核心未實作。
- Zbb 的參考簽章來自 QEMU，而非官方 reference_output。
- 自訂指令 `XDOTP16` 不在 arch-test 範圍內，由自建 testbench / 實板基準驗證。
