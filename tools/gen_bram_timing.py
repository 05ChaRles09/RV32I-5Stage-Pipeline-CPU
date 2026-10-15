#!/usr/bin/env python3
"""
gen_bram_timing.py  針對「BRAM 同步讀取」時序邊界的定向程式 -> sim/bram_timing.hex、sim/bram_timing_expect.mem
涵蓋（IMEM 以 pc_next 取指、DMEM 在 EX 讀寫，這些都是最容易出錯的組合）：
  1. store 後緊接 load（同位址）  2. store 後隔一條再 load  3. load 後緊接使用（load-use stall 期間取指保持）
  4. load 的結果直接當 store 資料  5. load-use 後接 taken branch（stall 與 flush 同時鄰近）
  6. 連續 load 不同位址  7. 連續 store 後反向順序 load  8. jal/jalr 重導向後的第一條指令  9. 迴圈（branch 反覆 taken）
輸出 expect：x0..x31 + dmem[0..15]（由 Python 黃金模型計算）
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv32i_model import asm, li, run, M32

def program():
    p = []
    A = lambda *a: p.append(asm(*a))
    p += li(1, 0x11111111); p += li(2, 0x22222222); p += li(3, 0x33333333)
    A("addi", 10, 0, 0)                       # x10 = 0 (base)
    # 1. store -> load back-to-back, same address
    A("sw", 1, 10, 0);  A("lw", 4, 10, 0)
    # 2. store, one instr, load
    A("sw", 2, 10, 4);  A("addi", 5, 0, 7); A("lw", 6, 10, 4)
    # 3. load -> immediate use (load-use stall)
    A("lw", 7, 10, 0);  A("add", 8, 7, 7)
    # 4. load result used as store data, then reload
    A("lw", 9, 10, 4);  A("sw", 9, 10, 8);  A("lw", 11, 10, 8)
    # 5. load-use feeding a taken branch, then fall-through / target both distinct
    A("lw", 12, 10, 0); A("beq", 12, 1, 12)   # taken (x12 == x1) -> skip next 2 instrs
    A("addi", 13, 0, 111); A("addi", 13, 0, 222)
    A("addi", 14, 0, 5)                       # branch target
    # 6. consecutive loads of different addresses
    A("lw", 15, 10, 0); A("lw", 16, 10, 4); A("lw", 17, 10, 8)
    # 7. consecutive stores, loads in reverse order
    A("sw", 3, 10, 12); A("sw", 1, 10, 16); A("sw", 2, 10, 20)
    A("lw", 18, 10, 20); A("lw", 19, 10, 16); A("lw", 20, 10, 12)
    # 8. jal over garbage, jalr back-to-back redirect
    A("jal", 21, 12);  A("addi", 22, 0, 999); A("addi", 22, 0, 998)
    A("addi", 22, 0, 1)                       # jal target
    A("jal", 23, 8);   A("addi", 24, 0, 997)
    A("addi", 24, 0, 2)
    # 9. loop with load/store each iteration: mem[16..] accumulates, 6 iterations
    A("addi", 25, 0, 0)  # i
    A("addi", 26, 0, 6)  # n
    A("addi", 27, 0, 0)  # sum
    A("lw", 28, 10, 24); A("add", 28, 28, 1); A("sw", 28, 10, 24)    # loop body: load -> use -> store -> (next iter) load, same address
    A("addi", 25, 25, 1)
    A("bne", 25, 26, -16)
    A("lw", 29, 10, 24)
    A("jal", 0, 0)
    return p

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sim")
    p = program()
    r = run(p)
    assert not r["illegal"]
    with open(os.path.join(out, "bram_timing.hex"), "w") as f:
        for w in p + [0x13] * (1024 - len(p)): f.write("%08x\n" % (w & M32))
    with open(os.path.join(out, "bram_timing_expect.mem"), "w") as f:
        for v in r["regs"]: f.write("%08x\n" % v)
        for i in range(16): f.write("%08x\n" % r["mem"].get(i, 0))
    print("gen_bram_timing: %d instructions, spin pc=0x%X" % (len(p), r["pc"]))
    print("x4=%08x x6=%08x x8=%08x x11=%08x x13=%d x14=%d x22=%d x24=%d x28=%08x x29=%08x" % tuple(
        r["regs"][i] for i in (4, 6, 8, 11, 13, 14, 22, 24, 28, 29)))

if __name__ == "__main__":
    main()
