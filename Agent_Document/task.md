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
- `[x]` Fix Issue 1: Implement Dynamic Domain Wall Shift Mechanism in `SubArray::TransverseRead`
- `[x]` Fix Issue 2: Bypass redundant DRAM-style PRECHARGE penalties for consecutive `TR_READ`s in `MemoryController.cpp` and `SubArray.cpp`
- `[x]` **Phase 1 硬體驗證審計最終驗收與正式簽核 (FULL PASS & SIGN-OFF)** (詳見 [`code_audit_report.md`](file:///e:/NVMain-PIM/Agent_Document/code_audit_report.md))：
  - `[x]` 修復 `MemoryController::IssuePIMCommands` 未賦值 `req->issueCycle` 引發之假死鎖崩潰漏洞
  - `[x]` 在 `SubArray::NextIssuable` 補上 `TR_READ` 週期回傳 (杜絕控制器忙輪詢，已驗證)
  - `[x]` 在 `SubArray::TransverseRead` 實作 `address2` 次行磁疇移位與能耗累加（落實克希荷夫雙行疊加物理模型）
  - `[x]` 修復 `abs()` 無號整數減法下溢與急切更新模式（Eager）雙向移位時延計算
  - `[x]` 為 `rwPortPos` 存取埠及 DBC 索引增加物理邊界防護與防溢位機制

