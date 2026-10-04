#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
cd Zero_Shift_Experiment
../nvmain.fast ../Config/RM.config trace_padded.nvt 10000 > padded_out_fixed.txt
echo "Baseline Total Shifts:"
grep "totalnumShifts" baseline_out_fixed.txt
echo "Padded Total Shifts:"
grep "totalnumShifts" padded_out_fixed.txt
