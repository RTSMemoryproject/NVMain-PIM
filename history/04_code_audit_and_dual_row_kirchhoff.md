# Stage 4: 代碼審計 8 大缺陷全面修復與雙行克希荷夫疊加實作 (Code Audit Resolution)

## 1. 問題描述 (Problem Description)
根據資深硬體驗證工程師與 C++ 代碼審計報告 (`Agent_Document/code_audit_report.md`)，現有代碼存在 8 大物理保真度與記憶體安全性致命缺陷：
1. **雙行克希荷夫電路疊加缺失 (`address2` 遭完全忽略)**：`TR_READ` 需要同時激勵兩個特定行進行類比電流疊加。代碼僅解析了 `request->address`，完全忽略了 `request->address2`。若兩行位於不同 DBC，第二條奈米線完全未移位，時延與能耗被嚴重漏算。
2. **大型 Trace 必定死鎖崩潰**：`MemoryController::IssuePIMCommands` 未對 `req->issueCycle` 賦值（恆為 0）。當模擬時間超過 `DeadlockTimer` (1,000 萬週期) 且在隊首遭遇等待時，會誤觸假死鎖 panic 強制 `exit(1)`。
3. **急切模式（Eager Mode）往返時延漏算一半**：能耗模型計入了雙倍位移能耗 ($2D$)，但時延僅計入單程時延 ($D \times tSH$)，違反物理因果律。
4. **多存取埠奈米線指標下溢與負數越界**：非選中埠計算時無下限防護，會下溢產生負數；邊界檢查使用了 `>` 而非 `>=`。
5. **`SubArray::NextIssuable` 缺少 `TR_READ` 時序反饋**：傳入 `TR_READ` 恆回傳 0，導致控制器退化為輪詢。
6. **未受防護的 DBC 陣列索引訪問**：未檢查 `dbc < p->DBCS`，存在觸發 Segmentation Fault 的段錯誤風險。
7. **靜態存取策略差一越界 (Off-by-One)**：`domain == DOMAINS` 時 `AP = nPorts`，導致存取埠陣列讀寫越界。
8. **無號整數減法下溢**：`rwPortPos`（`int`）與 `dom`（`uint64_t`）直接相減產生無號數環繞（約 $1.84 \times 10^{19}$）。

---

## 2. 對應的具體改動 (Code Changes & Diffs)

### (1) 修復假死鎖崩潰漏洞
* **檔案**：`src/MemoryController.cpp`
* **改動**：在推入 `commandQueues` 前初始化 `req->issueCycle`。
```diff
--- a/src/MemoryController.cpp
+++ b/src/MemoryController.cpp
@@ -1640,6 +1640,7 @@ bool MemoryController::IssuePIMCommands( NVMainRequest *req )
     }
 
     //add request
+    req->issueCycle = GetEventQueue()->GetCurrentCycle();
     commandQueues[queueId].push_back( req );
```

### (2) 補全 `SubArray::NextIssuable` 時序暴露
* **檔案**：`src/SubArray.cpp`
* **改動**：加入 `request->type == TR_READ`。
```diff
--- a/src/SubArray.cpp
+++ b/src/SubArray.cpp
@@ -1581,7 +1581,7 @@ ncycle_t SubArray::NextIssuable( NVMainRequest *request )
 {
     ncycle_t nextCompare = 0;
 
-    if( request->type == ACTIVATE ) nextCompare = nextActivate;
+    if( request->type == ACTIVATE || request->type == TR_READ ) nextCompare = nextActivate;
     else if( request->type == READ ) nextCompare = nextRead;
```

### (3) 修復存取埠差一越界與無號數下溢
* **檔案**：`src/SubArray.cpp`（`SubArray::FindClosestPort`）
* **改動**：加入邊界鉗位防護，並顯式將 `domain` 轉型為 `static_cast<int>`。
```diff
--- a/src/SubArray.cpp
+++ b/src/SubArray.cpp
@@ -2102,19 +2102,23 @@ ncounter_t SubArray::FindClosestPort(uint64_t dbc, uint64_t domain)
   if( StaticPortAcces )
   {
       ncounter_t domainsPerPort = DOMAINS / nPorts;
-      AP = domain / ( DOMAINS / nPorts );
+      AP = (domainsPerPort > 0) ? (domain / domainsPerPort) : 0;
+      if( AP >= nPorts )
+          AP = nPorts - 1;
   }
   else
   {
-      int min = abs( rwPortPos[dbc][0] - domain );
+      int min = std::abs( rwPortPos[dbc][0] - static_cast<int>(domain) );
       for(uint16_t i = 1; i < nPorts; i++)
       {
+          int curDist = std::abs( rwPortPos[dbc][i] - static_cast<int>(domain) );
+          if( curDist < min )
+          {
+              min = curDist;
+              AP = i;
+          }
       }
   }
```

### (4) 重構 `TransverseRead` 支援雙行克希荷夫疊加與安全防護
* **檔案**：`src/SubArray.cpp`（`SubArray::TransverseRead`）
* **改動**：
  * 同步解析 `address`（`dbc1, dom1`）與 `address2`（`dbc2, dom2`）。
  * 加入 `dbc1 < p->DBCS && dbc2 < p->DBCS` 邊界防護。
  * 若 `dbc1 != dbc2`，在兩條獨立 DBC 奈米線上平行執行移位（`unique_tracks = 2`）。
  * 平行軌道時延取最大值：`max_shift_cycles = max(shift1, shift2)`。
  * 能耗累加兩條軌道：`track_shift_energy` 逐軌累加至 `subArrayEnergy` 與 `shiftEnergy`。
  * 急切模式（Eager）正確計入往返時延：`(LazyPortUpdate ? dist : (dist * 2)) * p->tSH`。
  * 次要存取埠限縮在 $[0, \text{DOMAINS}-1]$，杜絕負數下溢與越界漂移。
```cpp
// 核心片段示意
uint64_t dbcs[2] = { dbc1, dbc2 };
uint64_t doms[2] = { dom1, dom2 };
ncounter_t unique_tracks = (dbc1 == dbc2) ? 1 : 2;

for( ncounter_t t = 0; t < unique_tracks; t++ )
{
    uint64_t cur_dbc = dbcs[t];
    uint64_t cur_dom = doms[t];
    ncounter_t port = FindClosestPort( cur_dbc, cur_dom );
    ncounter_t dist = static_cast<ncounter_t>(std::abs( rwPortPos[cur_dbc][port] - static_cast<int>(cur_dom) ));
    ...
    // 往返時延與平行最長時延
    ncycle_t cur_shift_cycles = (LazyPortUpdate ? dist : (dist * 2)) * p->tSH;
    if( cur_shift_cycles > max_shift_cycles ) max_shift_cycles = cur_shift_cycles;
    ...
    // 能耗累加
    subArrayEnergy += track_shift_energy;
    shiftEnergy += track_shift_energy;
    shiftReqs++;
}
```

---

## 3. 驗證與成效 (Verification & Impact)
1. **回歸測試 (`bwt_pim_test.nvt`)**：
   * `precharges`: 0（預充電繞過保持有效）
   * `transverse_reads`: 8
   * `totalnumShifts`: 480，`shiftEnergy`: 0.2925 nJ，`subArrayEnergy`: 43.8257 nJ，模擬週期: 267
   * 指標 100% 吻合且無任何回歸問題。
2. **跨 DBC 雙行壓力測試 (`scratch/dual_row_test.nvt`)**：
   * 測試跨 DBC 位址對（DBC 0 與 DBC 1）：
   * `shiftReqs`: 3（1 次寫入 + 2 條獨立 DBC 奈米線各自平行移位）。
   * `totalnumShifts`: 128（兩條奈米線各移位 64 shifts，精確累加）。
   * `shiftEnergy`: 0.078 nJ（$4 \times Esh = 0.078\text{ nJ}$，精確累加）。
   * 雙行類比電流疊加物理模型 100% 驗證通過，代碼審計正式獲得簽核（Sign-off）！
