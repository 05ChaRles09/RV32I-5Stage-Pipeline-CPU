"""
rv32i_model.py  RV32I + Zbb + MUL 的 Python 參考模型（golden model）與迷你組譯器。

用途
  * 提供 Zbb 每個指令的「標準答案」(zbb_ref)
  * 提供 ISA 層級的程式執行模型 run()，輸出最終暫存器、記憶體與寫回序列
  * 提供指令編碼器 enc_*，產生測試程式的機器碼（已對照 GNU binutils 驗證，見 verify_encodings.py）

模型與硬體 control_unit.v 的 illegal 規則一致：不支援的指令視為 NOP 並被記錄。
本核心目前只支援 lw/sw（沒有 lb/lh/sb/sh）、RV32M 只有 MUL（MULH*/DIV*/REM* 仍為 illegal）、沒有 CSR / FENCE / ECALL。
"""
M32 = 0xFFFFFFFF


def s32(v):
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


# ----------------------------------------------------------------------------
# Zbb 標準答案
# ----------------------------------------------------------------------------
def _clz(a):
    return 32 - a.bit_length()


def _ctz(a):
    return 32 if a == 0 else (a & -a).bit_length() - 1


def _rol(a, n):
    n &= 31
    return ((a << n) | (a >> (32 - n))) & M32 if n else a


def _ror(a, n):
    n &= 31
    return ((a >> n) | (a << (32 - n))) & M32 if n else a


ZBB_REF = {
    "andn":   lambda a, b: a & ~b & M32,
    "orn":    lambda a, b: (a | ~b) & M32,
    "xnor":   lambda a, b: ~(a ^ b) & M32,
    "min":    lambda a, b: a if s32(a) < s32(b) else b,
    "minu":   lambda a, b: a if a < b else b,
    "max":    lambda a, b: b if s32(a) < s32(b) else a,
    "maxu":   lambda a, b: b if a < b else a,
    "rol":    lambda a, b: _rol(a, b),
    "ror":    lambda a, b: _ror(a, b),
    "clz":    lambda a, b: _clz(a),
    "ctz":    lambda a, b: _ctz(a),
    "cpop":   lambda a, b: bin(a).count("1"),
    "sext_b": lambda a, b: sx(a, 8) & M32,
    "sext_h": lambda a, b: sx(a, 16) & M32,
    "zext_h": lambda a, b: a & 0xFFFF,
    "rev8":   lambda a, b: int.from_bytes(a.to_bytes(4, "little"), "big"),
    "orc_b":  lambda a, b: sum(0xFF << (8 * i) for i in range(4) if (a >> (8 * i)) & 0xFF),
}

# 與 zbb_unit.v / control_unit.v 的 op 編碼順序一致
ZBB_OPS = ["andn", "orn", "xnor", "min", "minu", "max", "maxu", "rol", "ror",
           "clz", "ctz", "cpop", "sext_b", "sext_h", "zext_h", "rev8", "orc_b"]
ZBB_BINARY = ["andn", "orn", "xnor", "min", "minu", "max", "maxu", "rol", "ror"]   # R-type, 用 rs2
ZBB_UNARY = ["clz", "ctz", "cpop", "sext_b", "sext_h", "zext_h", "rev8", "orc_b"]  # 只用 rs1

# ----------------------------------------------------------------------------
# 編碼器
# ----------------------------------------------------------------------------
OP, OPIMM, LOAD, STORE, BRANCH, JAL, JALR, LUI, AUIPC = (
    0b0110011, 0b0010011, 0b0000011, 0b0100011, 0b1100011, 0b1101111, 0b1100111, 0b0110111, 0b0010111)


def enc_r(op, f3, f7, rd, rs1, rs2):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(op, f3, rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(f3, rs1, rs2, imm):
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | STORE


def enc_b(f3, rs1, rs2, imm):
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
           (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | BRANCH


def enc_u(op, rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


def enc_j(rd, imm):
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) | \
           (((imm >> 12) & 0xFF) << 12) | (rd << 7) | JAL


BASE_R = {"add": (0, 0x00), "sub": (0, 0x20), "sll": (1, 0), "slt": (2, 0), "sltu": (3, 0),
          "xor": (4, 0), "srl": (5, 0), "sra": (5, 0x20), "or": (6, 0), "and": (7, 0)}
CUSTOM0 = 0x0B                    # custom-0 opcode
X_R = {"xdotp16": (0, 0x00)}      # 自訂：int16 x2 內積（opcode=custom-0）
M_R = {"mul": (0, 0x01)}          # RV32M：只實作 MUL（低 32 位元）
BASE_I = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFT_I = {"slli": (1, 0x00), "srli": (5, 0x00), "srai": (5, 0x20), "rori": (5, 0x30)}
ZBB_R = {"andn": (7, 0x20), "orn": (6, 0x20), "xnor": (4, 0x20),
         "min": (4, 0x05), "minu": (5, 0x05), "max": (6, 0x05), "maxu": (7, 0x05),
         "rol": (1, 0x30), "ror": (5, 0x30)}
# 單運算元：(opcode, funct3, funct7, rs2 欄位固定值)
ZBB_U = {"clz": (OPIMM, 1, 0x30, 0), "ctz": (OPIMM, 1, 0x30, 1), "cpop": (OPIMM, 1, 0x30, 2),
         "sext_b": (OPIMM, 1, 0x30, 4), "sext_h": (OPIMM, 1, 0x30, 5),
         "rev8": (OPIMM, 5, 0x34, 0x18), "orc_b": (OPIMM, 5, 0x14, 0x07),
         "zext_h": (OP, 4, 0x04, 0)}


def asm(name, *a):
    """asm('add', rd, rs1, rs2) / asm('addi', rd, rs1, imm) / asm('clz', rd, rs1) / asm('lw', rd, rs1, off) /
       asm('sw', rs2, rs1, off) / asm('beq', rs1, rs2, off) / asm('lui', rd, imm20) / asm('jal', rd, off)"""
    if name in BASE_R:
        f3, f7 = BASE_R[name]; return enc_r(OP, f3, f7, *a)
    if name in ZBB_R:
        f3, f7 = ZBB_R[name]; return enc_r(OP, f3, f7, *a)
    if name in M_R:
        f3, f7 = M_R[name]; return enc_r(OP, f3, f7, *a)
    if name in X_R:
        f3, f7 = X_R[name]; return enc_r(CUSTOM0, f3, f7, *a)
    if name in BASE_I:
        return enc_i(OPIMM, BASE_I[name], *a)
    if name in SHIFT_I:
        f3, f7 = SHIFT_I[name]; rd, rs1, sh = a
        return enc_i(OPIMM, f3, rd, rs1, (f7 << 5) | (sh & 31))
    if name in ZBB_U:
        op, f3, f7, r2 = ZBB_U[name]; rd, rs1 = a
        return enc_r(op, f3, f7, rd, rs1, r2)
    if name == "lw":
        rd, rs1, off = a; return enc_i(LOAD, 2, rd, rs1, off)
    if name == "sw":
        rs2, rs1, off = a; return enc_s(2, rs1, rs2, off)
    if name in ("beq", "bne", "blt", "bge", "bltu", "bgeu"):
        f3 = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}[name]
        return enc_b(f3, a[0], a[1], a[2])
    if name == "lui":
        return enc_u(LUI, *a)
    if name == "auipc":
        return enc_u(AUIPC, *a)
    if name == "jal":
        return enc_j(*a)
    if name == "jalr":
        rd, rs1, off = a; return enc_i(JALR, 0, rd, rs1, off)
    raise ValueError(name)


def li(rd, value):
    """載入 32-bit 常數 → [lui, addi]"""
    value &= M32
    lo = sx(value, 12)
    hi = ((value - lo) & M32) >> 12
    return [asm("lui", rd, hi), asm("addi", rd, rd, lo)]


# ----------------------------------------------------------------------------
# 解碼 + 執行（鏡像 control_unit.v）
# ----------------------------------------------------------------------------
def decode(ins):
    """回傳 ('name', fields...) 或 None（= illegal，硬體當 NOP）"""
    op = ins & 0x7F
    rd = (ins >> 7) & 31; f3 = (ins >> 12) & 7
    rs1 = (ins >> 15) & 31; rs2 = (ins >> 20) & 31; f7 = ins >> 25
    immi = sx(ins >> 20, 12)
    if op == OP:
        for n, (a, b) in BASE_R.items():
            if (f3, f7) == (a, b): return (n, rd, rs1, rs2)
        for n, (a, b) in ZBB_R.items():
            if (f3, f7) == (a, b): return (n, rd, rs1, rs2)
        for n, (a, b) in M_R.items():
            if (f3, f7) == (a, b): return (n, rd, rs1, rs2)
        if (f3, f7) == (4, 0x04) and rs2 == 0: return ("zext_h", rd, rs1, 0)
        return None
    if op == CUSTOM0:
        return ("xdotp16", rd, rs1, rs2) if (f3, f7) == (0, 0) else None
    if op == OPIMM:
        for n, a in BASE_I.items():
            if f3 == a: return (n, rd, rs1, immi)
        if f3 == 1:
            if f7 == 0: return ("slli", rd, rs1, rs2)
            if f7 == 0x30:
                m = {0: "clz", 1: "ctz", 2: "cpop", 4: "sext_b", 5: "sext_h"}
                return (m[rs2], rd, rs1, 0) if rs2 in m else None
            return None
        if f3 == 5:
            if f7 == 0: return ("srli", rd, rs1, rs2)
            if f7 == 0x20: return ("srai", rd, rs1, rs2)
            if f7 == 0x30: return ("rori", rd, rs1, rs2)
            if f7 == 0x34 and rs2 == 0x18: return ("rev8", rd, rs1, 0)
            if f7 == 0x14 and rs2 == 0x07: return ("orc_b", rd, rs1, 0)
            return None
        return None
    if op == LOAD:
        return ("lw", rd, rs1, immi) if f3 == 2 else None
    if op == STORE:
        imm = sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
        return ("sw", rs2, rs1, imm) if f3 == 2 else None
    if op == BRANCH:
        if f3 in (2, 3): return None
        imm = sx(((ins >> 31) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
        return ({0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}[f3], rs1, rs2, imm)
    if op == JAL:
        imm = sx(((ins >> 31) << 20) | (((ins >> 12) & 0xFF) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
        return ("jal", rd, imm)
    if op == JALR:
        return ("jalr", rd, rs1, immi) if f3 == 0 else None
    if op == LUI:
        return ("lui", rd, ins & 0xFFFFF000)
    if op == AUIPC:
        return ("auipc", rd, ins & 0xFFFFF000)
    return None


def xdotp16(a, b):
    """rd = a[15:0]*b[15:0] + a[31:16]*b[31:16]（有號 16x16，和取 32 位元）"""
    return (sx(a & 0xFFFF, 16) * sx(b & 0xFFFF, 16) + sx(a >> 16, 16) * sx(b >> 16, 16)) & M32


def _base_r(n, a, b):
    return {"add": a + b, "sub": a - b, "sll": a << (b & 31), "slt": int(s32(a) < s32(b)), "sltu": int(a < b),
            "xor": a ^ b, "srl": a >> (b & 31), "sra": s32(a) >> (b & 31), "or": a | b, "and": a & b}[n] & M32


def run(prog, max_steps=50000, mem_words=1024):   # dmem.v: 4096 位元組 = 1024 字（索引 addr[11:2]）
    """執行到「自我跳躍」(spin) 為止。
    回傳 dict: regs[32], mem{word_index: value}, wb[(rd,val)...] (rd!=0, 程式順序), illegal[pc...], pc"""
    x = [0] * 32
    mem = {}
    wb, illegal, winfo = [], [], []
    pc = 0
    for _ in range(max_steps):
        ins = prog[pc >> 2] if (pc >> 2) < len(prog) else 0x00000013       # imem 以 NOP 填滿
        d = decode(ins)
        npc = (pc + 4) & M32
        val = None
        rd = None
        if d is None:
            illegal.append(pc)
        else:
            n = d[0]
            if n in BASE_R or n in ZBB_R or n in M_R or n in X_R:
                _, rd, r1, r2 = d
                if n in X_R: val = xdotp16(x[r1], x[r2])
                elif n in M_R: val = (x[r1] * x[r2]) & M32
                elif n in BASE_R: val = _base_r(n, x[r1], x[r2])
                else: val = ZBB_REF[n](x[r1], x[r2])
            elif n in BASE_I:
                _, rd, r1, imm = d
                a = x[r1]; b = imm & M32
                val = {"addi": a + b, "slti": int(s32(a) < imm), "sltiu": int(a < b),
                       "xori": a ^ b, "ori": a | b, "andi": a & b}[n] & M32
            elif n in ("slli", "srli", "srai", "rori"):
                _, rd, r1, sh = d
                a = x[r1]
                val = {"slli": a << sh, "srli": a >> sh, "srai": s32(a) >> sh, "rori": _ror(a, sh)}[n] & M32
            elif n in ZBB_UNARY:
                _, rd, r1, _ = d
                val = ZBB_REF[n](x[r1], 0)
            elif n == "lw":
                _, rd, r1, imm = d
                val = mem.get(((x[r1] + imm) & M32) >> 2 & (mem_words - 1), 0)
            elif n == "sw":
                _, r2, r1, imm = d
                mem[((x[r1] + imm) & M32) >> 2 & (mem_words - 1)] = x[r2]
            elif n in ("beq", "bne", "blt", "bge", "bltu", "bgeu"):
                _, r1, r2, imm = d
                a, b = x[r1], x[r2]
                t = {"beq": a == b, "bne": a != b, "blt": s32(a) < s32(b), "bge": s32(a) >= s32(b),
                     "bltu": a < b, "bgeu": a >= b}[n]
                if t: npc = (pc + imm) & M32
            elif n == "jal":
                _, rd, imm = d; val = (pc + 4) & M32; npc = (pc + imm) & M32
            elif n == "jalr":
                _, rd, r1, imm = d; val = (pc + 4) & M32; npc = (x[r1] + imm) & ~1 & M32
            elif n == "lui":
                _, rd, imm = d; val = imm
            elif n == "auipc":
                _, rd, imm = d; val = (pc + imm) & M32
        if val is not None and rd:
            x[rd] = val & M32
            wb.append((rd, val & M32))
            winfo.append((pc, d[0], rd, val & M32))      # (指令 PC, 助記符, rd, 值)
        if npc == pc:
            break
        pc = npc
    return {"regs": x, "mem": mem, "wb": wb, "winfo": winfo, "illegal": illegal, "pc": pc}
