`ifndef MAC_SANITY_TEST_SVH
`define MAC_SANITY_TEST_SVH

//------------------------------------------------------------------------------
// Class: mac_sanity_test_c
// Exercises the normal MAC data paths in three phases: TX-only, RX-only, and
// concurrent TX/RX traffic. All frames are independently randomized and valid.
//------------------------------------------------------------------------------
class mac_sanity_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_sanity_test_c)

  localparam int unsigned TX_TRANSACTION_COUNT = 10;
  localparam int unsigned RX_TRANSACTION_COUNT = 15;
  // This package is compiled at picosecond precision.  A 195.3125 MHz
  // clock therefore has a 5,120 ps period, which sustains 100 Gb/s across
  // the 512-bit MAC data path.
  // Use realtime so the 2.56 ns half-period is not rounded by $time to a
  // whole nanosecond before the measurement is made.
  localparam realtime MAC_CLK_PERIOD_NS = 5.120;
  localparam realtime MAC_CLK_TOLERANCE_NS = 0.001;

  extern function new(string name = "mac_sanity_test_c", uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
  extern virtual task verify_mac_clock_rate();
endclass

function mac_sanity_test_c::new(string name = "mac_sanity_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
  num_tx_frames          = TX_TRANSACTION_COUNT;
  num_rs_frames          = RX_TRANSACTION_COUNT;
endfunction

task mac_sanity_test_c::verify_mac_clock_rate();
  realtime previous_edge;
  realtime observed_period;

  @(posedge mac_tx_vif.clk);
  previous_edge = $realtime;
  repeat (4) begin
    @(posedge mac_tx_vif.clk);
    observed_period = $realtime - previous_edge;
    if ((observed_period < (MAC_CLK_PERIOD_NS - MAC_CLK_TOLERANCE_NS)) ||
        (observed_period > (MAC_CLK_PERIOD_NS + MAC_CLK_TOLERANCE_NS)))
      `uvm_fatal("MAC_SANITY", $sformatf(
                 "MAC clock period %0.3f ns is outside 100G tolerance around %0.3f ns",
                 observed_period,
                 MAC_CLK_PERIOD_NS
                 ))
    previous_edge = $realtime;
  end
  `uvm_info("MAC_SANITY",
            "Verified free-running 195.3125 MHz MAC clock (512 bits/cycle = 100 Gb/s)", UVM_NONE)
endtask

task mac_sanity_test_c::run_stimulus(uvm_phase phase);
  mac_sanity_tx_sequence_c tx_only_seq_h;
  mac_sanity_rx_sequence_c rx_only_seq_h;
  mac_sanity_tx_sequence_c tx_parallel_seq_h;
  mac_sanity_rx_sequence_c rx_parallel_seq_h;
  bit tx_only_timed_out;
  bit rx_only_timed_out;
  bit tx_parallel_timed_out;
  bit rx_parallel_timed_out;

  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null ||
      env_cfg_h.ral_h == null)
    `uvm_fatal("MAC_SANITY", "MAC environment, APB agent, RAL, or virtual sequencer was not built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("MAC_SANITY", "MAC reset and APB bootstrap did not complete")

  verify_mac_clock_rate();

  tx_only_seq_h = mac_sanity_tx_sequence_c::type_id::create("sanity_tx_only_seq_h");
  tx_only_seq_h.num_transactions = TX_TRANSACTION_COUNT;
  tx_only_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
  mac_wait_utils_c::wait_for_count_at_least(
      TX_TRANSACTION_COUNT,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt, mac_tx_vif,
      MAC_COMPLETION_TIMEOUT_NS, tx_only_timed_out);

  rx_only_seq_h = mac_sanity_rx_sequence_c::type_id::create("sanity_rx_only_seq_h");
  rx_only_seq_h.num_transactions = RX_TRANSACTION_COUNT;
  rx_only_seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  mac_wait_utils_c::wait_for_axi_count_at_least(
      RX_TRANSACTION_COUNT,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt, axi_rx_vif,
      MAC_COMPLETION_TIMEOUT_NS, rx_only_timed_out);

  tx_parallel_seq_h = mac_sanity_tx_sequence_c::type_id::create("sanity_tx_parallel_seq_h");
  rx_parallel_seq_h = mac_sanity_rx_sequence_c::type_id::create("sanity_rx_parallel_seq_h");
  tx_parallel_seq_h.num_transactions = TX_TRANSACTION_COUNT;
  rx_parallel_seq_h.num_transactions = RX_TRANSACTION_COUNT;
  fork
    tx_parallel_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
    rx_parallel_seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  join
  mac_wait_utils_c::wait_for_count_at_least(
      2 * TX_TRANSACTION_COUNT,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt, mac_tx_vif,
      MAC_COMPLETION_TIMEOUT_NS, tx_parallel_timed_out);
  mac_wait_utils_c::wait_for_axi_count_at_least(
      2 * RX_TRANSACTION_COUNT,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt, axi_rx_vif,
      MAC_COMPLETION_TIMEOUT_NS, rx_parallel_timed_out);

  if (tx_only_timed_out || rx_only_timed_out || tx_parallel_timed_out || rx_parallel_timed_out)
    `uvm_error("MAC_SANITY", $sformatf(
               "traffic completion failed: tx_only=%0b rx_only=%0b tx_parallel=%0b rx_parallel=%0b",
               tx_only_timed_out,
               rx_only_timed_out,
               tx_parallel_timed_out,
               rx_parallel_timed_out
               ))
  else
    `uvm_info("MAC_SANITY",
              "PASS: TX-only(10), RX-only(15), and concurrent TX(10)/RX(15) traffic completed",
              UVM_NONE)
endtask

`endif  // MAC_SANITY_TEST_SVH
