# constraints_standalone.xdc  --  只用於「單獨合成 CPU 核心」（頂層 rv32i_pipeline）
# =====================================================================
# 目標：PYNQ-ZU（Zynq UltraScale+），standalone synthesis，尚未指定腳位。
# 這份不是給整合設計（design_1）用的；整合設計請見 constraints.xdc（不需要額外約束）。
#
# 使用方式：把本檔加入新建專案的 Constraints，頂層設為 rv32i_pipeline，再執行 Synthesis。

# 100 MHz 時脈（10 ns）。若 WNS 很大（> 3 ns）可縮短週期（例如 6.0 ns 約 166 MHz）重新評估。
create_clock -name clk -period 10.0 [get_ports clk]

# rst_n 為非同步、低態有效的 reset，排除於時序分析之外。
set_false_path -from [get_ports rst_n]
