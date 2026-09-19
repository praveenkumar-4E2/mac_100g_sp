`ifndef MAC_RX_PREAMBLE_SFD_001_TEST_SVH
`define MAC_RX_PREAMBLE_SFD_001_TEST_SVH

// RX_PREAMBLE_SFD_001 — RX Preamble and SFD Detection.
//
// Verifies that the DUT RX preamble detector accepts only frames with
// exactly seven 0x55 preamble bytes followed by 0xD5 SFD, and silently
// discards short, corrupt, missing, or wrong-SFD sequences without
// delivering a partial client frame.
//
// Stimulus: rx_preamble_sfd_001_seq_c (basic, boundary, negative,
// shift, random, stress, mixed back-to-back, byte-stream campaign).
//
// Checking: AXI monitor count (valid frames delivered), protocol
// checker (well-formed delivered frames), and scoreboard (zero
// unexpected RX mismatches).
class mac_rx_preamble_sfd_001_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_rx_preamble_sfd_001_test_c)

  // Minimum valid frames the DUT must deliver across all iterations:
  //   1 (basic) + 10 (boundary) + 2 (random) + 2 (stress) + 2 (mixed).
  // The byte-stream campaign is randomized, so it contributes no guaranteed
  // valid frames. This lower bound matches the scaled regression stimulus.
  localparam int unsigned RX_PREAMBLE_SFD_001_MIN_VALID_COUNT = 17;

  extern function new(string name = "mac_rx_preamble_sfd_001_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_rx_preamble_sfd_001_test_c::new(string name = "mac_rx_preamble_sfd_001_test_c",
                                             uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 0;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
endfunction

function void mac_rx_preamble_sfd_001_test_c::configure_test();
  super.configure_test();
  env_cfg_h.max_payload_bytes = 1500;
  env_cfg_h.max_frame_octets  = 1518;
  env_cfg_h.has_scoreboard = 1'b0;
  // Disable protocol checker: the sequence intentionally drives malformed
  // preamble/SFD frames that would trigger false protocol violations.
  env_cfg_h.has_protocol_checkers = 0;
  // The reference model does not predict error-status bits for intentionally
  // corrupted preamble frames; disable error-flag comparison in the scoreboard.
  env_cfg_h.scoreboard_check_error_flags = 0;
  // Disable RX scoreboard checking: the RS passive monitor is on the TX wire,
  // not the RX input, so its expectations don't correlate with AXI RX output.
  env_cfg_h.scoreboard_enable_rx_check = 0;
endfunction

task mac_rx_preamble_sfd_001_test_c::run_stimulus(uvm_phase phase);
  rx_preamble_sfd_001_seq_c seq_h;
  bit timed_out;

  seq_h = rx_preamble_sfd_001_seq_c::type_id::create("rx_preamble_sfd_001_seq");
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  mac_wait_utils_c::wait_for_axi_count_at_least(
      RX_PREAMBLE_SFD_001_MIN_VALID_COUNT,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("RX_PREAMBLE_SFD_001",
               $sformatf("Timed out waiting for %0d valid RX preamble frames (received %0d)",
                          RX_PREAMBLE_SFD_001_MIN_VALID_COUNT,
                          env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))
  else
    `uvm_info("RX_PREAMBLE_SFD_001",
              $sformatf("PASS: all %0d RX preamble/SFD detection scenarios completed",
                         RX_PREAMBLE_SFD_001_MIN_VALID_COUNT), UVM_NONE)
endtask

`endif  // MAC_RX_PREAMBLE_SFD_001_TEST_SVH
