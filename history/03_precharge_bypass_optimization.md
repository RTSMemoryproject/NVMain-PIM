# Stage 3: 繞過連續 TR_READ 預充電延遲 (Precharge Bypass Optimization)

## 1. 問題描述 (Problem Description)
在 Stage 2 修復移位機制後，審查發現底層狀態機仍存在傳統 DRAM 行約束的冗餘延遲問題：
* **缺陷成因**：在 `MemoryController::IssuePIMCommands` 中：
  ```cpp
  if(activeSubArray[rank][bank][subarray] && (req->type == SRA || req->type == DRA || req->type == TRA || req->type == TR_READ)){
      commandQueues[queueId].push_back( MakePrechargeRequest( req ) );
  }
  ```
  每當連續發出 `TR_READ` 且子陣列已打開時，控制器強制插入了一個 `PRECHARGE` 指令！
* **物理矛盾**：跑道記憶體 (RTM) 是**非揮發性記憶體 (NVM)**，且 `TR_READ` 是利用克希荷夫電路定律在位元線上讀取類比電流的**非破壞性讀取**。不需要像破壞性讀取的傳統 DRAM 一樣在每次操作前發出 Precharge 關閉行並重置位元線電壓。
* **負面影響**：在 `bwt_pim_test.nvt` 模擬中產生了 8 次無謂的預充電，使流水線遭遇多次 $tRP$ 週期懲罰，並消耗額外的預充電能量。
* **連鎖阻礙**：若僅移除控制器的預充電，`SubArray::IsIssuable` 和 `SubArray::TransverseRead` 內部硬編碼了 `state == SUBARRAY_CLOSED` 的防護檢查，會直接攔截並報錯。

---

## 2. 對應的具體改動 (Code Changes & Diffs)

### (1) 記憶體控制器層級
* **檔案**：`src/MemoryController.cpp`
* **改動**：從強制插入預充電的條件中移除 `req->type == TR_READ`。
```diff
--- a/src/MemoryController.cpp
+++ b/src/MemoryController.cpp
@@ -1630,7 +1630,7 @@ bool MemoryController::IssuePIMCommands( NVMainRequest *req )
     ncounter_t queueId = GetCommandQueueId(req->address);
 
     //If not overlap, the subarray should not be active
-    if(activeSubArray[rank][bank][subarray] && (req->type == SRA || req->type == DRA ||  req->type == TRA || req->type == TR_READ)){
+    if(activeSubArray[rank][bank][subarray] && (req->type == SRA || req->type == DRA ||  req->type == TRA)){
         commandQueues[queueId].push_back( MakePrechargeRequest( req ) );
     }
```

### (2) 子陣列層級可發行性解耦
* **檔案**：`src/SubArray.cpp`（`SubArray::IsIssuable`）
* **改動**：將非破壞性的 `TR_READ` 與需要 Precharge 的 DRAM 啟動指令分離，允許在 `state == SUBARRAY_OPEN` 時發行。
```diff
--- a/src/SubArray.cpp
+++ b/src/SubArray.cpp
@@ -1606,6 +1606,29 @@ bool SubArray::IsIssuable( NVMainRequest *req, FailReason *reason )
+    if( req->type == TR_READ )
+    {
+        /* TR_READ can issue back-to-back without precharge in non-volatile RTM */
+        if( nextActivate > (GetEventQueue()->GetCurrentCycle())
+            || (p->WritePausing && isWriting && writeRequest->flags & NVMainRequest::FLAG_FORCED)
+            || (p->WritePausing && isWriting && !(req->flags & NVMainRequest::FLAG_PRIORITY)) )
+        {
+            rv = false;
+            if( reason ) 
+                reason->reason = SUBARRAY_TIMING;
+        }
+
+        if( rv == false )
+        {
+            if( nextActivate > (GetEventQueue()->GetCurrentCycle()) )
+            {
+                actWaits++;
+                actWaitTotal += nextActivate - (GetEventQueue()->GetCurrentCycle() );
+            }
+        }
+    }
+    else if( req->type == ACTIVATE || req->type == TRA || req->type == DRA || req->type == SRA )
```

### (3) 子陣列執行防護與時序約束維護
* **檔案**：`src/SubArray.cpp`（`SubArray::TransverseRead`）
* **改動**：移除 `state != SUBARRAY_CLOSED` 限制，並將 `nextActivate` 推進 `total_cycles`，確保背靠背指令不發生管線衝突。
```diff
--- a/src/SubArray.cpp
+++ b/src/SubArray.cpp
@@ -2110,11 +2110,6 @@ bool SubArray::TransverseRead( NVMainRequest *request )
     if( nextActivate > GetEventQueue()->GetCurrentCycle() )
     {
         std::cerr << "NVMain Error: SubArray violates ACTIVATION timing constraint!" << std::endl;
         return false;
     }
-    else if( p->UsePrecharge && state != SUBARRAY_CLOSED )
-    {
-        std::cerr << "NVMain Error: try to open a subarray that is not idle!" << std::endl;
-        return false;
-    }
...
     // 2. TIMING CONSTRAINTS UPDATING
+    nextActivate = MAX( nextActivate, GetEventQueue()->GetCurrentCycle() + total_cycles );
     nextPrecharge = MAX( nextPrecharge, GetEventQueue()->GetCurrentCycle() + total_cycles );
```

---

## 3. 驗證與成效 (Verification & Impact)
* **測試軌跡**：`bwt_pim_test.nvt`
* **指標演進對比**：
  * `precharges`：由 8 次大幅降為 **0 次**（所有冗餘預充電全數歸零）。
  * `transverse_reads`：維持精確的 8 次。
  * `totalnumShifts`：維持 480，動態移位物理特性完好保留。
  * 模擬總週期由 271 週期縮減至 **267 週期**（完全消除了無謂的 $tRP$ 等待氣泡，實現背靠背無縫執行）。
