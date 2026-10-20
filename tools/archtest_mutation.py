#!/usr/bin/env python3
"""
archtest_mutation.py  突變測試：故意把 RTL 改壞，確認 riscv-arch-test 流程會抓到（對應的測試必須失敗）。
用法：python3 tools/archtest_mutation.py --arch-test <dir2> --arch-test3 <dir3>
每個突變：複製 src/ 到暫存資料夾 → 改一處 → run_archtest.py --src <暫存> --only <相關測試>；沒有測試失敗就代表測試無效。
"""
import argparse, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))

# (名稱, 檔案, 原文, 改成, 應該失敗的測試)
MUTATIONS = [
    ("SUB 改成 ADD", "alu.v", "ALU_SUB:  Result = A - B;", "ALU_SUB:  Result = A + B;", ["sub-01"]),
    ("SRA 改成邏輯右移", "alu.v", "ALU_SRA:  Result = $signed(A) >>> B[4:0];", "ALU_SRA:  Result = A >> B[4:0];", ["sra-01", "srai-01"]),
    ("SLTU 改成有號比較", "alu.v", "ALU_SLTU: Result = (A < B) ? 32'd1 : 32'd0;", "ALU_SLTU: Result = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0;", ["sltu-01", "sltiu-01"]),
    ("SLL 位移量只取 4 位元", "alu.v", "ALU_SLL:  Result = A << B[4:0];", "ALU_SLL:  Result = A << B[3:0];", ["sll-01", "slli-01"]),
    ("MUL 改成 A+B", "alu.v", "ALU_MUL:  Result = A * B;", "ALU_MUL:  Result = A + B;", ["mul-01"]),
    ("BLTU 改成有號比較", "branch_unit.v", "F3_BLTU: taken = (rs1_value <  rs2_value);", "F3_BLTU: taken = ($signed(rs1_value) <  $signed(rs2_value));", ["bltu-01"]),
    ("BGE 改成 BGT（少了等於）", "branch_unit.v", "F3_BGE:  taken = ($signed(rs1_value) >= $signed(rs2_value));", "F3_BGE:  taken = ($signed(rs1_value) >  $signed(rs2_value));", ["bge-01"]),
    ("forwarding：MEM/WB 轉送 A 失效", "forwarding_unit.v", "forward_a = 2'b01;", "forward_a = 2'b00;", ["add-01", "and-01", "xor-01"]),
    ("load-use stall 關掉", "hazard_unit.v", "stall = 1'b1;", "stall = 1'b0;", ["lw-align-01", "sw-align-01"]),
    ("Zbb clz 結果錯一位", "zbb_unit.v", "OP_CLZ:    Result = {26'b0, clz32(A)};", "OP_CLZ:    Result = {26'b0, clz32(A)} ^ 32'd1;", ["clz-01"]),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arch-test", required=True)
    ap.add_argument("--arch-test3")
    a = ap.parse_args()
    caught = 0
    for name, fn, old, new, tests in MUTATIONS:
        if any(t in ("clz-01",) for t in tests) and not a.arch_test3:
            print("略過（需要 --arch-test3）：", name); continue
        tmp = tempfile.mkdtemp(prefix="mut_")
        try:
            shutil.copytree(os.path.join(ROOT, "src"), os.path.join(tmp, "src"))
            path = os.path.join(tmp, "src", fn)
            txt = open(path).read()
            assert txt.count(old) == 1, (name, "原文出現 %d 次" % txt.count(old))
            open(path, "w").write(txt.replace(old, new))
            cmd = [sys.executable, os.path.join(HERE, "run_archtest.py"), "--arch-test", a.arch_test, "--src", os.path.join(tmp, "src"),
                   "--out", os.path.join(tmp, "out"), "--suite", "I", "M", "--only"] + tests
            if a.arch_test3:
                cmd += ["--arch-test3", a.arch_test3]
            r = subprocess.run(cmd, capture_output=True, text=True)
            failed = [l.split()[0] for l in r.stdout.splitlines()
                      if len(l.split()) > 1 and "/" in l.split()[0] and l.split()[1] in ("FAIL", "BUILD_ERROR", "SIM_ERROR")]
            ok = bool(failed)
            caught += ok
            print("%-28s -> %s（失敗的測試：%s）" % (name, "抓到" if ok else "沒抓到！", ", ".join(failed) or "無"))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    print("\n突變測試：%d / %d 個突變被抓到" % (caught, len(MUTATIONS)))
    sys.exit(0 if caught == len(MUTATIONS) else 1)


if __name__ == "__main__":
    main()
