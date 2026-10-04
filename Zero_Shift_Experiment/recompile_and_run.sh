#!/bin/bash
export PATH="$HOME/.local/bin:$PATH"
cd ..
python2 ~/.local/bin/scons --build-type=fast
cd Zero_Shift_Experiment
../nvmain.fast ../Config/RM.config trace_baseline.nvt 10000 > baseline_out_fixed.txt
grep "totalnumShifts\|transverse_reads\|DEBUG PIM" baseline_out_fixed.txt
