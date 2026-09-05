# Hardware Architecture Theory: RTM-Based Acceleration for Genome Sequencing

## 1. Transverse Read (TR_READ) Mechanism
- TR_READ is not a standard memory fetch. It relies on Kirchhoff's Circuit Laws to perform analog computation directly on the Bitlines.
- It requires simultaneously activating ONLY the specific rows participating in the computation (e.g., Row A for Target Sequence, Row B for Reference Sequence). 
- It MUST NOT activate all rows in a SubArray. Doing so would violate the `tRAW` (Row Activate Window) power delivery limits and physically destroy the chip due to current spikes.
- Address tracking (using both `address1` and `address2`) is absolutely necessary to identify which two rows are being superimposed.

## 2. Dynamic Domain Wall Shift Mechanism
- RTM requires moving data (Domain Walls) along a nanowire to a fixed access port before reading.
- The shift cost is dynamic, not flat.
- Shift Distance (D) = |Target_Domain_Position - Current_Port_Position|
- Dynamic Latency = D * tSH
- Dynamic Energy = D * ESH
- Total Operation Time = Dynamic Shift Latency + 5ns (TR_READ fixed latency).

## 3. Precharge bypass (Non-volatile characteristic)
- RTM is non-volatile. TR_READ is a non-destructive operation.
- Consecutive TR_READ commands should NOT trigger conventional DRAM `PRECHARGE` (tRP) delays.