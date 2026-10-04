#!/bin/bash
../nvmain.fast ../Config/RM.config trace_baseline.nvt 10000 > baseline_out.txt
grep "totalnumShifts" baseline_out.txt
grep "DEBUG PIM:" baseline_out.txt | head -n 10
