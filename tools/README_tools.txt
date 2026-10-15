gen_tests.py          產生 sim/zbb_vectors.mem、zbb_prog.hex、zbb_prog_expect.mem（含 MUL）
rv32i_model.py        ISA 黃金模型 + 迷你組譯器（RV32I + Zbb + MUL）
gen_illegal_hex.py    產生 sim/illegal.hex
gen_board_test.py     產生板測 PROGRAM / board_program.hex
verify_encodings.py   與 GNU binutils 比對編碼（需要 riscv 工具鏈，選用）
gen_bram_timing.py    產生 sim/bram_timing.hex、bram_timing_expect.mem（BRAM 同步讀取時序邊界的定向程式）
