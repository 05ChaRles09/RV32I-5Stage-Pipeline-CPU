#!/bin/bash
# run_xsim.sh  用 Vivado 的 xsim 以命令列一次跑完全部 11 個 testbench（Linux；選用）
#   先 source Vivado 環境：  source /tools/Xilinx/Vivado/2022.2/settings64.sh
#   再在 sim/ 執行：          ./run_xsim.sh
# 注意：作者尚未在實際 Vivado 環境執行過本腳本；有問題請改用 GUI（見 docs/VIVADO_GUIDE.md）。
cd "$(dirname "$0")" || exit 99
command -v xvlog >/dev/null || { echo "找不到 xvlog，請先 source Vivado 的 settings64.sh"; exit 99; }
mkdir -p .xsim_work
SRCS="$(ls ../src/*.v) ../axi/rv32i_pipelined_cpu_v1_0_S00_AXI.v ../axi/rv32i_pipelined_cpu_v1_0.v bmg_tdp_model.v"
nfail=0
for tb in tb_rv32i_pipeline tb_jalr tb_extra_branches tb_load_use_branch tb_illegal tb_zbb_unit tb_zbb_prog tb_board_program tb_imem_default tb_bram_timing tb_axi_bram_system; do
  echo "==== $tb"
  xvlog $SRCS $tb.v -log .xsim_work/${tb}_xvlog.log >/dev/null 2>&1
  xelab -debug off $tb -s ${tb}_snap -log .xsim_work/${tb}_xelab.log >/dev/null 2>&1
  xsim ${tb}_snap -runall -log .xsim_work/${tb}_xsim.log >/dev/null 2>&1
  if grep -Eq "ALL .*PASSED" .xsim_work/${tb}_xsim.log; then echo "  PASS"; else echo "  FAIL  (詳見 .xsim_work/${tb}_xsim.log)"; nfail=$((nfail+1)); fi
done
echo; echo "失敗的 testbench 數量: $nfail"
exit $nfail
