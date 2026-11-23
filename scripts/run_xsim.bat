@echo off
REM Run the FIFO testbench with Vivado xsim (Windows).
REM Usage: scripts\run_xsim.bat        (run from the repo root, with Vivado's bin on PATH)
setlocal
set ROOT=%~dp0..
if not exist "%ROOT%\sim" mkdir "%ROOT%\sim"
cd /d "%ROOT%\sim"

call xvlog -sv ..\rtl\design.v ..\testbench\testbench.sv || exit /b 1
call xelab testbench -s tb_sim -debug typical || exit /b 1
call xsim tb_sim -R -log sim.log
endlocal
