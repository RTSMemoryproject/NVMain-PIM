# TR_READ 验证报告与待办修复清单

本报告针对横向读取 (`TR_READ`) 的 C++ 实现逻辑进行审查。目前 `nvmain.fast` 已成功建置，动态时延换算 (5ns -> cycles) 与扁平能耗 (0.175nJ) 已正确实作于 `src/SubArray.cpp`，且已成功绕过 PIM 路由。

然而，目前底层的物理状态机仍存在以下两大缺陷，需要优先修复：

> [!TIP]
> **1. “零移位”的物理悖论 (缺失移位机制) [已修复 - FIXED]**
> - **位置**: `src/SubArray.cpp` 中的 `TransverseRead` 方法。
> - **状态**: 已成功实作动态磁畴移位机制。
> - **验证结果**:
>   - 每次 `TR_READ` 在套用 5ns 類比時延前，動態計算目標磁疇與 `rwPortPos` 存取埠的距離 $D$。
>   - 動態累加移位時延 $D \times tSH$ 及移位能耗 $D \times Esh$。
>   - 在 `bwt_pim_test.nvt` 驗證中：
>     - `shiftReqs`: 3 -> 11 (8 次 TR_READ 均成功觸發動態移位)
>     - `totalnumShifts`: 96 -> 480 (+384 磁疇移位數)
>     - `shiftEnergy`: 0.0585nJ -> 0.2925nJ (+0.234nJ 移位能耗)
>     - `subArrayEnergy`: 43.5917nJ -> 43.8257nJ
>     - `activeEnergy`: 1.4801nJ (固有類比計算能耗維持不變)
>     - 退出週期正常推移至 cycle 271，100% 符合硬體架構物理規範。

> [!TIP]
> **2. 冗余的 DRAM 式预充电惩罚 [已修复 - FIXED]**
> - **位置**: `src/MemoryController.cpp` 的 `IssuePIMCommands` 及 `src/SubArray.cpp` 的 `IsIssuable` / `TransverseRead`。
> - **状态**: 已成功解耦 DRAM 式破坏性行激活约束，实现背靠背 (back-to-back) 连续横向读取。
> - **验证结果**:
>   - 在 `MemoryController::IssuePIMCommands` 中移除對 `TR_READ` 的強制 `MakePrechargeRequest`。
>   - 在 `SubArray::IsIssuable` 與 `TransverseRead` 中允許在子陣列已打開時直接發出非破壞性 `TR_READ`，並將 `nextActivate` 推進 `total_cycles` 以精確約束背靠背時序。
>   - 在 `bwt_pim_test.nvt` 測試中：
>     - `precharges`: 8 -> 0 (冗餘預充電全數歸零)
>     - `transverse_reads`: 維持精確 8 次
>     - 模擬週期由 271 週期縮減至 267 週期 (省去無謂的 $tRP$ 預充電等待延遲)
>     - 兩大物理架構缺陷已全數修復完畢！