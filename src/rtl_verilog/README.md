# Staged pure-Verilog implementation

This directory contains migrated Verilog-2005 RTL while `src/hdl_top` remains
the SystemVerilog reference design. Converted modules retain their original
module names and are not added to `mac_compile.f` until the complete dependent
cone has been migrated; compiling both versions together would create duplicate
module definitions and invalidate differential testing.

Current syntax check:

```text
iverilog -g2005 -tnull src/rtl_verilog/cdc/*.v \
  src/rtl_verilog/integration/mac_event_collector.v \
  src/rtl_verilog/tx/tx_scheduler.v
```
