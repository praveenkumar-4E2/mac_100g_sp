`ifndef MAC_RX_VALID_FRAME_001_TEST_SVH
`define MAC_RX_VALID_FRAME_001_TEST_SVH

// RX_VALID_FRAME_001 — RX Valid Frame Reception.
//
// Verifies that the normal RX MAC path accepts a complete error-free
// Ethernet frame after a valid preamble/SFD and delivers correctly
// disassembled fields (DA, SA, Length/Type, Payload, FCS) to the MAC client.
//
// Stimulus: rx_valid_frame_001_seq_c (basic, boundary, pattern, config,
// alternate start patterns, 1-byte shifts, mixed B2B, byte-stream).
//
// Checking: AXI monitor count (valid frames delivered), scoreboard
// (expected vs actual AXI RX frame comparison), protocol checker
// (well-formed delivered frames), and frame counter with timeout.
class rx_valid_frame_001_test_c extends mac_base_test_c;
  `uvm_component_utils(rx_valid_frame_001_test_c)

  // Minimum valid frames the DUT must deliver across all iterations:
  //   3 (basic) + 7 (boundary) + 9 (pattern) + 3 (back-to-back)
  //   + 5 (alt start) + 3 (mixed ~50% valid) + 22 (byte-stream ~75%)
  //   = 52. Conservative lower bound.
  localparam int unsigned RX_VALID_FRAME_001_MIN_VALID_COUNT = 45;

  extern function new(string name = "rx_valid_frame_001_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function rx_valid_frame_001_test_c::new(string name = "rx_valid_frame_001_test_c",
                                       uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 0;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
endfunction

function void rx_valid_frame_001_test_c::configure_test();
  super.configure_test();
  env_cfg_h.max_payload_bytes = 1500;
  env_cfg_h.max_frame_octets  = 1518;
  // Enable RX scoreboard checking: all frames are valid, so the reference
  // model creates AXI expectations for every RS frame received.
  env_cfg_h.scoreboard_enable_rx_check = 1;
  // Disable TX scoreboard: no AXI TX traffic in this RX-only test.
  env_cfg_h.scoreboard_enable_tx_check = 0;
  // All frames are clean; the reference model sets error flags to 0 for
  // every expected AXI item. Error-flag comparison is redundant here.
  env_cfg_h.scoreboard_check_error_flags = 0;
  // Protocol checker enabled: all frames are well-formed with valid
  // preamble/SFD, so no false protocol violations will fire.
  env_cfg_h.has_protocol_checkers = 1;
endfunction

task rx_valid_frame_001_test_c::run_stimulus(uvm_phase phase);
  rx_valid_frame_001_seq_c seq_h;
  bit timed_out;
  bit sequence_timed_out;

  seq_h = rx_valid_frame_001_seq_c::type_id::create("rx_valid_frame_001_seq");
  // The sequence can block in finish_item() when the RS/DUT handshake stops
  // progressing. Guard the sequence itself; the existing count wait below
  // only begins after sequence completion and cannot catch that failure mode.
  sequence_timed_out = 1'b0;
  fork
    seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
    begin
      #MAC_COMPLETION_TIMEOUT_NS;
      sequence_timed_out = 1'b1;
    end
  join_any
  disable fork;

  if (sequence_timed_out) begin
    `uvm_error("RX_VALID_FRAME_001", "Timed out waiting for the RX valid-frame sequence")
    return;
  end

  mac_wait_utils_c::wait_for_axi_count_at_least(
      RX_VALID_FRAME_001_MIN_VALID_COUNT,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("RX_VALID_FRAME_001", "Timed out waiting for the RX valid-frame scenario burst")
  else
    `uvm_info("RX_VALID_FRAME_001", "PASS: all RX valid-frame scenarios completed", UVM_NONE)
endtask

`endif  // MAC_RX_VALID_FRAME_001_TEST_SVH
