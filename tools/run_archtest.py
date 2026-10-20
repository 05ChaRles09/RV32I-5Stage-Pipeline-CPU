#!/usr/bin/env python3
"""
run_archtest.py  用 riscv-arch-test 驗證 rv32i_pipeline（iverilog 模擬，記憶體放大為 2 MB）。

兩組測試、兩種參考簽章：
  * RV32I（38 支）與 RV32M（8 支）：riscv-arch-test 的 old-framework-2.x 分支，附官方 reference_output。
  * Zbb（18 支）：riscv-arch-test 3.9.1 的 B 測試中屬於 Zbb 的部分。這個版本不附參考簽章，
    所以用 QEMU（qemu-system-riscv32，-cpu rv32,zbb=true）當獨立的參考模型產生簽章。
    為了確認 QEMU 可信，--validate-qemu 會對 2.x 的 RV32I / RV32M 測試也跑一次 QEMU，要求簽章與官方 reference_output 完全相同。

流程（每支測試）：riscv64-unknown-elf-gcc 編譯 → 取出 .text / .data → 放進 IMEM / DMEM（sim/tb_archtest.v）
→ 執行到 self_loop → 傾印簽章區 → 與參考簽章逐字比對。

需要：riscv64-unknown-elf-gcc / binutils、iverilog / vvp；Zbb 另需 qemu-system-riscv32。
  git clone --depth 1 --branch old-framework-2.x https://github.com/riscv-non-isa/riscv-arch-test <dir2>
  git clone --depth 1 --branch 3.9.1            https://github.com/riscv-non-isa/riscv-arch-test <dir3>

用法：python3 tools/run_archtest.py --arch-test <dir2> [--arch-test3 <dir3>] [--validate-qemu] [--out arch_test/results] [--only add-01 ...]
輸出：<out>/summary.json；每支測試的 ELF / hex / 簽章留在 <out>/work/（不進 git）。
"""
import argparse, json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
TARGET = os.path.join(ROOT, "arch_test", "target")
DMEM_BASE = 0x200000
GCC, OBJCOPY, NM = "riscv64-unknown-elf-gcc", "riscv64-unknown-elf-objcopy", "riscv64-unknown-elf-nm"

# 本核心「設計上不支援」的測試（lw / sw 以外的 load / store、RV32M 只做 MUL）。這些測試預期失敗，不算 RTL 錯誤。
UNSUPPORTED = {
    "lb-align-01": "lb（核心只有 lw / sw）", "lbu-align-01": "lbu（核心只有 lw / sw）",
    "lh-align-01": "lh（核心只有 lw / sw）", "lhu-align-01": "lhu（核心只有 lw / sw）",
    "sb-align-01": "sb（核心只有 lw / sw）", "sh-align-01": "sh（核心只有 lw / sw）",
    "mulh-01": "mulh（RV32M 只實作 MUL）", "mulhsu-01": "mulhsu（RV32M 只實作 MUL）", "mulhu-01": "mulhu（RV32M 只實作 MUL）",
    "div-01": "div（RV32M 只實作 MUL）", "divu-01": "divu（RV32M 只實作 MUL）",
    "rem-01": "rem（RV32M 只實作 MUL）", "remu-01": "remu（RV32M 只實作 MUL）",
}
ZBB_TESTS = ["andn-01", "clz-01", "cpop-01", "ctz-01", "max-01", "maxu-01", "min-01", "minu-01", "orcb_32-01", "orn-01",
             "rev8_32-01", "rol-01", "ror-01", "rori-01", "sext.b-01", "sext.h-01", "xnor-01", "zext.h_32-01"]


def sh(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def words_from_bin(path):
    b = open(path, "rb").read() if os.path.exists(path) else b""
    b += b"\0" * (-len(b) % 4)
    return [int.from_bytes(b[i:i + 4], "little") for i in range(0, len(b), 4)]


def write_hex(path, words):
    with open(path, "w") as f:
        for w in words:
            f.write("%08x\n" % w)
        if not words:
            f.write("00000013\n")


def symbols(elf):
    syms = {}
    for line in sh([NM, elf]).stdout.splitlines():
        p = line.split()
        if len(p) == 3:
            syms[p[2]] = int(p[0], 16)
    return syms


def build(src, envdir, march, ld, out_elf):
    cases = sorted(set(re.findall(r"TEST_CASE_\d+", open(src).read())))
    cmd = [GCC, "-march=" + march, "-mabi=ilp32", "-static", "-mcmodel=medany", "-mno-relax", "-fvisibility=hidden",
           "-nostdlib", "-nostartfiles", "-DXLEN=32"] + ["-D%s=True" % c for c in cases] + [
           "-I", os.path.join(TARGET, "wrap"), "-I", envdir, "-I", TARGET, "-T", os.path.join(TARGET, ld), src, "-o", out_elf]
    return sh(cmd)


def qemu_signature(elf, out, cpu="rv32,zbb=true"):
    """用 QEMU 跑 ELF（RAM 從 0x80000000），傾印 begin_signature..end_signature，寫成每行 8 位十六進位。"""
    s = symbols(elf)
    bs, es = s["begin_signature"], s["end_signature"]
    p = subprocess.Popen(["qemu-system-riscv32", "-M", "virt", "-cpu", cpu, "-bios", "none", "-kernel", elf, "-nographic",
                          "-monitor", "stdio", "-serial", "null", "-S"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, cwd=os.path.dirname(os.path.abspath(out)))
    p.stdin.write("cont\n"); p.stdin.flush(); time.sleep(0.8)
    tmp = out + ".bin"
    # monitor 的 size 參數是運算式，「2352 /path」會被當成除法；所以用相對檔名（cwd = 輸出資料夾）
    p.stdin.write("stop\npmemsave 0x%x %d %s\nquit\n" % (bs, es - bs, os.path.basename(tmp))); p.stdin.flush()
    try:
        p.wait(timeout=15)
    except subprocess.TimeoutExpired:
        p.kill()
    b = open(tmp, "rb").read()
    with open(out, "w") as f:
        for i in range(0, len(b), 4):
            f.write("%08x\n" % int.from_bytes(b[i:i + 4], "little"))
    return open(out).read().split()


def compare(got, exp):
    diff = [(i, g, e) for i, (g, e) in enumerate(zip(got, exp)) if g != e]
    if len(got) != len(exp):
        diff += [(min(len(got), len(exp)), "len=%d" % len(got), "len=%d" % len(exp))]
    return diff


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arch-test", required=True, help="riscv-arch-test old-framework-2.x 目錄（I / M，附官方簽章）")
    ap.add_argument("--arch-test3", help="riscv-arch-test 3.9.1 目錄（Zbb，用 QEMU 產生參考簽章）")
    ap.add_argument("--validate-qemu", action="store_true", help="2.x 測試也用 QEMU 跑一次，確認 QEMU 簽章 == 官方 reference_output")
    ap.add_argument("--suite", nargs="+", default=["I", "M"])
    ap.add_argument("--out", default=os.path.join(ROOT, "arch_test", "results"))
    ap.add_argument("--only", nargs="*", help="只跑這些測試名稱（不含 .S）")
    ap.add_argument("--src", help="RTL 原始碼資料夾（預設 ../src；突變測試用）")
    ap.add_argument("--maxcyc", type=int, default=20000000)
    a = ap.parse_args()
    work = os.path.join(a.out, "work")
    os.makedirs(work, exist_ok=True)

    srcdir = os.path.abspath(a.src) if a.src else os.path.join(ROOT, "src")
    srcs = [os.path.join(srcdir, f) for f in sorted(os.listdir(srcdir))
            if f.endswith(".v") and not f.startswith("rv32i_dut")]
    vvp = os.path.join(work, "tb_archtest.vvp")
    r = sh(["iverilog", "-g2005", "-o", vvp] + srcs + [os.path.join(ROOT, "sim", "tb_archtest.v")])
    if r.returncode:
        sys.exit("iverilog 編譯失敗:\n" + r.stderr)

    # 工作清單：(suite, name, src, envdir, march, 參考簽章來源)
    jobs = []
    a2 = os.path.abspath(a.arch_test)
    for suite in a.suite:
        sdir = os.path.join(a2, "riscv-test-suite", "rv32i_m", suite)
        for f in sorted(os.listdir(os.path.join(sdir, "src"))):
            if f.endswith(".S"):
                jobs.append(dict(suite=suite, name=f[:-2], src=os.path.join(sdir, "src", f), env=os.path.join(a2, "riscv-test-env"),
                                 march={"I": "rv32i", "M": "rv32im"}.get(suite, "rv32i"),
                                 ref=os.path.join(sdir, "references", f[:-2] + ".reference_output")))
    if a.arch_test3:
        a3 = os.path.abspath(a.arch_test3)
        for n in ZBB_TESTS:
            jobs.append(dict(suite="Zbb", name=n, src=os.path.join(a3, "riscv-test-suite", "rv32i_m", "B", "src", n + ".S"),
                             env=os.path.join(a3, "riscv-test-suite", "env"), march="rv32i_zbb", ref=None))
    if a.only:
        jobs = [j for j in jobs if j["name"] in a.only]

    results = []
    for j in jobs:
        suite, name = j["suite"], j["name"]
        tag = "%s/%s" % (suite, name)
        ent = {"suite": suite, "test": name, "unsupported": UNSUPPORTED.get(name),
               "reference": "official" if j["ref"] else "qemu"}
        base = os.path.join(work, "%s_%s" % (suite, name))
        r = build(j["src"], j["env"], j["march"], "link.ld", base + ".elf")
        if r.returncode:
            ent.update(status="BUILD_ERROR", detail=(r.stderr or r.stdout)[-400:]); results.append(ent); print("%-28s BUILD_ERROR" % tag); continue
        sh([OBJCOPY, "-O", "binary", "-j", ".text.init", "-j", ".text", base + ".elf", base + ".text.bin"])
        sh([OBJCOPY, "-O", "binary", "-j", ".data", base + ".elf", base + ".data.bin"])
        tw, dw = words_from_bin(base + ".text.bin"), words_from_bin(base + ".data.bin")
        write_hex(base + ".imem.hex", tw); write_hex(base + ".dmem.hex", dw)
        syms = symbols(base + ".elf")
        if not all(k in syms for k in ("begin_signature", "end_signature", "self_loop")):
            ent.update(status="BUILD_ERROR", detail="找不到 begin_signature / end_signature / self_loop"); results.append(ent); continue
        sigidx = (syms["begin_signature"] - DMEM_BASE) // 4
        siglen = (syms["end_signature"] - syms["begin_signature"]) // 4
        ent.update(text_words=len(tw), data_words=len(dw), sig_words=siglen)

        # 參考簽章
        if j["ref"]:
            exp = open(j["ref"]).read().split()
        else:
            rq = build(j["src"], j["env"], j["march"], "link_qemu.ld", base + ".q.elf")
            if rq.returncode:
                ent.update(status="BUILD_ERROR", detail="QEMU 版本編譯失敗: " + rq.stderr[-300:]); results.append(ent); continue
            exp = qemu_signature(base + ".q.elf", base + ".qsig")
        if a.validate_qemu and j["ref"]:
            rq = build(j["src"], j["env"], j["march"], "link_qemu.ld", base + ".q.elf")
            qs = qemu_signature(base + ".q.elf", base + ".qsig", cpu="rv32") if rq.returncode == 0 else []
            ent["qemu_matches_official"] = (qs == exp)

        out = base + ".sig"
        r = sh(["vvp", vvp, "+imem=" + base + ".imem.hex", "+dmem=" + base + ".dmem.hex", "+halt=%d" % syms["self_loop"],
                "+sigidx=%d" % sigidx, "+siglen=%d" % siglen, "+out=" + out, "+maxcyc=%d" % a.maxcyc])
        m = re.search(r"ARCHTEST cycles=(\d+) illegal=(\d+) status=OK", r.stdout)
        if not m:
            ent.update(status="SIM_ERROR", detail=r.stdout[-200:]); results.append(ent); print("%-28s SIM_ERROR" % tag); continue
        ent.update(cycles=int(m.group(1)), illegal=int(m.group(2)))
        got = open(out).read().split()
        ent["ref_words"] = len(exp)
        diff = compare(got, exp)
        ent["mismatch"] = len(diff)
        ent["first_diff"] = diff[:3]
        ent["status"] = "PASS" if not diff else "FAIL"
        results.append(ent)
        flag = ""
        if ent["unsupported"]:
            flag = "  [預期失敗：%s]" % ent["unsupported"] if diff else "  [不支援項目但通過]"
        if "qemu_matches_official" in ent:
            flag += "  [QEMU==官方: %s]" % ("是" if ent["qemu_matches_official"] else "否")
        print("%-28s %-5s cycles=%-7d illegal=%d sig=%d/%d mismatch=%d ref=%s%s" % (
            tag, ent["status"], ent["cycles"], ent["illegal"], len(got), len(exp), len(diff), ent["reference"], flag))

    json.dump(results, open(os.path.join(a.out, "summary.json"), "w"), indent=1, ensure_ascii=False)
    sup = [x for x in results if not x["unsupported"]]
    uns = [x for x in results if x["unsupported"]]
    print("\n支援範圍內：%d / %d PASS；不支援項目（預期失敗）：%d 支，其中 %d 支確實失敗" % (
        sum(x["status"] == "PASS" for x in sup), len(sup), len(uns), sum(x["status"] == "FAIL" for x in uns)))
    if a.validate_qemu:
        v = [x for x in results if "qemu_matches_official" in x]
        print("QEMU 參考模型驗證：%d / %d 支的 QEMU 簽章與官方 reference_output 完全相同" % (sum(x["qemu_matches_official"] for x in v), len(v)))
    bad = [x for x in sup if x["status"] != "PASS"]
    for x in bad:
        print("  非預期失敗：", x["suite"], x["test"], x["status"], x.get("first_diff", x.get("detail")))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
