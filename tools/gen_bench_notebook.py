#!/usr/bin/env python3
"""
gen_bench_notebook.py  產生 pynq_5-stage-pipeline-CPU_TEST/RV32I_CPU_Benchmark.ipynb
  資料來源：sim/bench/bench_manifest.json（gen_bench.py）+ sim/bench/bench_results.json（run_bench.py 的 RTL 模擬週期數）
  Notebook 是自包含的：程式、輸入資料、預期結果與模擬週期數都嵌在 cell ② 的 JSON 裡，板上不需要 Python 黃金模型。
"""
import json, os, sys, uuid

here = os.path.dirname(os.path.abspath(__file__))
bench = os.path.join(here, "..", "sim", "bench")
out_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "pynq_5-stage-pipeline-CPU_TEST", "RV32I_CPU_Benchmark.ipynb")


def read_hex(path):
    ws = [int(l, 16) for l in open(path).read().split()]
    while ws and ws[-1] == 0x13:           # 去掉尾端 NOP 補滿（Notebook 載入時會自己補）
        ws.pop()
    return ws


man = json.load(open(os.path.join(bench, "bench_manifest.json")))
res = {(r["kernel"], r["var"]): r for r in json.load(open(os.path.join(bench, "bench_results.json")))}

data = {"kernels": {}, "programs": []}
for kn, k in man["kernels"].items():
    data["kernels"][kn] = {"macs": k["macs"], "outputs": k["outputs"], "dmem_init": k["dmem_init"],
                           "expect_words": k["expect_words"]}
for p in man["programs"]:
    r = res[(p["kernel"], p["var"])]
    data["programs"].append({
        "kernel": p["kernel"], "var": p["var"], "fmt": p["fmt"], "spin_pc": p["spin_pc"],
        "words": read_hex(os.path.join(bench, p["file"])),
        "rep_words": read_hex(os.path.join(bench, p["reps"]["3"]["file"])),
        "rep_spin_pc": p["reps"]["3"]["spin_pc"],
        "sim_cycles": r["cycles"], "sim_rep_period": r["rep_period"], "n_instr": p["n_instr"]})
data_json = json.dumps(data, separators=(",", ":"))


def cell(kind, src):
    c = {"cell_type": kind, "id": uuid.uuid4().hex[:8], "metadata": {}, "source": src.splitlines(True)}
    if kind == "code":
        c["execution_count"] = None
        c["outputs"] = []
    return c


MD = """# RV32I CPU — XDOTP16 效益量測（PYNQ-ZU 板上版）
同一顆 CPU（IP 1.6，bitstream 不用改）跑 3 個 kernel × 4 種實作，驗證結果並量測週期數。

| 代號 | 實作 |
|---|---|
| S0 | 純標量，資料未打包（每個 int16 佔一個字，lw + mul + add） |
| S1 | 標量 + 打包資料，用 slli / srai 拆包（RV32I + MUL） |
| S2 | 標量 + 打包資料，用 Zbb sext_h 拆包（RV32I + MUL + Zbb） |
| X  | XDOTP16 + 打包資料（一條指令 = 2 個乘加） |

Kernel：`dot`（128 元素內積）、`fir`（8 taps、16 輸出）、`matmul`（8×8 int16 矩陣乘）。

**做法**
1. cell ④ **正確性**：PS 寫入資料與程式 → run → 讀回整塊 DMEM（1024 字）與預期結果逐字比對。
2. cell ⑤ **計時**：同一支 kernel 包在「重複 R 次」的迴圈裡，用 PS 端 `time.perf_counter()` 量總時間，
   換算成每次重複的 cycle 數（= 時間 × 時脈 ÷ R），與 RTL 模擬的週期數比較。R 取使總時間約 0.5 秒，
   所以 PS 讀 PC 的延遲（微秒等級）可以忽略。
3. cell ⑥ 結果總表與報告檔。

需要：IP 1.6 的 bitstream（FEATURE bit4）；cell ① 的 IMEM_BASE / DMEM_BASE 與 Address Editor 一致。
"""

C1 = '''# ① 載入 Overlay 與 MMIO（重新上傳 bitstream 後請先 Kernel → Restart）
import time, json
import numpy as np
from pynq import Overlay, MMIO

BIT  = "/home/xilinx/jupyter_notebooks/design_1_wrapper.bit"   # 同資料夾需有同名 .hwh
BASE = 0x80000000
SIZE = 0x10000
IMEM_BASE, DMEM_BASE, BRAM_SIZE = 0x80010000, 0x80020000, 0x1000

ol   = Overlay(BIT)
mmio = MMIO(BASE, SIZE)
imem = MMIO(IMEM_BASE, BRAM_SIZE)
dmem = MMIO(DMEM_BASE, BRAM_SIZE)

CTRL, PC, R_FEAT = 0x00, 0x04, 0x2C
feat = mmio.read(R_FEAT)
print("FEATURE = 0x%X" % feat, "（需要 bit4 = 外部 BRAM、bit1 = MUL、bit2 = XDOTP16）")
assert feat & 0x10 and feat & 0x2 and feat & 0x4, "bitstream 不是 IP 1.6（FEATURE 應為 0x17）"

# PL 時脈：Vivado 時序是以 100 MHz 簽核。PYNQ-ZU 板上 PL0 的來源是 IOPLL（≈1500 MHz），套用 .hwh 的 ÷8 後約 187.5 MHz，
# 並不是 Block Design 裡設定的 100 MHz（診斷見 docs/XDOTP16_BENCHMARK.md）。這裡明確設回 100 MHz，讓測試落在時序簽核範圍內。
from pynq import Clocks
TARGET_CLK_MHZ = 100.0      # None = 不改，維持 PYNQ 目前的時脈
mmio.write(0x00, 0x0)       # 改時脈前先讓 CPU 留在 reset
if TARGET_CLK_MHZ is not None:
    Clocks.fclk0_mhz = TARGET_CLK_MHZ
CLK_MHZ = float(Clocks.fclk0_mhz)
print("PL 時脈（fclk0）= %.3f MHz" % CLK_MHZ)
assert TARGET_CLK_MHZ is None or abs(CLK_MHZ - TARGET_CLK_MHZ) / TARGET_CLK_MHZ < 0.02, "PL 時脈沒有設成 %s MHz（讀回 %.3f）" % (TARGET_CLK_MHZ, CLK_MHZ)
'''

C2 = '''# ② benchmark 資料（由 tools/gen_bench_notebook.py 產生：程式、輸入、預期結果、RTL 模擬週期數）
DATA = json.loads(r\'\'\'%s\'\'\')
KERNELS  = DATA["kernels"]
PROGRAMS = DATA["programs"]
print("kernel：%%s；程式 %%d 支" %% (", ".join(KERNELS), len(PROGRAMS)))
''' % data_json

C3 = '''# ③ 工具函式
NOP, WORDS, M32 = 0x00000013, 1024, 0xFFFFFFFF
R_SPIN_CONFIRM = 4          # 連續 4 次讀到 PC 在 spin 位址附近才算結束（避免 wrong-path 預取造成的誤判）

def cpu_reset(): mmio.write(CTRL, 0x0)
def cpu_run():   mmio.write(CTRL, 0x1)

def bram_write(mm, words):
    arr = np.array([w & M32 for w in words], dtype=np.uint32)
    try:    mm.array[:len(arr)] = arr
    except Exception:
        for i, w in enumerate(arr): mm.write(4 * i, int(w))

def bram_read(mm, n=WORDS):
    try:    return [int(x) for x in mm.array[:n]]
    except Exception:
        return [mm.read(4 * i) for i in range(n)]

def li_words(rd, v):
    v &= M32
    lo = ((v & 0xFFF) ^ 0x800) - 0x800
    hi = ((v - lo) & M32) >> 12
    return [(hi << 12) | (rd << 7) | 0x37, ((lo & 0xFFF) << 20) | (rd << 15) | (rd << 7) | 0x13]

def dmem_image(kernel, fmt):
    img = [0] * WORDS
    for a, v in KERNELS[kernel]["dmem_init"][fmt].items(): img[int(a)] = v
    return img

def expected_image(kernel, fmt):
    img = dmem_image(kernel, fmt)
    for a, v in KERNELS[kernel]["expect_words"].items(): img[int(a)] = v
    return img

def load(words, img):
    """CPU 放在 reset：清 DMEM + 寫入資料 + 寫入程式（其餘補 NOP）"""
    cpu_reset(); time.sleep(0.001)
    bram_write(dmem, img)
    bram_write(imem, list(words) + [NOP] * (WORDS - len(words)))

def wait_spin(spin_pc, timeout=60.0):
    """輪詢 PC，直到連續 R_SPIN_CONFIRM 次都在 spin 附近；回傳經過秒數（從呼叫起算）或 None（逾時）"""
    near = {spin_pc, spin_pc + 4, spin_pc + 8}
    t0 = time.perf_counter(); ok = 0
    while True:
        if mmio.read(PC) in near:
            ok += 1
            if ok >= R_SPIN_CONFIRM: return time.perf_counter() - t0
        else:
            ok = 0
            if time.perf_counter() - t0 > timeout: return None

RESULTS = []
def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))
    print(("[PASS] " if ok else "[FAIL] ") + name + (("  —  " + detail) if detail else ""))
    return ok

def diff_words(hw, exp):
    return [(i, hw[i], exp[i]) for i in range(WORDS) if hw[i] != exp[i]]
'''

C4 = '''# ④ 正確性：每支程式單次執行 → 讀回整塊 DMEM 與預期逐字比對
CORRECT = {}
for p in PROGRAMS:
    k, v, f = p["kernel"], p["var"], p["fmt"]
    exp = expected_image(k, f)
    load(p["words"], dmem_image(k, f))
    cpu_run()
    t = wait_spin(p["spin_pc"])
    hw = bram_read(dmem)
    bad = diff_words(hw, exp)
    ok = (t is not None) and not bad
    CORRECT[(k, v)] = ok
    check("%-6s %-2s 結果正確" % (k, v), ok,
          "逾時" if t is None else ("DMEM 不同字數=%d，前幾個 (idx,實際,預期)=%s" % (len(bad), [(i, hex(a), hex(b)) for i, a, b in bad[:3]]) if bad else "整塊 DMEM 一致"))
    cpu_reset()
'''

C5 = '''# ⑤ 計時：kernel 重複 R 次，量總時間，換算每次重複的 cycle 數，與 RTL 模擬比較
TARGET_CYCLES = 50_000_000          # 目標總 cycle 數 ≈ 0.5 秒（100 MHz）
TIMING = {}
for p in PROGRAMS:
    k, v, f = p["kernel"], p["var"], p["fmt"]
    period = p["sim_rep_period"]
    R = max(2, int(round(TARGET_CYCLES / period)))
    words = li_words(31, R) + p["rep_words"][2:]          # 前 2 個字是 li x31, R（R 在這裡換成大值）
    exp = expected_image(k, f)
    load(words, dmem_image(k, f))
    t0 = time.perf_counter()
    cpu_run()
    t = wait_spin(p["rep_spin_pc"], timeout=120.0)
    t1 = time.perf_counter()
    elapsed = (t1 - t0)
    hw = bram_read(dmem)
    bad = diff_words(hw, exp)
    cpu_reset()
    cyc_per_rep = elapsed * CLK_MHZ * 1e6 / R if t is not None else float("nan")
    ratio = cyc_per_rep / period
    TIMING[(k, v)] = dict(R=R, elapsed=elapsed, cyc_per_rep=cyc_per_rep, sim_period=period, ratio=ratio, ok=(t is not None and not bad))
    check("%-6s %-2s 計時：R=%d，%.3f s → %.1f cycles/rep（模擬 %d，比值 %.4f）" % (k, v, R, elapsed, cyc_per_rep, period, ratio),
          t is not None and not bad and abs(ratio - 1) < 0.02,
          "DMEM 不同字數=%d" % len(bad) if bad else "")
'''

C6 = '''# ⑥ 結果總表與報告檔
print("=" * 92)
print("%-7s %-3s %9s %9s %9s %9s %9s" % ("kernel", "var", "模擬cyc", "板上cyc", "比值", "vs S0", "vs S2"))
by = {(p["kernel"], p["var"]): p for p in PROGRAMS}
rows = []
for k in KERNELS:
    for v in ("S0", "S1", "S2", "X"):
        p = by[(k, v)]
        tm = TIMING.get((k, v), {})
        s0 = by[(k, "S0")]["sim_cycles"]; s2 = by[(k, "S2")]["sim_cycles"]
        rows.append({"kernel": k, "var": v, "sim_cycles": p["sim_cycles"], "n_instr": p["n_instr"],
                     "sim_rep_period": p["sim_rep_period"], "board_cycles_per_rep": tm.get("cyc_per_rep"),
                     "board_over_sim": tm.get("ratio"), "speedup_vs_S0": s0 / p["sim_cycles"], "speedup_vs_S2": s2 / p["sim_cycles"],
                     "correct": CORRECT.get((k, v)), "R": tm.get("R"), "elapsed_s": tm.get("elapsed")})
        r = rows[-1]
        print("%-7s %-3s %9d %9s %9s %8.2fx %8.2fx" % (k, v, r["sim_cycles"],
              "%.1f" % r["board_cycles_per_rep"] if r["board_cycles_per_rep"] else "-",
              "%.4f" % r["board_over_sim"] if r["board_over_sim"] else "-", r["speedup_vs_S0"], r["speedup_vs_S2"]))
print("=" * 92)
n_pass = sum(1 for _, ok, _ in RESULTS if ok)
print("總計：%d / %d 通過  →  %s" % (n_pass, len(RESULTS), "ALL PASS ✅" if n_pass == len(RESULTS) else "有失敗項目 ❌"))
print("註：模擬cyc = 單次執行（RTL 模擬）；板上cyc = 重複執行的每次週期（含重複迴圈的 addi + bne 與 taken-branch 的 2 個 bubble），與模擬的『rep 週期』比較。")

report = {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "clk_mhz": CLK_MHZ,
          "results": [{"test": n, "pass": ok, "detail": d} for n, ok, d in RESULTS], "rows": rows}
with open("/home/xilinx/jupyter_notebooks/cpu_bench_report.json", "w") as fh:
    json.dump(report, fh, indent=1)
print("報告已存到 cpu_bench_report.json")
'''

nb = {"cells": [cell("markdown", MD), cell("code", C1), cell("code", C2), cell("code", C3),
                cell("code", C4), cell("code", C5), cell("code", C6)],
      "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"}},
      "nbformat": 4, "nbformat_minor": 5}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(nb, f, ensure_ascii=False, indent=1)
print("OK ->", os.path.abspath(out_path), "(%d KB)" % (os.path.getsize(out_path) // 1024))
