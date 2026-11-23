#!/usr/bin/env bash
# Run the FIFO testbench with Vivado xsim (Linux / Git Bash).
# Usage: ./scripts/run_xsim.sh   (Vivado's bin directory must be on PATH)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/sim"
cd "$ROOT/sim"

xvlog -sv ../rtl/design.v ../testbench/testbench.sv
xelab testbench -s tb_sim -debug typical
xsim tb_sim -R -log sim.log
