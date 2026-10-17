#!/usr/bin/env python3
"""
gen_coe.py  產生 Block Memory Generator 的初始化檔（COE）
  bram_init/imem_board_program.coe   IMEM：136 字板測程式，其後以 NOP（0x00000013）補滿到 1024 字
  bram_init/dmem_zero.coe            DMEM：1024 字全 0（BMG 不載入 COE 時預設也是 0，這份是備用）
用法：python tools/gen_coe.py [輸出資料夾，預設 bram_init]
"""
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "bram_init")
os.makedirs(out, exist_ok=True)
DEPTH = 1024
prog = [int(l, 16) for l in open(os.path.join(here, "..", "sim", "board_program.hex")) if l.strip() and not l.lstrip().startswith("//")]
assert len(prog) <= DEPTH
imem = prog + [0x13] * (DEPTH - len(prog))
def write(name, words):
    with open(os.path.join(out, name), "w") as f:
        f.write("memory_initialization_radix=16;\nmemory_initialization_vector=\n")
        f.write(",\n".join("%08x" % (w & 0xFFFFFFFF) for w in words) + ";\n")
write("imem_board_program.coe", imem)
write("dmem_zero.coe", [0] * DEPTH)
print("gen_coe: imem %d 字（程式 %d 字 + NOP）, dmem %d 字 -> %s" % (DEPTH, len(prog), DEPTH, os.path.normpath(out)))
