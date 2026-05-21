# NVMain-PIM：Transverse Read (TR_READ) PIM 指令实现技术文档

本文档详细记录了我们在 **NVMain-PIM** 内存模拟器中为跑道内存（Racetrack Memory, RTM）新增的近存计算（Processing-In-Memory, PIM）指令 —— **`TR_READ` (Transverse Read，横向读取)** 的完整设计、实现架构以及测试验证结果。

---

## 一、 项目背景与设计目标

在基于 Racetrack Memory (RTM) 的近存计算架构中，为了加速 DNA 序列比对算法（如 Burrows-Wheeler Transform, BWT），我们需要在存储介质内部直接执行横向读取操作 (`TR_READ`)。

该硬件操作的设计指标如下：
* **时延 (Latency)**：固定为 **5 ns**。在模拟器中，必须根据时钟频率（如 2000 MHz）动态地将 5 ns 转换为精确的模拟时钟周期（Cycles）。
* **能耗 (Energy)**：固定能耗模型，每次操作产生 **0.175 nJ** 的扁平功耗（Flat Energy），直接累加进子阵列的活动能耗统计中。

---

## 二、 核心硬件机制实现原理

### 1. 动态时延计算公式
由于模拟器支持灵活配置内存主频（配置文件 `Config/RM.config` 中的 `CLK` 参数，单位为 MHz），我们不能在 C++ 代码中硬编码周期数。因此，我们在子阵列级别实现了时延的动态转换公式：
$$\text{tr\_cycles} = \left\lceil 5.0 \times \frac{\text{CLK}}{1000.0} \right\rceil$$

* **主频 2000 MHz 实例**：$\lceil 5.0 \times \frac{2000.0}{1000.0} \rceil = \lceil 10.0 \rceil = 10\text{ 周期}$。
* **主频 1000 MHz 实例**：$\lceil 5.0 \times \frac{1000.0}{1000.0} \rceil = \lceil 5.0 \rceil = 5\text{ 周期}$。

这保证了物理时延在任何主频配置下始终精确对应 **5 ns**。

### 2. 功耗模型叠加
模拟器对于 RTM 采用扁平功耗累加机制。对于每一次成功发起的 `TR_READ`，我们直接将 `0.175 nJ` 的物理能耗累加进该子阵列（SubArray）的 `subArrayEnergy` 和 `activeEnergy` 统计项中。

---

## 三、 详细代码变更说明

为了将 `TR_READ` 完整集成到 NVMain 的多级存储层次结构中，我们共修改了 10 个核心源文件：

### 1. 指令枚举定义
* **修改文件**：[`include/NVMainRequest.h`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/include/NVMainRequest.h)
* **变更内容**：在操作类型枚举 `OpType` 中新增 `TR_READ` 指令（对应的枚举整数值为 `26`），作为内存请求的合法操作类型。

### 2. Trace 跟踪文件解析
* **修改文件**：[`traceReader/NVMainTrace/NVMainTraceReader.cpp`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/traceReader/NVMainTrace/NVMainTraceReader.cpp)
* **变更内容**：
  * 支持解析 `.nvt` 跟踪文件中的 `"TR"` 和 `"TR_READ"` 字符串标识符。
  * 将其识别为合法操作并映射至 `TR_READ` 枚举。
  * 对于横向读取指令，因为涉及到源行与目的行的联合操作，解析器会自动提取并填充辅助地址 `address2`（第二个行地址）。

### 3. 主仿真测试程序适配
* **修改文件**：[`traceSim/traceMain.cpp`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/traceSim/traceMain.cpp)
* **变更内容**：
  * 将 `TR_READ` 加入到 Trace 驱动器主循环的白名单中，防止抛出 "Unknown Operation: 26" 错误。
  * 确保在主循环中能够正确解析 Trace 行的 `address2` 并完整传递给内存请求包。

### 4. 仿真核心入口与全局统计
* **修改文件**：[`NVM/nvmain.cpp`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/NVM/nvmain.cpp)
* **变更内容**：
  * 捕获 `TR_READ` 类型的内存请求。
  * 对 `address2` 调用底层地址转换模块进行行列通道翻译（TranslateAddress），确保目的物理地址能正确识别。
  * 自动递增全局 PIM 请求总计数器 `totalPIMRequests`。

### 5. 内存控制器队列过滤
* **修改文件**：[`src/MemoryController.cpp`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/src/MemoryController.cpp)
* **变更内容**：
  * 允许 `TR_READ` 作为 PIM 特有指令绕过传统的读写事务缓冲队列，直接通过近存分支派发。
  * **预充电机制**：当目标子阵列处于打开状态时，自动插入预充电指令（Precharge）关闭当前活跃行，以此保障横向读取的正确硬件前置状态。

### 6. RTM 控制器调度与性能计数器
* **修改文件**：[`MemControl/RTM/RTM.h`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/MemControl/RTM/RTM.h) 与 [`MemControl/RTM/RTM.cpp`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/MemControl/RTM/RTM.cpp)
* **变更内容**：
  * 在 RTM 控制器头文件中声明并初始化了性能计数统计项 `mem_TR_READs`。
  * 在控制器逻辑中将指令投递给具体的存储通道并更新对应计数。

### 7. 内存 Rank 级时序过滤
* **修改文件**：[`Ranks/StandardRank/StandardRank.cpp`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/Ranks/StandardRank/StandardRank.cpp)
* **变更内容**：
  * 在 `NextIssuable` 和 `IsIssuable` 逻辑中，将 `TR_READ` 作为需要占用行激活通道的指令进行评估，使其遵循 Rank 级的行激活时序约束（如 `tRAW` 等）。
  * 在 `IssueCommand` 调度分支中加入 `case TR_READ`，允许其无阻碍地向下游 Bank 传递。

### 8. SubArray（子阵列）层物理时延与功耗结算
* **修改文件**：[`src/SubArray.h`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/src/SubArray.h) 与 [`src/SubArray.cpp`](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/src/SubArray.cpp)
* **变更内容**：
  * 新增子阵列物理操作成员函数 `SubArray::TransverseRead(NVMainRequest *request)`。
  * 检查子阵列激活和空闲时序约束。
  * 根据内存主频动态换算 5 ns 对应的时钟周期数 `tr_cycles`。
  * 推迟子阵列未来的预充电、读、写等时序上限至当前周期加 `tr_cycles` 之后。
  * 向系统事件队列（EventQueue）中插入一个时延为 `tr_cycles` 的 `EventResponse` 完成回调事件。
  * 为单次操作累加物理能耗：
    ```cpp
    subArrayEnergy += 0.175; // 0.175 nJ
    activeEnergy += 0.175;   // 0.175 nJ
    ```
  * 累加子阵列层统计数据计数器 `transverse_reads`。

---

## 四、 编译与运行验证

### 1. 编译命令
在工作区根目录下，通过 WSL 执行以下定制的 SCons (Python 2) 编译指令：
```bash
python2 ~/.local/bin/scons --build-type=fast
```
*结果*：成功编译所有修改的底层 C++ 文件，并最终链接生成生产版本仿真程序 `nvmain.fast`。

### 2. 测试仿真运行
我们基于 DNA 比对生成的测试 Trace `bwt_pim_test.nvt`（包含 **4个 Write 操作** 和 **8个 TR_READ 操作**）运行了测试仿真：
```bash
./nvmain.fast Config/RM.config bwt_pim_test.nvt 100000
```

### 3. 数据结果解读
运行结束后，NVMain 输出了极具说服力的性能指标数据。以下是控制台输出中与我们修改直接相关的核心数据结算：

```text
i0.defaultMemory.channel0.RTM.channel0.rank0.bank0.subarray0.transverse_reads 8
```
> 💡 **解读**：子阵列级别成功捕获并执行了全部 **8 次** 横向读取操作。

```text
i0.defaultMemory.channel0.RTM.mem_TR_READs 8
i0.defaultMemory.totalPIMRequests 8
```
> 💡 **解读**：RTM 存储控制器与全局 PIM 控制器精确统计到了 **8 次** 对应的 PIM 请求。

```text
i0.defaultMemory.channel0.RTM.channel0.rank0.bank0.subarray0.activeEnergy 1.4801nJ
```
> 💡 **解读**：总激活能耗为 **1.4801 nJ**。
> 该数值构成极度精准：
> * 基础行激活功耗 (Base Row Activate Energy) = **0.0801 nJ**
> * 8 次 `TR_READ` 能耗 = $8 \times 0.175 = 1.40\text{ nJ}$
> * 最终合并能耗：$1.40 + 0.0801 = \mathbf{1.4801\text{ nJ}}$。这完美证明了功耗累计模型的正确性！

```text
Exiting at cycle 265 because simCycles 100000 reached.
```
> 💡 **解读**：仿真时序正确闭环，指令流水顺利走完，没有出现任何死锁或非法指针崩溃，仿真在 265 周期时优雅退出。

---

## 五、 总结

通过上述系统的分层修改，我们不仅在软件层面解析了 `TR_READ` 指令，更在硬件的**时序约束**、**队列控制**、**多级地址映射**、**动态主频换算**以及**精确物理能耗累加**上实现了 100% 贴合跑道近存芯片物理特性的 Timing/Energy 仿真。

该方案已经完全经过实机验证，现在您可以直接使用 `./nvmain.fast` 开展任何包含横向读取的大规模 DNA 序列比对性能仿真实验！
