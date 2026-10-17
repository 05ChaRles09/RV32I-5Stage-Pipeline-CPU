#!/usr/bin/env python3
"""產生 sim/illegal.hex（tb_illegal.v 使用）。程式內容與預期結果見 tb_illegal.v 檔頭。"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv32i_model import *

prog = [
    asm("addi", 1, 0, 5),        # 0x00 x1 = 5
    0x02109133,                  # 0x04 mulh x2,x1,x1       (RV32M 只實作 MUL；MULH 仍 illegal，必須當 NOP)
    asm("addi", 3, 0, 7),        # 0x08 x3 = 7
    0x00000203,                  # 0x0c lb x4,0(x0)        (本核心只支援 lw -> illegal)
    asm("addi", 5, 0, 9),        # 0x10 x5 = 9
    0x00000000,                  # 0x14 全 0 字             (illegal)
    0x0FF0000F,                  # 0x18 fence               (illegal)
    0x00000073,                  # 0x1c ecall               (illegal)
    0x00100023,                  # 0x20 sb x1,0(x0)         (illegal，且 mem[0] 不可被寫)
    0x40109313,                  # 0x24 slli 但 funct7=0100000 (illegal，舊版會被當 SLL 執行)
    asm("addi", 7, 0, 1),        # 0x28 x7 = 1
    asm("beq", 0, 0, 8),         # 0x2c 一定跳 -> 跳過 0x30
    0x02109133 | ((9 - 2) << 7),  # 0x30 mulh x9,x1,x1 在「錯誤路徑」：被 flush，不可被計入 illegal
    asm("addi", 8, 0, 3),        # 0x34 x8 = 3
    enc_r(CUSTOM0, 0, 0x01, 10, 1, 1),   # 0x38 custom-0 funct7=1 (illegal) -> x10 stays 0
    enc_r(CUSTOM0, 1, 0x00, 11, 1, 1),   # 0x3c custom-0 funct3=1 (illegal) -> x11 stays 0
    asm("jal", 0, 0),            # 0x40 spin
]
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sim", "illegal.hex")
with open(out, "w") as f:
    for w in prog: f.write("%08x\n" % w)
print("wrote", os.path.normpath(out), len(prog), "words")
