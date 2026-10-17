@echo off
REM ============================================================================
REM  run_xsim.bat  用 Vivado 的 xsim 以命令列一次跑完全部 9 個 testbench（選用；也可在 Vivado GUI 逐一執行）
REM
REM  使用方式
REM    1. 先載入 Vivado 環境，例如：  C:\Xilinx\Vivado\2022.2\settings64.bat
REM    2. 在 sim\ 目錄執行：          run_xsim.bat
REM  結果：每個 testbench 顯示 PASS / FAIL，完整輸出在 .xsim_work\*.log。結束碼 = 失敗的 testbench 數量。
REM  注意：本腳本以標準 xvlog / xelab / xsim 指令撰寫，作者尚未在實際 Vivado 環境中執行過；
REM        若有問題，請改用 GUI（見 docs\VIVADO_GUIDE.md）。
REM ============================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"
where xvlog >nul 2>nul
if errorlevel 1 (
  echo 找不到 xvlog，請先執行 Vivado 的 settings64.bat
  exit /b 99
)
if not exist .xsim_work mkdir .xsim_work
set SRCS=
for %%F in (..\src\*.v) do set SRCS=!SRCS! %%F
set SRCS=!SRCS! ..\axi\rv32i_pipelined_cpu_v1_0_S00_AXI.v ..\axi\rv32i_pipelined_cpu_v1_0.v bmg_tdp_model.v
set TBS=tb_rv32i_pipeline tb_jalr tb_extra_branches tb_load_use_branch tb_illegal tb_zbb_unit tb_zbb_prog tb_board_program tb_imem_default tb_bram_timing tb_axi_bram_system
set NFAIL=0
for %%T in (%TBS%) do (
  echo ==== %%T
  call xvlog !SRCS! %%T.v -log .xsim_work\%%T_xvlog.log >nul 2>&1
  call xelab -debug off %%T -s %%T_snap -log .xsim_work\%%T_xelab.log >nul 2>&1
  call xsim %%T_snap -runall -log .xsim_work\%%T_xsim.log >nul 2>&1
  findstr /R /C:"ALL .*PASSED" .xsim_work\%%T_xsim.log >nul
  if errorlevel 1 (
    echo   FAIL   ^(詳見 .xsim_work\%%T_xsim.log^)
    set /a NFAIL+=1
  ) else (
    echo   PASS
  )
)
echo.
echo 失敗的 testbench 數量: %NFAIL%
exit /b %NFAIL%
