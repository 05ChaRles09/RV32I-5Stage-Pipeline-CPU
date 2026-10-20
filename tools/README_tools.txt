gen_tests.py          產生 sim/zbb_vectors.mem、zbb_prog.hex、zbb_prog_expect.mem（含 MUL）
rv32i_model.py        ISA 黃金模型 + 迷你組譯器（RV32I + Zbb + MUL）
gen_illegal_hex.py    產生 sim/illegal.hex
gen_board_test.py     產生板測 PROGRAM / board_program.hex
verify_encodings.py   與 GNU binutils 比對編碼（需要 riscv 工具鏈，選用）
gen_bram_timing.py    產生 sim/bram_timing.hex、bram_timing_expect.mem（BRAM 同步讀取時序邊界的定向程式）
gen_coe.py            產生 bram_init/imem_board_program.coe、dmem_zero.coe（Block Memory Generator 初始化檔）
gen_bench.py          產生 XDOTP16 效益量測（dot / fir / matmul x S0 S1 S2 X）的程式、資料、預期結果到 sim/bench/
gen_bench_notebook.py 產生板上計時 Notebook pynq_5-stage-pipeline-CPU_TEST/RV32I_CPU_Benchmark.ipynb（需先跑 gen_bench.py 與 sim/run_bench.py）
run_archtest.py       riscv-arch-test 執行器：編譯官方測試、跑 sim/tb_archtest.v、與參考簽章比對（I/M 用官方、Zbb 用 QEMU）；
                      需要 gcc-riscv64-unknown-elf、qemu-system-misc、iverilog 與另外 clone 的 arch-test（見 docs/ARCH_TEST.md）
archtest_mutation.py  對 RTL 副本植入 10 種錯誤，確認 arch-test 會失敗（驗證測試本身的偵測能力）
