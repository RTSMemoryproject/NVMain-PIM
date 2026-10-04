#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
cd Zero_Shift_Experiment

echo "--- 1. Running Baseline (DBC=32) Simulation ---"
../nvmain.fast ../Config/RM_DBC32.config trace_baseline.nvt 10000 > baseline_dbc32_out.txt
echo "Baseline DBC=32 Track-Shifts:"
grep "totalnumShifts" baseline_dbc32_out.txt

echo "--- 2. Running Bucket-Size (DBC=512) Simulation ---"
../nvmain.fast ../Config/RM.config trace_baseline.nvt 10000 > baseline_dbc512_out.txt
echo "Bucket-Size DBC=512 Track-Shifts:"
grep "totalnumShifts" baseline_dbc512_out.txt

echo "--- 3. Running Bucket-Size + Padding (DBC=512, Bounded 8) Simulation ---"
../nvmain.fast ../Config/RM.config trace_bounded_8.nvt 10000 > bounded_dbc512_out.txt
echo "Bounded DBC=512 Track-Shifts:"
grep "totalnumShifts" bounded_dbc512_out.txt
