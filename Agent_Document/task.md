# Task: Implement TR_READ in NVMain-PIM

- `[x]` Define `TR_READ` in `NVMainRequest.h`
- `[x]` Parse `TR_READ` in `NVMainTraceReader.cpp`
- `[x]` Translate `address2` and update PIM stats in `nvmain.cpp`
- `[x]` Route `TR_READ` correctly in `MemoryController.cpp`
- `[x]` Setup statistics for `TR_READ` in `MemControl/RTM/RTM.h` and `RTM.cpp`
- `[x]` Declare and implement `TransverseRead` timing and energy logic in `SubArray.h` and `SubArray.cpp`
- `[x]` Add routing and issue support for `TR_READ` in `Ranks/StandardRank/StandardRank.cpp`
- `[x]` Build the simulator with SCons (`python2 ~/.local/bin/scons --build-type=fast`)
- `[x]` Verify simulation timing, energy, and statistics output using `bwt_pim_test.nvt`
