# Stage 2: 動態磁疇移位機制修復 (Dynamic Domain Wall Shift Mechanism)

## 1. 問題描述 (Problem Description)
在 Stage 1 完成基礎管線後，審查發現底層物理狀態機存在「零移位物理悖論」（Zero-Shift Paradox）：
* **缺陷成因**：`SubArray::TransverseRead` 僅套用了固定的 5ns 類比感測時延，但**完全未觸發 RTM 奈米線的磁疇移位操作**。
* **物理矛盾**：在跑道記憶體中，目標資料必須先經由奈米線上的自旋轉移矩（Spin-Transfer Torque, STT）流動，將目標磁疇移動到固定存取埠（Access Port）下方方可讀取。
* **模擬失真**：測試結果中 `shiftReqs` 僅有寫入產生的 3 次，8 次 `TR_READ` 完全沒有產生任何移位請求與移位能耗（`totalnumShifts` 僅有 96，`shiftEnergy` 僅有 0.0585 nJ），嚴重低估實際延遲與功耗。

---

## 2. 對應的具體改動 (Code Changes & Diffs)

### 檔案：`src/SubArray.cpp`（`SubArray::TransverseRead`）
* **改動內容**：
  1. 調用 `FindClosestPort(dbc, dom)` 找出距離目標磁疇最近的存取埠。
  2. 計算目標磁疇與當前存取埠的距離 $D = |\text{rwPortPos}[\text{dbc}][\text{port}] - \text{dom}|$。
  3. 同步平移該 DBC 奈米線上的其他次要存取埠。
  4. 根據 `LazyPortUpdate` 策略更新存取埠位置與字長移位數：
     * Lazy 模式：`numShifts = dist * wordSize`，存取埠停留在 `dom`。
     * Eager 模式：`numShifts = dist * wordSize * 2`，存取埠返回初始位置。
  5. 動態累加移位時延 $\text{shift\_cycles} = D \times tSH$ 及移位能耗 $\text{shift\_energy} = D \times Esh$。
  6. 總延遲設置為 $\text{total\_cycles} = \text{shift\_cycles} + \text{tr\_cycles}$，並同步推進事件回調與時序約束。

```diff
--- a/src/SubArray.cpp
+++ b/src/SubArray.cpp
@@ -2120,6 +2120,60 @@ bool SubArray::TransverseRead( NVMainRequest *request )
+    ncycle_t shift_cycles = 0;
+    double shift_energy = 0.0;
+
+    /* Dynamic Domain Wall Shift Mechanism for Racetrack Memory */
+    if( p->MemIsRTM )
+    {
+        ncounter_t port = FindClosestPort( dbc, dom );
+        ncounter_t dist = abs( rwPortPos[dbc][port] - dom );
+
+        for( ncounter_t i = 0; i < nPorts; i++ )
+        {
+            if( i != port )
+            {
+                if( rwPortPos[dbc][port] < int(dom) )
+                    rwPortPos[dbc][i] += dist;
+                else
+                    rwPortPos[dbc][i] -= dist;
+            }
+        }
+
+        numShifts = dist;
+        if( LazyPortUpdate )
+        {
+            numShifts *= wordSize;
+            rwPortPos[dbc][port] = dom;
+        }
+        else
+        {
+            numShifts *= wordSize * 2;
+            rwPortPos[dbc][port] = rwPortInitPos[dbc][port];
+        }
+
+        totalnumShifts += numShifts;
+
+        /* Dynamic Latency = D * tSH */
+        shift_cycles = dist * p->tSH;
+
+        /* Dynamic Energy = D * Esh */
+        if( p->EnergyModel == "current" )
+        {
+            shift_energy = ( ( p->EIDD4R - p->EIDD3N ) * (double)(p->tBURST) ) / (double)(p->BANKS);
+        }
+        else
+        {
+            shift_energy = p->Esh * ( numShifts / wordSize );
+        }
+
+        subArrayEnergy += shift_energy;
+        shiftEnergy += shift_energy;
+        shiftReqs++;
+    }
+
     ncycle_t tr_cycles = static_cast<ncycle_t>(std::ceil(5.0 * (static_cast<double>(p->CLK) / 1000.0)));
-    ncycle_t total_cycles = tr_cycles;
+    ncycle_t total_cycles = shift_cycles + tr_cycles;
```

---

## 3. 驗證與成效 (Verification & Impact)
* **測試軌跡**：`bwt_pim_test.nvt`
* **指標演進對比**：
  * `shiftReqs`：由 3 增至 **11**（3 次寫入 + 8 次 TR_READ 移位，100% 吻合）。
  * `totalnumShifts`：由 96 增至 **480**（動態增加了 384 個磁疇移位步數）。
  * `shiftEnergy`：由 0.0585 nJ 增至 **0.2925 nJ**（精確增加了 0.234 nJ 移位能耗）。
  * `subArrayEnergy`：由 43.5917 nJ 增至 **43.8257 nJ**。
  * 模擬總週期由 265 正常推遲至 271 週期，真實呈現奈米線磁疇移動的物理延遲！
