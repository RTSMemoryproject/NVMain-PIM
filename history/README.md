# NVMain-PIM 程式碼改動歷史記錄 (Code Change History)

本目錄記錄了 `NVMain-PIM` 專案在支援跑道記憶體近存計算（RTM-PIM `TR_READ`）過程中所進行的各階段重大程式碼改動、問題成因分析、具體改動代碼對比及模擬驗證成效。

---

## 歷次改動版本導引

| 序號 | 檔案名稱 | 核心主題 | 解決之核心問題 | 驗證指標狀態 |
| :--- | :--- | :--- | :--- | :---: |
| **01** | [`01_tr_read_pipeline_implementation.md`](./01_tr_read_pipeline_implementation.md) | TR_READ 基礎指令管道貫通 | 原始代碼庫完全缺乏 `TR_READ` 相關指令定義、Trace 解析、PIM 控制器排程與 SubArray 執行入口 | **PASS** |
| **02** | [`02_domain_wall_shift_mechanism.md`](./02_domain_wall_shift_mechanism.md) | 動態磁疇移位機制修復 | 修復「零移位」物理悖論，在 `TransverseRead` 實作奈米線磁疇對齊之動態移位時延與能耗 | **PASS** |
| **03** | [`03_precharge_bypass_optimization.md`](./03_precharge_bypass_optimization.md) | 連續 TR_READ 預充電延遲繞過 | 解決非揮發性 RTM 中被強制插入 DRAM 式預充電 ($tRP$) 的問題，實現背靠背連續橫向讀取 | **PASS** |
| **04** | [`04_code_audit_and_dual_row_kirchhoff.md`](./04_code_audit_and_dual_row_kirchhoff.md) | 代碼審計 8 大缺陷全面修復 | 補全雙行克希荷夫電流疊加 (`address2`)、消除死鎖計時器崩潰漏洞、修復急切時延與記憶體安全防護 | **PASS** |

---

## 總體演進成效對比 (`bwt_pim_test.nvt`)

| 指標名稱 (Metric) | 原始基準 (Baseline) | 階段二 (動態移位) | 階段三 (繞過預充電) | 階段四 (審計加固) | 理論架構期望 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **預充電次數 (`precharges`)** | 8 | 8 | **0** | **0** | 100% 消除冗餘預充電 |
| **橫向讀取次數 (`transverse_reads`)** | 8 | 8 | **8** | **8** | 精確執行 8 次 PIM 讀取 |
| **磁疇移位請求 (`shiftReqs`)** | 3 | 11 | 11 | **11** | 3 次寫入 + 8 次 PIM 動態移位 |
| **總磁疇移位數 (`totalnumShifts`)** | 96 | 480 | 480 | **480** | 動態移位步數完全吻合 |
| **移位能耗 (`shiftEnergy`)** | 0.0585 nJ | 0.2925 nJ | 0.2925 nJ | **0.2925 nJ** | 正確累加動態移位能耗 |
| **子陣列總能耗 (`subArrayEnergy`)** | 43.5917 nJ | 43.8257 nJ | 43.8257 nJ | **43.8257 nJ** | 涵蓋移位與類比計算全部能耗 |
| **模擬退出週期** | 265 | 271 | **267** | **267** | 消除 $tRP$ 延遲，執行更緊湊 |
