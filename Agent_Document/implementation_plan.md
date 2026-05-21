# Implementation Plan: Transverse Read (TR_READ) PIM Command

This plan defines the step-by-step instructions and C++ snippets to implement a new Processing-In-Memory (PIM) command called `TR_READ` (Transverse Read) in the NVMain-PIM memory simulator. The target hardware parameters for this command are **5 ns latency** and **0.175 nJ energy**.

We have completed the research phase by tracing how the triple row activate (`TRA`) command is parsed and handled throughout the simulator, from trace reading to timing/energy calculations in the sub-arrays.

---

## Technical Overview of TRA Logic
In NVMain-PIM, the `TRA` (Triple Row Activate) command acts as follows:
1. **Definition**: Defined in `include/NVMainRequest.h` in the `OpType` enum.
2. **Parsing**: Parsed from trace files by `traceReader/NVMainTrace/NVMainTraceReader.cpp`. If a line contains the string `"TRA"` or `"T"`, it is converted to a request of `OpType` `TRA`.
3. **Memory Controller Flow**: The request is enqueued by `RTM::IssueCommand` or `FRFCFS::IssueCommand` into the memory controller transaction queue.
4. **Command Generation**: In `MemoryController::IssuePIMCommands`, the request is bypass-routed to the sub-array command queues. If the destination sub-array is open, a precharge command is inserted before `TRA` to close it first.
5. **Sub-Array Execution**: In `SubArray::IsIssuable`, the request is checked against the sub-array's activation timing constraints (`nextActivate`). In `SubArray::IssueCommand`, the request is routed to `SubArray::MultiRowActivate`.
6. **Timing Calculation**: `SubArray::MultiRowActivate` updates the sub-array's timing constraints (`nextPrecharge`, `nextRead`, `nextWrite`, `nextPowerDown`) and queues a completion callback at `GetCurrentCycle() + p->tRCD + p->tSH * (numShifts / wordSize)`.
7. **Energy Calculation**: It applies a scale of `1.44` to the mat read energy (`p->Erd`) and adds it to `subArrayEnergy` and `activeEnergy`.

---

## User Review Required

> [!IMPORTANT]
> - **Latency Calculation**: Since the simulator uses a configurable memory clock frequency (`p->CLK` in MHz), hardcoding a cycle count for 5 ns would break if the clock speed changes. We dynamically convert 5 ns to cycle counts at runtime using:
>   $$\text{cycles} = \lceil 5.0 \times \frac{\text{CLK}}{1000.0} \rceil$$
>   This guarantees that at 2000 MHz (like in `RM.config`), the latency is exactly 10 cycles (5.0 ns), and scales correctly for other frequencies.
> - **Energy Calculation**: Since `RM.config` uses the flat `energy` model (`EnergyModel energy`), we directly add the flat parameter value of `0.175` nJ to the sub-array's energy accumulators.
> - **Do NOT Modify Files Directly**: As requested, **no files will be modified directly**. I am presenting these code changes here for your review and approval. Once you approve, you can authorize me to apply them.

---

## Proposed Changes

We will introduce `TR_READ` by mirroring the PIM-routing architecture of `TRA` but calling a dedicated `TransverseRead` method in `SubArray`.

### 1. Request Definitions

#### [MODIFY] [include/NVMainRequest.h](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/include/NVMainRequest.h)
Add `TR_READ` to the `OpType` enum.

```diff
     OTRA, /*Overlapped Triple Row Activate primitive for PIM in DRAM*/
     LW, /*Local Write primitive for PIM in DRAM*/
-    ROWCLONE_PSM /*Row Clone PSM primitive for PIM in DRAM (not implemented yet) */
+    ROWCLONE_PSM, /*Row Clone PSM primitive for PIM in DRAM (not implemented yet) */
+    TR_READ /* Transverse Read PIM operation (DNA Sequence Alignment) */
 };
```

---

### 2. Trace Parsing

#### [MODIFY] [traceReader/NVMainTrace/NVMainTraceReader.cpp](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/traceReader/NVMainTrace/NVMainTraceReader.cpp)
Parse `TR_READ` from `.nvt` traces, ensure it checks against the same list of valid operations, and set the second address mapping.

```diff
                 else if(field == "T" || field == "TRA" )
                     operation = TRA;
+                else if(field == "TR" || field == "TR_READ")
+                    operation = TR_READ;
                 else if (field == "ODRA" )
                     operation = ODRA;
```

```diff
     if( operation != READ && operation != WRITE && 
         operation != TRA && operation != DRA && operation != SRA &&
-        operation != OTRA && operation != ODRA && operation != OA )
+        operation != OTRA && operation != ODRA && operation != OA && operation != TR_READ )
         std::cout << "NVMainTraceReader: Unknown Operation: " << operation 
```

```diff
-    if( operation == OA || operation == TRA ){
+    if( operation == OA || operation == TRA || operation == TR_READ ){
         NVMAddress nAddress2;
```

---

### 3. NVMain Core Entry Point

#### [MODIFY] [NVM/nvmain.cpp](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/NVM/nvmain.cpp)
Map `TR_READ` requests to translate the second address (source/destination) and increment PIM statistics.

```diff
         else if(request->type == TRA || request->type == OA || request->type == DRA || request->type == SRA 
-                || request->type == ODRA || request->type == OTRA)
+                || request->type == ODRA || request->type == OTRA || request->type == TR_READ)
         {
             /* Translate address 2 for pim commands */
```

```diff
         else if(request->type == TRA || request->type == OA || request->type == DRA || request->type == SRA 
-                || request->type == ODRA || request->type == OTRA)
+                || request->type == ODRA || request->type == OTRA || request->type == TR_READ)
         {
             totalPIMRequests++;
```

---

### 4. Memory Controller Routing

#### [MODIFY] [src/MemoryController.cpp](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/src/MemoryController.cpp)
Recognize `TR_READ` as a PIM command so that it is processed via `IssuePIMCommands` and not filtered out.

```diff
         // Skip transaction requests that are not READ or WRITE (PIM requests)
         if((*it)->type == TRA || (*it)->type == OA || (*it)->type == DRA || (*it)->type == SRA
-            || (*it)->type == ODRA || (*it)->type == OTRA)
+            || (*it)->type == ODRA || (*it)->type == OTRA || (*it)->type == TR_READ)
             continue;
```

```diff
         // Skip transaction requests that are not READ or WRITE (PIM requests)
         if((*it)->type == TRA || (*it)->type == OA || (*it)->type == DRA || (*it)->type == SRA
-            || (*it)->type == ODRA || (*it)->type == OTRA)
+            || (*it)->type == ODRA || (*it)->type == OTRA || (*it)->type == TR_READ)
             continue;
```

```diff
     //If not overlap, the subarray should not be active
-    if(activeSubArray[rank][bank][subarray] && (req->type == SRA || req->type == DRA ||  req->type == TRA)){
+    if(activeSubArray[rank][bank][subarray] && (req->type == SRA || req->type == DRA ||  req->type == TRA || req->type == TR_READ)){
         commandQueues[queueId].push_back( MakePrechargeRequest( req ) );
     }
```

---

### 5. RTM Memory Controller Scheduling

#### [MODIFY] [MemControl/RTM/RTM.h](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/MemControl/RTM/RTM.h)
Add stats trackers and fields for `TR_READ`.

```diff
     uint64_t mem_reads, mem_writes, mem_TRAs, mem_oAs, mem_DRAs;
+    uint64_t mem_TR_READs;
```

#### [MODIFY] [MemControl/RTM/RTM.cpp](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/MemControl/RTM/RTM.cpp)
Track and queue `TR_READ` commands in the RTM controller.

```diff
     mem_TRAs = 0; 
+    mem_TR_READs = 0;
     mem_DRAs = 0;
```

```diff
     AddStat(mem_TRAs);
+    AddStat(mem_TR_READs);
     AddStat(mem_DRAs);
```

```diff
     }else if(req->type == DRA){
         mem_DRAs++;
         Enqueue(0, req);
+    }else if(req->type == TR_READ){
+        mem_TR_READs++;
+        Enqueue(0, req);
     }
```

```diff
         if (nextRequest->type == TRA || nextRequest->type == OA || nextRequest->type == DRA ||
-            nextRequest->type == SRA || nextRequest->type == ODRA || nextRequest->type == OTRA)
+            nextRequest->type == SRA || nextRequest->type == ODRA || nextRequest->type == OTRA || nextRequest->type == TR_READ)
             IssuePIMCommands( nextRequest );
```

---

### 6. Sub-Array Handling and Timing/Energy Calculations

#### [MODIFY] [src/SubArray.h](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/src/SubArray.h)
Declare the `TransverseRead` handler and statistical counter in `SubArray`.

```diff
     bool OverlappedActivate( NVMainRequest *request );
     bool MultiRowActivate( NVMainRequest *request );
+    bool TransverseRead( NVMainRequest *request );
     bool Precharge( NVMainRequest *request );
```

```diff
     ncounter_t reads, writes, activates, precharges, refreshes, 
       overlapped_activates, overlapped_double_row_activates,
       overlapped_triple_row_activates, single_row_activates,
-      double_row_activates, triple_row_activates, local_writes;
+      double_row_activates, triple_row_activates, local_writes,
+      transverse_reads;
     ncounter_t idleTimer;
```

#### [MODIFY] [src/SubArray.cpp](file:///\\wsl.localhost/Ubuntu-22.04/home/maplesour/NVMain-PIM/src/SubArray.cpp)
Implement constructor initialization, stat registration, timing check, command routing, and calculations.

```diff
     triple_row_activates = 0;
     local_writes = 0;
+    transverse_reads = 0;
 
     actWaits = 0;
```

```diff
     AddStat(triple_row_activates);
     AddStat(local_writes);
+    AddStat(transverse_reads);
 
     /* Register these stats only for RaceTrack Memory */
```

```diff
     if( req->type == ACTIVATE || req->type == TRA || req->type == DRA || req->type == SRA )
+    if( req->type == ACTIVATE || req->type == TRA || req->type == DRA || req->type == SRA || req->type == TR_READ )
     {
```

```diff
             case TRA:
                 rv = this->MultiRowActivate( req );
                 break;
+            case TR_READ:
+                rv = this->TransverseRead( req );
+                break;
             case READ:
```

Add the `TransverseRead` method at the end of `src/SubArray.cpp`:

```cpp
bool SubArray::TransverseRead( NVMainRequest *request )
{
    uint64_t activateRow;
    request->address.GetTranslatedAddress( &activateRow, NULL, NULL, NULL, NULL, NULL );

    /* Check if we need to cancel or pause a write to service this request. */
    CheckWritePausing( );

    if( nextActivate > GetEventQueue()->GetCurrentCycle() )
    {
        std::cerr << "NVMain Error: SubArray violates ACTIVATION timing constraint!" << std::endl;
        return false;
    }
    else if( p->UsePrecharge && state != SUBARRAY_CLOSED )
    {
        std::cerr << "NVMain Error: try to open a subarray that is not idle!" << std::endl;
        return false;
    }

    // 1. LATENCY CALCULATION: 5 ns converted dynamically to cycles
    ncycle_t tr_cycles = static_cast<ncycle_t>(std::ceil(5.0 * (static_cast<double>(p->CLK) / 1000.0)));

    // 2. TIMING CONSTRAINTS UPDATING
    nextPrecharge = MAX( nextPrecharge, GetEventQueue()->GetCurrentCycle() + tr_cycles );
    nextRead = MAX( nextRead, GetEventQueue()->GetCurrentCycle() + tr_cycles );
    nextWrite = MAX( nextWrite, GetEventQueue()->GetCurrentCycle() + tr_cycles );
    nextPowerDown = MAX( nextPowerDown, GetEventQueue()->GetCurrentCycle() + tr_cycles );

    // 3. SEND EVENT RESPONSE CALLBACK
    GetEventQueue()->InsertEvent( EventResponse, this, request, GetEventQueue()->GetCurrentCycle() + tr_cycles );

    // 4. SUBARRAY INTERNAL STATE UPDATE
    openRow = activateRow;
    state = SUBARRAY_OPEN;
    writeCycle = false;
    lastActivate = GetEventQueue()->GetCurrentCycle();

    transverse_reads++;

    // 5. ENERGY CALCULATION: 0.175 nJ flat energy added
    subArrayEnergy += 0.175;
    activeEnergy += 0.175;

    return true;
}
```

---

## Verification Plan

### Automated Verification
After applying the code modifications, we will verify the changes by running:
1. **Compilation Check**: Build the fast simulator using:
   `python2 ~/.local/bin/scons --build-type=fast`
2. **Execution Check**: Run a trace-driven simulation using a test `.nvt` trace containing `TR_READ` commands:
   `./nvmain.fast Config/RM.config <test_trace>.nvt`
3. **Output Inspection**: Verify that the simulation reports `mem_TR_READs` and `transverse_reads` in the final stats block and that the timing cycles and energy reflect the 5ns latency (10 cycles @ 2GHz) and 0.175nJ per operation.
