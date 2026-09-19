// Canonical UVM build for Cadence Xcelium (xrun): pure-Verilog RTL
// connected to the existing HVL.  Paths are relative to sim/cadence/
// (../../src resolves to the repository root), matching Questa's list.
+incdir+/home/install/XCELIUM2209/tools.lnx86/methodology/UVM/CDNS-1.2/sv/src
+incdir+../../src/rtl_verilog
+incdir+../../src/hdl_top
+incdir+../../src/hvl_top/interfaces
+incdir+../../src/hvl_top/tb
+incdir+../../src/hvl_top/test
+incdir+../../src/hvl_top/test/base
+incdir+../../src/hvl_top/test/mac
+incdir+../../src/hvl_top/test/mac/integration
+incdir+../../src/hvl_top/test/mac/pause_frame
+incdir+../../src/hvl_top/test/mac/apb
+incdir+../../src/hvl_top/test/mac/jumbo
+incdir+../../src/hvl_top/test/mac/preamble_sfd
+incdir+../../src/hvl_top/test/mac/rx_valid_frame
+incdir+../../src/hvl_top/test/mac/ethertype
+incdir+../../src/hvl_top/test/mac/control
+incdir+../../src/hvl_top/test/mac/counters
+incdir+../../src/hvl_top/test/mac/tx_pad
+incdir+../../src/hvl_top/test/mac/statistics
+incdir+../../src/hvl_top/sequences/axi
+incdir+../../src/hvl_top/sequences/rs
+incdir+../../src/hvl_top/sequences/smoke
+incdir+../../src/hvl_top/sequences/virtual
+incdir+../../src/hvl_top/coverage
+incdir+../../src/hvl_top/pkg
+incdir+../../src/hvl_top/common
+incdir+../../src/hvl_top/mac_agents/rs_agt_top
+incdir+../../src/hvl_top/mac_agents/axi_agt_top
+incdir+../../src/hvl_top/mac_agents/apb_agt_top
+incdir+../../src/hvl_top/mac_agents/mac_reset_agt

// Legacy packages and interfaces are testbench support only.
../../src/hvl_top/pkg/mac_reg_map_pkg.sv
../../src/hvl_top/interfaces/apb_if.sv
../../src/hvl_top/interfaces/mac_reset_if.sv
../../src/hvl_top/interfaces/mac_rs_stream_if.sv
../../src/hvl_top/interfaces/axi4_stream_if.sv

// Converted synthesizable Verilog RTL.
../../src/rtl_verilog/cdc/cdc_2ff.v
../../src/rtl_verilog/cdc/cdc_dpram.v
../../src/rtl_verilog/cdc/cdc_handshake.v
../../src/rtl_verilog/cdc/cdc_pulse.v
../../src/rtl_verilog/common/crc32_engine.v
../../src/rtl_verilog/control/control_classifier.v
../../src/rtl_verilog/control/control_frame_builder.v
../../src/rtl_verilog/control/mac_control_top.v
../../src/rtl_verilog/pause/pause_admission_gate.v
../../src/rtl_verilog/pause/pause_rx.v
../../src/rtl_verilog/pause/pause_timer_engine.v
../../src/rtl_verilog/pause/pause_tx.v
../../src/rtl_verilog/primitives/address_filter.v
../../src/rtl_verilog/primitives/bit_time_counter.v
../../src/rtl_verilog/registers/apb_cfg_bridge.v
../../src/rtl_verilog/registers/apb_decode.v
../../src/rtl_verilog/registers/apb_interrupt.v
../../src/rtl_verilog/registers/apb_regs_if.v
../../src/rtl_verilog/registers/reg_file.v
../../src/rtl_verilog/registers/stats_cdc_bridge.v
../../src/rtl_verilog/registers/apb_regs.v
../../src/rtl_verilog/rx/rx_axi4_stream_adapter.v
../../src/rtl_verilog/rx/rx_crc_check.v
../../src/rtl_verilog/rx/rx_frame_emit.v
../../src/rtl_verilog/rx/rx_header_extract.v
../../src/rtl_verilog/rx/rx_length_check.v
../../src/rtl_verilog/rx/rx_preamble_detect.v
../../src/rtl_verilog/rx/rx_pipeline.v
../../src/rtl_verilog/rx/mac_rx_top.v
../../src/rtl_verilog/statistics/stats_counters.v
../../src/rtl_verilog/statistics/stats_aggregator.v
../../src/rtl_verilog/statistics/mac_stats.v
../../src/rtl_verilog/tx/crc32_tx.v
../../src/rtl_verilog/tx/frame_formatter.v
../../src/rtl_verilog/tx/tx_arbiter.v
../../src/rtl_verilog/tx/tx_axi_admission.v
../../src/rtl_verilog/tx/tx_axi4_stream_adapter.v
../../src/rtl_verilog/tx/tx_client_capture.v
../../src/rtl_verilog/tx/tx_crc_insert.v
../../src/rtl_verilog/tx/tx_frame_builder.v
../../src/rtl_verilog/tx/tx_ipg_timer.v
../../src/rtl_verilog/tx/tx_pad_calc.v
../../src/rtl_verilog/tx/tx_pipeline.v
../../src/rtl_verilog/tx/tx_scheduler.v
../../src/rtl_verilog/tx/mac_tx_top.v
../../src/rtl_verilog/integration/mac_event_collector.v
../../src/rtl_verilog/integration/mac_rx_path.v
../../src/rtl_verilog/integration/mac_tx_path.v
../../src/rtl_verilog/integration/mac_core_v.v
../../src/rtl_verilog/rtl_top.v

// Existing UVM testbench.
../../src/hvl_top/pkg/mac_test_pkg.sv
../../src/hvl_top/tb/mac_tb_top.sv