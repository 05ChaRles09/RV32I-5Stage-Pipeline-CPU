#!/usr/bin/env python3
"""
gen_tests.py  產生 Zbb 測試資料，直接輸出到 sim/（平面檔案，供 Vivado xsim 的 $readmemh 讀取）。
**一般使用 Vivado 跑模擬時不需要執行這個腳本**：產生好的檔案已經放在 sim/ 裡。
只有想改變測試內容（新增指令、換 seed）時才需要重新產生：  python3 tools/gen_tests.py [--seeds N]

輸出（皆為 hex 文字檔）
  sim/zbb_vectors.mem       tb_zbb_unit.v   每筆 4 個字：op a b expected
  sim/zbb_prog.hex          tb_zbb_prog.v   NP 支程式，每支固定 1024 字（不足以 NOP 補齊），依序串接
  sim/zbb_prog_expect.mem   tb_zbb_prog.v   NP 組預期狀態，每組 1056 字：x0..x31 + dmem[0..1023]
程式內容 = Zbb + MUL directed（每個指令 × 邊界值）+ 隨機 RV32I/Zbb 程式（含 forwarding / load-use / 分支 flush）
"""
import argparse, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv32i_model import *

CORNERS = [0, 1, 2, 3, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFF, 0xFFFFFFFE, 0x0000FFFF, 0xFFFF0000,
           0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000, 0x12345678, 0xDEADBEEF, 0x00000080, 0x00008000, 0x55555555, 0xAAAAAAAA]
IMEM_WORDS = 1024     # imem.v 以 addr[11:2] 索引 -> 實際 1024 字
MEMW = 1024           # dmem.v 同上
NOP = 0x00000013


def gen_vectors(path, rnd):
    n = 0
    with open(path, "w") as f:
        for opi, name in enumerate(ZBB_OPS):
            pairs = [(a, b) for a in CORNERS for b in CORNERS]
            pairs += [(rnd.getrandbits(32), rnd.getrandbits(32)) for _ in range(300)]
            if name in ("rol", "ror"):
                pairs += [(rnd.getrandbits(32), s) for s in range(32) for _ in range(2)]
                pairs += [(c, s) for c in CORNERS for s in range(32)]
            if name in ("clz", "ctz", "cpop"):
                pairs += [(1 << i, 0) for i in range(32)] + [((1 << i) - 1, 0) for i in range(33)]
                pairs += [((M32 << i) & M32, 0) for i in range(33)]
            for a, b in pairs:
                f.write("%02x %08x %08x %08x\n" % (opi, a, b, ZBB_REF[name](a, b)))
                n += 1
    return n


def gen_directed():
    """每個 Zbb 指令 × 邊界運算元：x1=a, x2=b → x3=op → sw x3,0(x4); x4+=4；切成多支 <= 900 指令的程式"""
    tests = []
    for name in ZBB_OPS:
        pairs = [(a, b) for a in CORNERS[:9] for b in ([0, 1, 31, 32, 0x80000000, 0xFFFFFFFF] if name in ("rol", "ror") else CORNERS[:5])]
        if name not in ZBB_BINARY: pairs = [(a, 0) for a in CORNERS]
        for a, b in pairs:
            tests.append(li(1, a) + (li(2, b) if name in ZBB_BINARY else []) +
                         [asm(name, 3, 1, 2) if name in ZBB_BINARY else asm(name, 3, 1)])
    for sh in range(32):
        tests.append(li(1, 0x80000001 ^ (sh * 0x01010101)) + [asm("rori", 3, 1, sh)])
    for a in CORNERS:                                  # RV32M MUL × 邊界運算元
        for b in CORNERS:
            tests.append(li(1, a) + li(2, b) + [asm("mul", 3, 1, 2)])
    chunks, cur = [], []
    for t in tests:
        if len(cur) + len(t) + 2 > 900:
            chunks.append(cur); cur = []
        cur += t + [asm("sw", 3, 4, 0), asm("addi", 4, 4, 4)]
    chunks.append(cur)
    return [("zbb_directed_%d" % k, body + [asm("jal", 0, 0)]) for k, body in enumerate(chunks)]


def gen_random(seed, n_instr=240):
    rnd = random.Random(seed)
    prog = []
    for r in range(1, 16):
        prog += li(r, rnd.choice(CORNERS + [rnd.getrandbits(32)] * 3))
    recent = list(range(1, 16))
    pick_src = lambda: rnd.choice(recent[-3:]) if rnd.random() < 0.6 else rnd.randrange(0, 16)
    base_r, base_i = list(BASE_R) + list(M_R), list(BASE_I)   # M_R = mul
    while len(prog) < 30 + n_instr:
        rd = rnd.randrange(1, 16)
        k = rnd.random()
        if k < 0.20:   ins = asm(rnd.choice(base_r), rd, pick_src(), pick_src())
        elif k < 0.30: ins = asm(rnd.choice(base_i), rd, pick_src(), rnd.randrange(-2048, 2048))
        elif k < 0.38: ins = asm(rnd.choice(["slli", "srli", "srai", "rori"]), rd, pick_src(), rnd.randrange(32))
        elif k < 0.58: ins = asm(rnd.choice(ZBB_BINARY), rd, pick_src(), pick_src())
        elif k < 0.78: ins = asm(rnd.choice(ZBB_UNARY), rd, pick_src())
        elif k < 0.85: ins = asm("lw", rd, 0, 4 * rnd.randrange(16))
        elif k < 0.91: ins = asm("sw", pick_src(), 0, 4 * rnd.randrange(16))
        elif k < 0.97:                                        # 向前跳過一條指令：測 flush
            prog.append(asm(rnd.choice(["beq", "bne", "blt", "bge", "bltu", "bgeu"]), pick_src(), pick_src(), 8))
            prog.append(asm(rnd.choice(ZBB_BINARY + base_r), rnd.randrange(1, 16), pick_src(), pick_src()))
            recent.append(rd); continue
        else:          ins = asm("lui", rd, rnd.getrandbits(20))
        prog.append(ins); recent.append(rd)
    prog.append(asm("jal", 0, 0))
    return ("rand_%d" % seed, prog)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sim"))
    ap.add_argument("--seeds", type=int, default=30)
    a = ap.parse_args()
    out = a.out
    nvec = gen_vectors(os.path.join(out, "zbb_vectors.mem"), random.Random(2024))
    progs = gen_directed() + [gen_random(s) for s in range(1, a.seeds + 1)]
    with open(os.path.join(out, "zbb_prog.hex"), "w") as fp, open(os.path.join(out, "zbb_prog_expect.mem"), "w") as fe:
        for name, prog in progs:
            res = run(prog)
            assert not res["illegal"], name
            assert len(prog) < IMEM_WORDS, (name, len(prog))
            fp.write("// %s\n" % name)
            for w in prog + [NOP] * (IMEM_WORDS - len(prog)): fp.write("%08x\n" % (w & M32))
            fe.write("// %s\n" % name)
            for r in res["regs"]: fe.write("%08x\n" % r)
            for i in range(MEMW): fe.write("%08x\n" % res["mem"].get(i, 0))
    print("gen_tests: %d 個 Zbb 向量; %d 支程式 (directed %d + random %d) -> %s" %
          (nvec, len(progs), len(progs) - a.seeds, a.seeds, os.path.normpath(out)))


if __name__ == "__main__":
    main()
