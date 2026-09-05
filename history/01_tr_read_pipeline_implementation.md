# Stage 1: TR_READ 基礎指令管道貫通 (Instruction Pipeline Implementation)

## 1. 問題描述 (Problem Description)
在原始 `NVMain-PIM` 代碼庫中，缺乏對跑道記憶體 (Racetrack Memory, RTM) 橫向讀取 (`TR_READ`) 近存計算指令的支援：
1. **未定義指令型別**：`NVMainRequestType` 列舉缺少 `TR_READ`，使指令無法在模擬器內部傳遞。
2. **Trace 檔案無法解析**：`NVMainTraceReader` 無法識別軌跡檔中的 `TR_READ` 字串，亦無法提取其第二位址 `address2`。
3. **PIM 路由斷路**：記憶體控制器 (`MemoryController`) 未建立針對 `TR_READ` 的排程管道，無法分發至子陣列命令佇列。
4. **底層缺少執行實作**：`SubArray` 與 `StandardRank` 未實作類比橫向讀取邏輯，硬體層級無法執行。
5. **統計計數缺失**：無法統計 `TR_READ` 呼叫次數與能耗指標。

---

## 2. 對應的具體改動 (Code Changes & Diffs)

### (1) 指令型別定義
* **檔案**：`include/NVMainRequest.h`
* **改動**：在請求類型列舉加入 `TR_READ`。
```cpp
// include/NVMainRequest.h
enum NVMainRequestType
{
    ...
    SRA,
    DRA,
    TRA,
    TR_READ,  // [NEW] 跑道記憶體近存計算橫向讀取指令
    ...
};
```

### (2) 軌跡檔讀取與解析
* **檔案**：`traceReader/NVMainTrace/NVMainTraceReader.cpp`
* **改動**：解析 `TR_READ` 指令字串與可選的雙位址欄位 `address2`。
```cpp
// traceReader/NVMainTrace/NVMainTraceReader.cpp
if( reqType == "TR_READ" )
{
    req->type = TR_READ;
    if( fieldCount >= 5 )
    {
        req->address2.SetPhysicalAddress( address2 );
    }
}
```

### (3) 主控層與統計對接
* **檔案**：`src/nvmain.cpp`
* **改動**：累加 `totalPIMRequests` 並進行 `address2` 位址翻譯。
```cpp
// src/nvmain.cpp
if( request->type == TR_READ )
{
    totalPIMRequests++;
    if( request->address2.GetPhysicalAddress() != 0 )
    {
        translator->Translate( request->address2.GetPhysicalAddress(), &(request->address2) );
    }
}
```

### (4) 記憶體控制器排程
* **檔案**：`src/MemoryController.cpp`
* **改動**：在 `IssueCommand` 中將 `TR_READ` 導向 `IssuePIMCommands`。
```cpp
// src/MemoryController.cpp
if( req->type == SRA || req->type == DRA || req->type == TRA || req->type == TR_READ )
{
    rv = IssuePIMCommands( req );
}
```

### (5) 統計計數器註冊
* **檔案**：`MemControl/RTM/RTM.h`, `MemControl/RTM/RTM.cpp`
* **改動**：宣告並註冊 `mem_TR_READs`。
```cpp
// MemControl/RTM/RTM.h
ncounter_t mem_TR_READs;

// MemControl/RTM/RTM.cpp
AddStat( mem_TR_READs );
if( req->type == TR_READ ) mem_TR_READs++;
```

### (6) Rank 與 SubArray 執行入口
* **檔案**：`Ranks/StandardRank/StandardRank.cpp`
```cpp
// Ranks/StandardRank/StandardRank.cpp
case TR_READ:
    GetChild( request )->IssueCommand( request );
    break;
```
* **檔案**：`src/SubArray.h`, `src/SubArray.cpp`
```cpp
// src/SubArray.h
bool TransverseRead( NVMainRequest *request );
ncounter_t transverse_reads;

// src/SubArray.cpp (基礎版)
bool SubArray::TransverseRead( NVMainRequest *request )
{
    ncycle_t tr_cycles = static_cast<ncycle_t>(std::ceil(5.0 * (static_cast<double>(p->CLK) / 1000.0)));
    GetEventQueue()->InsertEvent( EventResponse, this, request, GetEventQueue()->GetCurrentCycle() + tr_cycles );
    transverse_reads++;
    subArrayEnergy += 0.175; // 固有類比電流計算能耗 0.175 nJ
    activeEnergy += 0.175;
    return true;
}
```

---

## 3. 驗證與成效 (Verification & Impact)
* **編譯指令**：`python2 ~/.local/bin/scons --build-type=fast`
* **測試軌跡**：`bwt_pim_test.nvt`
* **成果**：
  * 指令通道全線貫通，編譯無警告錯誤。
  * 統計報表中精準產出 `mem_TR_READs 8` 與 `transverse_reads 8`。
  * 驗證了 5ns 時延換算（2000MHz 下為 10 週期）與 0.175nJ 類比能耗注入。
