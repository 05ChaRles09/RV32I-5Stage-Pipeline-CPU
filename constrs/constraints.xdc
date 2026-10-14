# constraints.xdc  --  PYNQ-ZU 整合設計（design_1 / design_1_wrapper）
# =====================================================================
# 結論：目前這個設計「不需要」額外的 XDC 才能 Implementation / 產生 bitstream。
#
# 原因（已由 Vivado 報告驗證）：
#   * CPU 的 clk / rst_n 不是 FPGA 外部腳位。時脈來自 Zynq UltraScale+ PS 的 pl_clk0（100 MHz），
#     reset 由 AXI 暫存器 CTRL[0] 控制。util 報告 Bonded IOB = 0，代表設計沒有使用任何外部 I/O 腳位。
#   * PS 的 PL 時脈約束由 Zynq PS IP 自動產生：
#       clk_pl_0  <- design_1_i/zynq_ultra_ps_e_0/inst/pl_clk_unbuffered[0]，週期 10.0 ns
#     （見 power / timing 報告的 Clock Constraints 區段），不需要手寫 create_clock。
#   * AXI4-Lite 與 PS 之間的路徑皆在同一個時脈網域內。
#
# 使用方式：
#   * 整合設計（Block Design）：不要把舊版的 clk / rst_n 約束加入 Vivado 專案，
#     否則會出現「No ports matched 'clk'」的 Critical Warning。此檔案保留為說明文件，也可以直接加入專案（內容全為註解，無影響）。
#   * 想單獨合成 CPU 核心（頂層 rv32i_pipeline，有 clk / rst_n 外部 port）：改用 constraints_standalone.xdc。
#
# 想改變 CPU 的運作頻率：
#   在 Block Design 開啟 Zynq UltraScale+ PS 的設定 → Clock Configuration → PL Fabric Clocks，
#   修改 PL0 的頻率（目前 100 MHz）。依 setup slack +1.977 ns 粗估上限約 125 MHz（估算值，需實際跑 Implementation 驗證，
#   且 hold slack 目前僅 +0.001 ns，改頻率後請重新檢查 WNS / WHS）。
#
# 若日後新增外部 I/O（例如 LED / UART），在此加入 PACKAGE_PIN 與 IOSTANDARD，範例（請依 PYNQ-ZU 原理圖確認腳位後再啟用）：
#   # set_property PACKAGE_PIN <PIN>  [get_ports <port_name>]
#   # set_property IOSTANDARD LVCMOS33 [get_ports <port_name>]
