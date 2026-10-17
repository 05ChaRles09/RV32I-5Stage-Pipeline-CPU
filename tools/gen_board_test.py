"""gen_board_test.py  產生上板用的 program.hex（RV32I 原測試 + Zbb + MUL + XDOTP16 + illegal）。
用法: python gen_board_test.py <out_dir>    （需要同資料夾或 ../repo/tools 的 rv32i_model.py）
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "repo", "tools"))
from rv32i_model import *

# 原本的 40 字測試程式（最後一字是 spin，改成接續新測試）
ORIG = [0x00500093, 0x00a00113, 0x002081b3, 0x00500213, 0x00320293, 0x00528b93, 0x00100313, 0x00130393,
        0x00138413, 0x00000593, 0x02a00493, 0x0095a023, 0x0005a503, 0x00950633, 0x00000493, 0x00050493,
        0x00000693, 0x00100793, 0x00100813, 0x01078463, 0x06300693, 0x00700713, 0x00100913, 0x00200993,
        0x01391663, 0x00500893, 0x00900893, 0x00900893, 0x00000013, 0x00000013, 0x00000a93, 0x00c000ef,
        0x00500a93, 0x00700a93, 0x06300a13, 0x0080006f, 0x00500a93, 0x12345b37, 0x0040006f]   # 39 字，無 spin
P = list(ORIG)
a, b, c = 1, 2, 3
# ---- 常數 ----
P += li(a, 0xF0F08A81) + li(b, 0x00FF0003) + li(c, 0x00012300)
# ---- Zbb 二元運算 ----
for i, n in enumerate(["andn", "orn", "xnor", "min", "minu", "max", "maxu", "rol", "ror"]):
    P.append(asm(n, 5 + i, a, b))                 # x5..x13
P.append(asm("rori", 14, a, 12))
# ---- Zbb 單元運算 ----
P += [asm("clz", 15, c), asm("ctz", 16, c), asm("cpop", 17, a), asm("sext_b", 18, a), asm("sext_h", 19, a),
      asm("zext_h", 20, a), asm("rev8", 21, a), asm("orc_b", 22, c),
      asm("clz", 23, 0), asm("ctz", 24, 0), asm("cpop", 25, 0), asm("clz", 26, a), asm("ctz", 27, a)]
# ---- 轉送（Zbb 結果緊接著被使用）----
P += [asm("clz", 28, c), asm("add", 29, 28, 28), asm("rev8", 30, a), asm("xor", 31, 30, a)]
# ---- Zbb 結果存入 dmem 再讀回，load-use ----
P += [asm("sw", 21, 0, 8), asm("lw", 5, 0, 8), asm("add", 6, 5, 5)]
# ---- 依 Zbb 結果分支（不跳 / 跳；跳過的 shadow 內放 illegal，不應被回報）----
P += [asm("cpop", 7, c), asm("addi", 8, 0, 4),
      asm("bne", 7, 8, 8), asm("addi", 9, 0, 0x55),           # bne 不成立 → 執行 addi x9
      asm("beq", 7, 8, 8), 0x02a50533,                         # beq 成立 → 跳過 shadow 的 mul（現為合法 MUL，被 flush 不得提交）
      asm("addi", 10, 0, 0x66)]
# ---- RV32M MUL（含轉送 / load-use / 依 mul 結果分支）----
P += [asm("mul", 15, a, b), asm("mul", 16, a, a), asm("mul", 17, c, 0),          # 一般 / 平方 / 乘 x0
      asm("addi", 19, 0, -1), asm("mul", 20, 19, 19), asm("mul", 21, 19, c),      # (-1)*(-1)=1, (-1)*c=-c
      asm("lui", 28, 0x80000), asm("addi", 29, 0, 2),
      asm("mul", 30, 28, 29), asm("mul", 31, 28, 19),                             # 0x80000000*2 溢位=0, *(-1)=0x80000000
      asm("mul", 22, a, b), asm("add", 23, 22, 22), asm("mul", 24, 22, 22),       # mul→add、mul→mul 轉送
      asm("sw", 22, 0, 12), asm("lw", 25, 0, 12), asm("mul", 26, 25, c),          # load→mul（load-use）
      asm("mul", 7, 29, 29), asm("addi", 8, 0, 4),
      asm("bne", 7, 8, 8), asm("addi", 9, 0, 0x3C),                               # 4==4：bne 不跳，執行 addi
      asm("beq", 7, 8, 8), asm("mul", 27, 29, 29),                                # beq 跳過 shadow 的 mul
      asm("addi", 10, 0, 0x2B)]
# ---- custom XDOTP16（int16 x2 內積；含負數 / 溢位 / 轉送 / load-use / 依結果分支）----
P += [asm("xdotp16", 15, a, b), asm("xdotp16", 16, a, a), asm("xdotp16", 17, c, 0),
      asm("lui", 28, 0x80008),                                                     # x28 = 0x80008000
      asm("xdotp16", 29, 28, 28),                                                  # 2*(-32768)^2 = 0x80000000（溢位回繞）
      asm("lui", 19, 0x7FFF8), asm("addi", 19, 19, -1),                            # x19 = 0x7FFF7FFF
      asm("xdotp16", 20, 19, 19), asm("xdotp16", 21, 28, 19),
      asm("xdotp16", 22, a, b), asm("add", 23, 22, 22), asm("xdotp16", 24, 22, 22),   # xdotp→add、xdotp→xdotp 轉送
      asm("sw", 22, 0, 16), asm("lw", 25, 0, 16), asm("xdotp16", 26, 25, a),       # load→xdotp（load-use）
      asm("xdotp16", 7, 0, 0), asm("addi", 8, 0, 0),
      asm("beq", 7, 8, 8), asm("xdotp16", 27, a, b),                               # 0==0：beq 跳過 shadow 的 xdotp16（被 flush）
      asm("addi", 10, 0, 0x77)]
# ---- illegal（皆在已提交路徑，應當作 NOP；結果暫存器維持 0）----
ILLEGAL_START = len(P) * 4
P += [enc_r(OP, 1, 0x01, 12, 11, 10),                        # mulh x12,x11,x10（RV32M 只實作 MUL）
      0x00002583,                                             # lh? -> lw 是 0x00002583；此為 lw 合法，改下方
      ]
P.pop()                                                       # 移除上面誤放的合法 lw
P += [enc_r(CUSTOM0, 0, 0x01, 12, a, b),                       # custom-0 但 funct7≠0 → illegal
      0x00000283,                                             # lb x5,0(x0)   → 只支援 lw
      0x00000000,                                             # 全零字
      0x0ff0000f,                                             # fence
      0x00000073,                                             # ecall
      0x00100023,                                             # sb x1,0(x0)   → 不得寫 dmem[0]
      enc_i(OPIMM, 1, 11, a, (0x20 << 5) | 1),                # 不合法的 slli（funct7=0100000）
      enc_r(OPIMM, 1, 0x30, 12, a, 3),                        # clz 家族但 rs2=3 → illegal（enc_r 的 op 參數是第一個）
      ]
# 修正：enc_r(op, f3, f7, rd, rs1, rs2)
P[-1] = enc_r(OPIMM, 1, 0x30, 13, a, 3)
P += [asm("addi", 14, 0, 0x7A)]                               # illegal 之後仍能正常執行
P += [asm("jal", 0, 0)]                                       # spin
assert len(P) <= 1024

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "program.hex"), "w") as f:
        for w in P: f.write("%08x\n" % w)
    r = run(P)
    with open(os.path.join(out, "board_program_expect.mem"), "w") as f:     # x0..x31 + dmem[0..15]
        for v in r["regs"]: f.write("%08x\n" % v)
        for i in range(16): f.write("%08x\n" % r["mem"].get(i, 0))
    print("words:", len(P), " spin pc: 0x%X" % r["pc"], " writebacks:", len(r["wb"]), " committed illegal:", len(r["illegal"]),
          [hex(p) for p in r["illegal"]])
