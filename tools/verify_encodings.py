#!/usr/bin/env python3
"""用 GNU binutils (riscv*-unknown-elf-as) 核對 rv32i_model.py 的指令編碼。找不到組譯器就略過（exit 0）。
安裝：Ubuntu/Debian `sudo apt install binutils-riscv64-unknown-elf`"""
import os, random, shutil, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv32i_model import *

AS = next((shutil.which(n) for n in ("riscv64-unknown-elf-as", "riscv32-unknown-elf-as", "riscv64-linux-gnu-as")), None)
if not AS:
    print("SKIP verify_encodings: 找不到 riscv *-as"); sys.exit(0)
OBJCOPY = AS[:-2] + "objcopy"

rnd = random.Random(1)
R = lambda: rnd.randrange(32)
cases = []                         # (asm 文字, 我的編碼)
for n in list(BASE_R) + list(ZBB_R) + list(M_R):
    for _ in range(6):
        d, a, b = R(), R(), R(); cases.append((f"{n} x{d},x{a},x{b}", asm(n, d, a, b)))
for n in BASE_I:
    for _ in range(6):
        d, a, i = R(), R(), rnd.randrange(-2048, 2048); cases.append((f"{n} x{d},x{a},{i}", asm(n, d, a, i)))
for n in SHIFT_I:
    for _ in range(6):
        d, a, i = R(), R(), rnd.randrange(32); cases.append((f"{n} x{d},x{a},{i}", asm(n, d, a, i)))
for n in ZBB_U:
    for _ in range(6):
        d, a = R(), R(); cases.append((f"{n.replace('_', '.')} x{d},x{a}", asm(n, d, a)))
for _ in range(6):
    d, a, o = R(), R(), rnd.randrange(-2048, 2048); cases.append((f"lw x{d},{o}(x{a})", asm("lw", d, a, o)))
    cases.append((f"sw x{d},{o}(x{a})", asm("sw", d, a, o)))
    cases.append((f"jalr x{d},{o}(x{a})", asm("jalr", d, a, o)))
    u = rnd.randrange(1 << 20); cases.append((f"lui x{d},{u}", asm("lui", d, u)))
    cases.append((f"auipc x{d},{u}", asm("auipc", d, u)))
for n in ("beq", "bne", "blt", "bge", "bltu", "bgeu"):
    for _ in range(4):
        a, b, o = R(), R(), rnd.randrange(-1024, 1024) * 2; cases.append((f"{n} x{a},x{b},.+{o}", asm(n, a, b, o)))
for _ in range(6):
    d, o = R(), rnd.randrange(-(1 << 19), 1 << 19) * 2; cases.append((f"jal x{d},.+{o}", asm("jal", d, o)))

with tempfile.TemporaryDirectory() as t:
    s, o, b = (os.path.join(t, x) for x in ("a.s", "a.o", "a.bin"))
    open(s, "w").write("\n".join(c[0] for c in cases) + "\n")
    subprocess.run([AS, "-march=rv32im_zbb", "-mabi=ilp32", s, "-o", o], check=True)
    subprocess.run([OBJCOPY, "-O", "binary", "-j", ".text", o, b], check=True)
    data = open(b, "rb").read()
words = [int.from_bytes(data[i:i + 4], "little") for i in range(0, len(data), 4)]
bad = [(c[0], hex(c[1]), hex(w)) for c, w in zip(cases, words) if c[1] != w]
print(f"verify_encodings: {len(cases)} 條指令, 不一致 {len(bad)}")
for x in bad[:10]: print("  MISMATCH", x)
sys.exit(1 if bad or len(words) != len(cases) else 0)
