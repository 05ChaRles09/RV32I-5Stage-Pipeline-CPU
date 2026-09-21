# constraints.xdc RV32I pipeline CPU synthesis constraints
# Target: PYNQ-ZU (Zynq UltraScale+), standalone synthesis (no pin assignment yet)
#
# Usage: Add as a constraints source in Vivado, then Run Synthesis.

# 100 MHz clock (10 ns period). Conservative for a first pass on ZU.
# If WNS is large (> 3 ns), you can tighten this to 6.0 ns (~166 MHz) and re-run.
create_clock -name clk -period 10.0 [get_ports clk]

# rst_n is an asynchronous active-low reset; exclude from timing analysis.
set_false_path -from [get_ports rst_n]
