`ifndef MAC_TEST_MANIFEST_SVH
`define MAC_TEST_MANIFEST_SVH

// Central test registration point. Add a feature aggregator here when its
// first executable testcase is implemented. Test IDs and ownership are kept
// in src/hvl_top/testplan/mac_testplan.csv.
`include "mac_integration_tests.svh"
`include "integration/mac_top_concurrent_integration_tests.svh"
`include "mac_pause_frame_tests.svh"
`include "integration/mac_full_duplex_control_transparency_tests.svh"
`include "mac_apb_tests.svh"
`include "cdc/mac_comprehensive_scenario_tests.svh"
`include "mac_jumbo_tests.svh"

`include "crc/TX_CRC_001.sv"
`include "crc/RX_CRC_002.sv"

`include "preamble_sfd/mac_preamble_sfd_tests.svh"
`include "rx_valid_frame/mac_rx_valid_frame_tests.svh"
`include "tx_adapter/mac_rx_pipe_tests.svh"
`include "ethertype/mac_ethertype_all_tests.svh"
`include "control/mac_control_tests.svh"
`include "address_filtering/mac_addr_filtering_tests.svh"
`include "ipg/mac_ipg_tests.svh"

`include "counters/mac_counters_tests.svh"

`include "tx_pad/TX_PAD_001.sv"

`include "tx_adapter/mac_tx_adapter_tests.svh"
`include "statistics/mac_stats_tests.svh"


`endif
