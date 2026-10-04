#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
cd Zero_Shift_Experiment

# Generate traces
python2 generate_bounded_shift_experiment.py

echo "--- Running Bounded Shift (max=8) Simulation ---"
../nvmain.fast ../Config/RM.config trace_bounded_8.nvt 10000 > bounded_8_out.txt
echo "Bounded 8 Total Shifts:"
grep "totalnumShifts" bounded_8_out.txt

echo "--- Running Bounded Shift (max=4) Simulation ---"
../nvmain.fast ../Config/RM.config trace_bounded_4.nvt 10000 > bounded_4_out.txt
echo "Bounded 4 Total Shifts:"
grep "totalnumShifts" bounded_4_out.txt

echo "--- Baseline (No Bounds) Total Shifts (For Reference) ---"
grep "totalnumShifts" baseline_out_fixed.txt
