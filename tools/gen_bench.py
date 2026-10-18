#!/usr/bin/env python3
"""
gen_bench.py  XDOTP16 效益量測：3 個 kernel x 4 種實作，產生程式 / 資料 / 預期結果。

Kernel（資料皆為有號 int16，結果為 int32）
  dot     內積，N = 128 個元素（每次迴圈處理 8 個元素，迭代 16 次）
  fir     FIR，8 taps、16 個輸出（y[n] = sum_k h[k] * x[n+k]）
  matmul  8x8 矩陣乘  C = A x B（B 以轉置 Bt 存放，C[i][j] = sum_k A[i][k] * Bt[j][k]）

實作（同一個核心、同一個排程器，只差指令選擇）
  S0  純標量，資料「未打包」（每個 int16 佔一個 32 位元字，lw + mul + add）。這是「不需要拆包」的標量下限。
  S1  標量 + 打包資料（兩個 int16 一個字，與 X 的資料格式相同），用 slli/srai 拆包（RV32I + MUL）
  S2  同 S1，但用 Zbb 的 sext_h 拆包（RV32I + MUL + Zbb）
  X   XDOTP16（打包資料，一條指令 = 2 個乘加）

公平性
  * 四種實作都經過同一個 list scheduler（只重排、不改指令；避開 load-use stall）。
  * 每次迴圈處理的元素數相同（dot 8 個、FIR 2 個輸出、matmul 每個內圈 2 個輸出）。
  * 打包資料的 FIR 需要「偶數對齊」與「奇數對齊」兩份 x（核心沒有 lh，無法對半字取值）；這份額外記憶體算在 S1/S2/X 身上。
  * 輸入資料由 PS 事先寫入 DMEM，載入時間不算在週期數內；kernel 內的 setup（pointer、hoist）算在內。

輸出（預設 ../sim/bench/）
  <kernel>_<var>.hex           程式（R=1，直接執行一次）
  <kernel>_<var>_rep<R>.hex    程式（重複 R 次，板上計時用；R=2/3 給模擬驗證線性、R=大值給板子）
  <kernel>.dmem.mem            DMEM 初始內容（1024 字；S0 與 packed 資料格式不同 → 檔名帶 _u / _p）
  <kernel>_<fmt>.expect.mem    DMEM 預期最終內容（黃金模型）
  bench_manifest.json          全部程式的中繼資料（spin PC、模型指令數、靜態大小…），供 tb / 報告 / Notebook 使用
"""
import os, sys, json, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv32i_model import asm, li, run, M32, s32, sx

# ----------------------------------------------------------------------------
# 指令表示與 list scheduler
# ----------------------------------------------------------------------------
R3 = {"add", "sub", "mul", "xdotp16"}
UN = {"sext_h"}
IMM = {"addi", "slli", "srai", "srli"}


class I:
    """一條指令 + 讀寫的暫存器（用於排程）"""
    def __init__(self, name, *a):
        self.name, self.a = name, a
        self.mem = None
        if name in R3:
            self.w, self.r = {a[0]}, {a[1], a[2]}
        elif name in UN or name in IMM:
            self.w, self.r = {a[0]}, {a[1]}
        elif name == "lw":
            self.w, self.r, self.mem = {a[0]}, {a[1]}, "L"
        elif name == "sw":
            self.w, self.r, self.mem = set(), {a[0], a[1]}, "S"
        elif name in ("bne", "beq", "blt", "bge"):
            self.w, self.r = set(), {a[0], a[1]}
        elif name == "lui":
            self.w, self.r = {a[0]}, set()
        else:
            raise ValueError(name)
        self.w.discard(0); self.r.discard(0)

    def enc(self):
        return asm(self.name, *self.a)


def schedule(block):
    """保持相依關係（RAW/WAR/WAW/記憶體順序）下重排，盡量避免「load 緊接著使用其結果」。"""
    n = len(block)
    deps = [set() for _ in range(n)]
    last_w, readers = {}, {}
    last_s, loads_since_s = None, []
    for i, ins in enumerate(block):
        for r in ins.r:
            if r in last_w: deps[i].add(last_w[r])
        for r in ins.w:
            if r in last_w: deps[i].add(last_w[r])
            deps[i] |= set(readers.get(r, []))
        if ins.mem == "L":
            if last_s is not None: deps[i].add(last_s)
        elif ins.mem == "S":
            if last_s is not None: deps[i].add(last_s)
            deps[i] |= set(loads_since_s)
        for r in ins.r: readers.setdefault(r, []).append(i)
        for r in ins.w: last_w[r] = i; readers[r] = []
        if ins.mem == "L": loads_since_s.append(i)
        if ins.mem == "S": last_s = i; loads_since_s = []
        deps[i].discard(i)
    done, out, prev = set(), [], None
    while len(out) < n:
        ready = [i for i in range(n) if i not in done and deps[i] <= done]
        pick = None
        for i in ready:
            if prev is not None and prev.name == "lw" and (prev.a[0] in block[i].r):
                continue
            pick = i; break
        if pick is None: pick = ready[0]
        done.add(pick); out.append(block[pick]); prev = block[pick]
    return out


class Pool:
    def __init__(self, regs): self.regs, self.k = list(regs), 0
    def alloc(self):
        r = self.regs[self.k % len(self.regs)]; self.k += 1; return r


def reduce_sum(prods, dest=None):
    """prods 內的暫存器相加（原地累加到第一個）；回傳 (指令, 結果暫存器)"""
    ins = []
    acc = prods[0]
    for p in prods[1:]:
        ins.append(I("add", acc, acc, p))
    return ins, acc


# ----------------------------------------------------------------------------
# 資料與預期結果
# ----------------------------------------------------------------------------
def rnd16(rng, n, lim=2000):
    return [rng.randint(-lim, lim) for _ in range(n)]


def pack(lo, hi):
    return ((hi & 0xFFFF) << 16) | (lo & 0xFFFF)


def pack_seq(v):                 # v[2i], v[2i+1]
    return [pack(v[2 * i], v[2 * i + 1]) for i in range(len(v) // 2)]


def pack_shift(v, n_words):      # v[2i+1], v[2i+2]
    return [pack(v[2 * i + 1], v[2 * i + 2]) for i in range(n_words)]


DOT_N = 128
FIR_T, FIR_M = 8, 16
MM_N = 8


class Kernel:
    pass


def make_dot(rng):
    A, B = rnd16(rng, DOT_N), rnd16(rng, DOT_N)
    k = Kernel(); k.name = "dot"; k.macs = DOT_N; k.iters = DOT_N // 8
    k.dmem = {"u": {}, "p": {}}
    k.layout = {"u": {"A": 16, "B": 16 + DOT_N, "RES": 0}, "p": {"A": 16, "B": 16 + DOT_N // 2, "RES": 0}}
    for i, v in enumerate(A): k.dmem["u"][16 + i] = v & M32
    for i, v in enumerate(B): k.dmem["u"][16 + DOT_N + i] = v & M32
    for i, w in enumerate(pack_seq(A)): k.dmem["p"][16 + i] = w
    for i, w in enumerate(pack_seq(B)): k.dmem["p"][16 + DOT_N // 2 + i] = w
    k.expect_words = {0: sum(a * b for a, b in zip(A, B)) & M32}
    k.outputs = {"RES": (0, 1)}
    return k


def make_fir(rng):
    h = rnd16(rng, FIR_T)
    x = rnd16(rng, FIR_M + FIR_T)                      # 24 個樣本
    y = [sum(h[kk] * x[n + kk] for kk in range(FIR_T)) & M32 for n in range(FIR_M)]
    k = Kernel(); k.name = "fir"; k.macs = FIR_M * FIR_T; k.iters = FIR_M // 2
    nw = FIR_M // 2 + FIR_T // 2 - 1 + 1                # 每份 x 11 個字（需要 m+j <= 10）
    k.dmem = {"u": {}, "p": {}}
    # u: h 在 16..23、x 在 24..47、y 在 48..63
    for i, v in enumerate(h): k.dmem["u"][16 + i] = v & M32
    for i, v in enumerate(x): k.dmem["u"][24 + i] = v & M32
    # p: h 在 16..19、xe 在 20..30、xo 在 31..41、y 在 48..63
    for i, w in enumerate(pack_seq(h)): k.dmem["p"][16 + i] = w
    xe = pack_seq(x)[:nw]
    xo = pack_shift(x + [0], nw)
    for i, w in enumerate(xe): k.dmem["p"][20 + i] = w
    for i, w in enumerate(xo): k.dmem["p"][20 + nw + i] = w
    k.layout = {"u": {"h": 16, "x": 24, "y": 48}, "p": {"h": 16, "xe": 20, "xo": 20 + nw, "y": 48}}
    k.expect_words = {48 + i: v for i, v in enumerate(y)}
    k.outputs = {"y": (48, FIR_M)}
    k.nw = nw
    return k


def make_matmul(rng):
    A = [rnd16(rng, MM_N) for _ in range(MM_N)]
    B = [rnd16(rng, MM_N) for _ in range(MM_N)]
    Bt = [[B[kk][j] for kk in range(MM_N)] for j in range(MM_N)]
    C = [[sum(A[i][kk] * B[kk][j] for kk in range(MM_N)) & M32 for j in range(MM_N)] for i in range(MM_N)]
    k = Kernel(); k.name = "matmul"; k.macs = MM_N ** 3; k.iters = MM_N * MM_N // 2
    k.dmem = {"u": {}, "p": {}}
    # u: A 在 16..79、Bt 在 80..143、C 在 160..223
    for i in range(MM_N):
        for j in range(MM_N):
            k.dmem["u"][16 + i * MM_N + j] = A[i][j] & M32
            k.dmem["u"][80 + i * MM_N + j] = Bt[i][j] & M32
    # p: A 在 16..47、Bt 在 48..79、C 在 160..223
    for i in range(MM_N):
        for w, v in enumerate(pack_seq(A[i])): k.dmem["p"][16 + i * 4 + w] = v
        for w, v in enumerate(pack_seq(Bt[i])): k.dmem["p"][48 + i * 4 + w] = v
    k.layout = {"u": {"A": 16, "Bt": 80, "C": 160}, "p": {"A": 16, "Bt": 48, "C": 160}}
    k.expect_words = {160 + i * MM_N + j: C[i][j] for i in range(MM_N) for j in range(MM_N)}
    k.outputs = {"C": (160, MM_N * MM_N)}
    return k


# ----------------------------------------------------------------------------
# 程式產生
# ----------------------------------------------------------------------------
POOL_REGS = list(range(1, 31))        # x31 保留給板上重複計時的計數器


def unpack_pair(var, w, T, tmp_lo=None):
    """w（打包字）→ (lo 暫存器, hi 暫存器)；回傳 (指令, lo, hi)"""
    lo, hi = T.alloc(), T.alloc()
    ins = []
    if var == "S1":
        ins += [I("slli", lo, w, 16), I("srai", lo, lo, 16)]
    else:                              # S2
        ins += [I("sext_h", lo, w)]
    ins += [I("srai", hi, w, 16)]
    return ins, lo, hi


def dot_prog(var, k):
    L = k.layout["u" if var == "S0" else "p"]
    pa, pb, end, acc = 1, 2, 3, 4
    T = Pool(range(5, 31))
    nb = DOT_N * 4 if var == "S0" else DOT_N * 2
    setup = [I("addi", pa, 0, 4 * L["A"]), I("addi", pb, 0, 4 * L["B"]),
             I("addi", end, pa, nb), I("addi", acc, 0, 0)]
    body = []
    if var == "S0":
        for u in range(8):
            a, b = T.alloc(), T.alloc()
            body += [I("lw", a, pa, 4 * u), I("lw", b, pb, 4 * u)]
            body += [I("mul", a, a, b), I("add", acc, acc, a)]
        step = 32
    elif var == "X":
        for u in range(4):
            a, b = T.alloc(), T.alloc()
            body += [I("lw", a, pa, 4 * u), I("lw", b, pb, 4 * u)]
            body += [I("xdotp16", a, a, b), I("add", acc, acc, a)]
        step = 16
    else:
        for u in range(4):
            a, b = T.alloc(), T.alloc()
            body += [I("lw", a, pa, 4 * u), I("lw", b, pb, 4 * u)]
            i1, alo, ahi = unpack_pair(var, a, T)
            i2, blo, bhi = unpack_pair(var, b, T)
            body += i1 + i2 + [I("mul", alo, alo, blo), I("mul", ahi, ahi, bhi),
                               I("add", acc, acc, alo), I("add", acc, acc, ahi)]
        step = 16
    body += [I("addi", pa, pa, step), I("addi", pb, pb, step)]
    body = schedule(body)
    br = I("bne", pa, end, -4 * len(body))
    tail = [I("sw", acc, 0, 4 * L["RES"])]
    return setup, body + [br], tail


def stream_dot(var, k, H, wregs, T):
    """計算 8 個元素的內積（H 為已 hoist 的運算元）。
       X/S1/S2：wregs = 4 個已載入的打包字；S0：wregs = 8 個已載入的樣本。回傳 (指令, 結果暫存器)"""
    ins = []
    prods = []
    if var == "X":
        for j, w in enumerate(wregs):
            ins.append(I("xdotp16", w, H[j], w)); prods.append(w)
    elif var == "S0":
        for j, w in enumerate(wregs):
            ins.append(I("mul", w, w, H[j])); prods.append(w)
    else:
        for j, w in enumerate(wregs):
            i1, lo, hi = unpack_pair(var, w, T)
            ins += i1 + [I("mul", lo, lo, H[2 * j]), I("mul", hi, hi, H[2 * j + 1])]
            prods += [lo, hi]
    s, res = reduce_sum(prods)
    return ins + s, res


def hoist(var, base_reg, off, T_setup, hregs):
    """從 base_reg+off 載入 8 個元素的 hoist 運算元到 hregs（X: 4 個字；S0: 8 個樣本；S1/S2: 8 個拆好的半字）"""
    ins = []
    if var == "X":
        for j in range(4): ins.append(I("lw", hregs[j], base_reg, off + 4 * j))
    elif var == "S0":
        for j in range(8): ins.append(I("lw", hregs[j], base_reg, off + 4 * j))
    else:
        for j in range(4):
            w = T_setup.alloc()
            ins.append(I("lw", w, base_reg, off + 4 * j))
            i1, lo, hi = None, hregs[2 * j], hregs[2 * j + 1]
            if var == "S1": ins += [I("slli", lo, w, 16), I("srai", lo, lo, 16)]
            else:           ins += [I("sext_h", lo, w)]
            ins.append(I("srai", hi, w, 16))
    return ins


def fir_prog(var, k):
    L = k.layout["u" if var == "S0" else "p"]
    H = list(range(5, 13)) if var != "X" else list(range(5, 9))   # hoisted 暫存器
    px, po, py, end = 1, 2, 3, 4                                  # S0 只用 px；其他 px=pe
    T = Pool(range(13, 31))
    Ts = Pool(range(13, 31))
    setup = []
    n_iter = FIR_M // 2
    setup += hoist(var, 0, 4 * L["h"], Ts, H)
    if var == "S0":
        setup += [I("addi", px, 0, 4 * L["x"]), I("addi", py, 0, 4 * L["y"]), I("addi", end, px, 8 * n_iter)]
    else:
        setup += [I("addi", px, 0, 4 * L["xe"]), I("addi", po, 0, 4 * L["xo"]),
                  I("addi", py, 0, 4 * L["y"]), I("addi", end, px, 4 * n_iter)]
    setup = schedule(setup)
    body = []
    if var == "S0":
        xr = [T.alloc() for _ in range(9)]
        for u in range(9): body.append(I("lw", xr[u], px, 4 * u))
        # 偶數輸出 y[2m]：sum_k h[k] x[k]；奇數輸出 y[2m+1]：sum_k h[k] x[k+1]（共用已載入的樣本）
        P = Pool(range(22, 31))
        for par in (0, 1):
            acc = None
            for kk in range(8):
                p = P.alloc()
                body.append(I("mul", p, xr[kk + par], H[kk]))
                if acc is None: acc = p
                else:
                    body.append(I("add", acc, acc, p))
                    # 釋放：p 之後會被 Pool 重用（WAR 由排程器處理）
            body.append(I("sw", acc, py, 4 * par))
        body += [I("addi", px, px, 8), I("addi", py, py, 8)]
        # S0 的 acc 暫存器在 pool 內循環；為避免 acc 被覆蓋，acc 在 sw 前不會再被分配（pool 9 個，一個 parity 最多占 1 個 acc + 輪替）
    else:
        for par, pr in ((0, px), (1, po)):
            wr = [T.alloc() for _ in range(4)]
            for j in range(4): body.append(I("lw", wr[j], pr, 4 * j))
            ins, res = stream_dot(var, k, H, wr, T)
            body += ins + [I("sw", res, py, 4 * par)]
        body += [I("addi", px, px, 4), I("addi", po, po, 4), I("addi", py, py, 8)]
    body = schedule(body)
    br = I("bne", px, end, -4 * len(body))
    return setup, body + [br], []


def matmul_prog(var, k):
    L = k.layout["u" if var == "S0" else "p"]
    rowb = 32 if var == "S0" else 16
    H = list(range(8, 16)) if var != "X" else list(range(8, 12))
    pa, enda, pb, endb, pc = 1, 2, 3, 4, 5
    T = Pool([6, 7] + list(range(16, 31)))
    Ts = Pool([6, 7] + list(range(16, 31)))
    setup = [I("addi", pa, 0, 4 * L["A"]), I("addi", enda, pa, MM_N * rowb),
             I("addi", endb, 0, 4 * L["Bt"] + MM_N * rowb), I("addi", pc, 0, 4 * L["C"])]
    outer = hoist(var, pa, 0, Ts, H)
    outer = schedule(outer) + [I("addi", pb, 0, 4 * L["Bt"])]
    inner = []
    for u in range(2):
        nreg = 8 if var == "S0" else 4
        wr = [T.alloc() for _ in range(nreg)]
        for j in range(nreg): inner.append(I("lw", wr[j], pb, u * rowb + 4 * j))
        ins, res = stream_dot(var, k, H, wr, T)
        inner += ins + [I("sw", res, pc, 4 * u)]
    inner += [I("addi", pb, pb, 2 * rowb), I("addi", pc, pc, 8)]
    inner = schedule(inner)
    inner_br = I("bne", pb, endb, -4 * len(inner))
    outer_tail = [I("addi", pa, pa, rowb)]
    return setup, outer, inner + [inner_br], outer_tail, enda


def assemble(kname, var, k, rep=None):
    """回傳 (words, spin_pc)。rep=None：直接執行一次；rep=R：重複 R 次（x31 為計數器）"""
    words = []
    top_idx = 0
    if rep is not None:
        words += li(31, rep)
        top_idx = len(words)
    if kname == "dot":
        setup, body, tail = dot_prog(var, k)
        words += [i.enc() for i in setup + body + tail]
    elif kname == "fir":
        setup, body, tail = fir_prog(var, k)
        words += [i.enc() for i in setup + body + tail]
    else:
        setup, outer, inner, outer_tail, enda = matmul_prog(var, k)
        words += [i.enc() for i in setup]
        o_start = len(words)
        words += [i.enc() for i in outer + inner + outer_tail]
        # 外圈分支：回到 outer 開頭
        n_outer = len(outer) + len(inner) + len(outer_tail)
        words.append(asm("bne", 1, enda, -4 * n_outer))
    if rep is not None:
        n = len(words) - top_idx
        words.append(asm("addi", 31, 31, -1))
        words.append(asm("bne", 31, 0, -4 * (n + 1)))
    spin = 4 * len(words)
    words.append(asm("jal", 0, 0))
    return words, spin


def write_hex(path, words, depth=1024):
    with open(path, "w") as f:
        for w in list(words) + [0x13] * (depth - len(words)):
            f.write("%08x\n" % (w & M32))


def write_mem(path, d, depth=1024):
    with open(path, "w") as f:
        for i in range(depth): f.write("%08x\n" % (d.get(i, 0) & M32))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sim", "bench")
    os.makedirs(out, exist_ok=True)
    rng = random.Random(20261018)
    kernels = {"dot": make_dot(rng), "fir": make_fir(rng), "matmul": make_matmul(rng)}
    manifest = {"kernels": {}, "programs": []}
    for kname, k in kernels.items():
        manifest["kernels"][kname] = {"macs": k.macs, "iters": k.iters, "layout": k.layout,
                                      "outputs": k.outputs, "expect_words": {str(a): v for a, v in k.expect_words.items()}}
        for fmt in ("u", "p"):
            write_mem(os.path.join(out, "%s_%s.dmem.mem" % (kname, fmt)), k.dmem[fmt])
            full = dict(k.dmem[fmt]); full.update(k.expect_words)
            write_mem(os.path.join(out, "%s_%s.expect.mem" % (kname, fmt)), full)
            manifest["kernels"][kname].setdefault("dmem_init", {})[fmt] = {str(a): v for a, v in k.dmem[fmt].items()}
    for kname, k in kernels.items():
        for var in ("S0", "S1", "S2", "X"):
            fmt = "u" if var == "S0" else "p"
            words, spin = assemble(kname, var, k)
            # 以黃金模型驗證：結果必須等於獨立算出的預期值，且不能有 illegal
            full = dict(k.dmem[fmt]); full.update(k.expect_words)
            r = run(words, max_steps=2_000_000, mem0=k.dmem[fmt])
            assert not r["illegal"], (kname, var, "illegal")
            assert r["pc"] == spin, (kname, var, hex(r["pc"]), hex(spin))
            for a, v in k.expect_words.items():
                assert r["mem"].get(a, 0) == v, (kname, var, "word", a, hex(r["mem"].get(a, 0)), hex(v))
            # 輸入區不可被改動
            for a, v in k.dmem[fmt].items():
                if a not in k.expect_words:
                    assert r["mem"].get(a, 0) == v, (kname, var, "input modified", a)
            base = "%s_%s" % (kname, var)
            write_hex(os.path.join(out, base + ".hex"), words)
            prog = {"kernel": kname, "var": var, "fmt": fmt, "file": base + ".hex", "words": len(words), "spin_pc": spin,
                    "n_instr": r["n_instr"], "n_taken": r["n_taken"], "n_loads": r["n_loads"], "reps": {}}
            for R in (2, 3):
                rw, rspin = assemble(kname, var, k, rep=R)
                rr = run(rw, max_steps=5_000_000, mem0=k.dmem[fmt])
                assert not rr["illegal"] and rr["pc"] == rspin
                for a, v in k.expect_words.items():
                    assert rr["mem"].get(a, 0) == v, (kname, var, "rep", R, a)
                write_hex(os.path.join(out, "%s_rep%d.hex" % (base, R)), rw)
                prog["reps"][str(R)] = {"file": "%s_rep%d.hex" % (base, R), "spin_pc": rspin, "words": len(rw),
                                         "n_instr": rr["n_instr"]}
            manifest["programs"].append(prog)
            print("%-6s %-2s  %3d words  %5d instr executed  %4d taken  %4d lw" % (
                kname, var, len(words), r["n_instr"], r["n_taken"], r["n_loads"]))
    with open(os.path.join(out, "bench_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print("OK -> %s" % os.path.abspath(out))


if __name__ == "__main__":
    main()
