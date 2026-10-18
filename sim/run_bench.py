#!/usr/bin/env python3
"""run_bench.py  用 iverilog 對 sim/bench/ 的每支 benchmark 程式跑 tb_bench，彙整成 bench/bench_results.json。
   需要：iverilog、vvp、先執行 tools/gen_bench.py。重複版本（rep2 / rep3）用來確認「每次重複的週期數」是常數。"""
import json, os, re, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
os.chdir(here)
srcs = [os.path.join("..", "src", f) for f in sorted(os.listdir("../src")) if f.endswith(".v") and not f.startswith("rv32i_dut")]
subprocess.check_call(["iverilog", "-g2005", "-o", "/tmp/tb_bench.vvp"] + srcs + ["tb_bench.v"])
m = json.load(open("bench/bench_manifest.json"))

def sim(prog_file, spin, kernel, fmt, tag):
    out = subprocess.run(["vvp", "/tmp/tb_bench.vvp", "+hex=bench/" + prog_file, "+dmem=bench/%s_%s.dmem.mem" % (kernel, fmt),
                          "+expect=bench/%s_%s.expect.mem" % (kernel, fmt), "+spin=%d" % spin, "+tag=" + tag],
                         capture_output=True, text=True).stdout
    mm = re.search(r"BENCH tag=\S+ cycles=(\d+) stall=(\d+) flush=(\d+) mismatch=(\d+)", out)
    if not mm: raise SystemExit("no result for %s:\n%s" % (tag, out))
    c, s, f, bad = map(int, mm.groups())
    return {"cycles": c, "stall": s, "flush": f, "mismatch": bad}

res = []
fail = 0
for p in m["programs"]:
    r = sim(p["file"], p["spin_pc"], p["kernel"], p["fmt"], "%s_%s" % (p["kernel"], p["var"]))
    reps = {}
    for R, rp in p["reps"].items():
        reps[R] = sim(rp["file"], rp["spin_pc"], p["kernel"], p["fmt"], "%s_%s_rep%s" % (p["kernel"], p["var"], R))
    period = reps["3"]["cycles"] - reps["2"]["cycles"]
    entry = dict(p); entry.update(r); entry["reps_result"] = reps; entry["rep_period"] = period
    entry["mismatch_all"] = r["mismatch"] + sum(v["mismatch"] for v in reps.values())
    fail += entry["mismatch_all"] != 0
    res.append(entry)
    print("%-7s %-2s cycles=%5d (instr %5d, stall %3d, flush %3d)  rep 週期=%5d  mismatch=%d" % (
        p["kernel"], p["var"], r["cycles"], p["n_instr"], r["stall"], r["flush"], period, entry["mismatch_all"]))
json.dump(res, open("bench/bench_results.json", "w"), indent=1)
print("FAILED programs: %d" % fail)
sys.exit(1 if fail else 0)
