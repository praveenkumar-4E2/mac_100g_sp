`ifndef MAC_TX_PAD_001_TEST_SV
`define MAC_TX_PAD_001_TEST_SV

// TX_PAD_001 — Transmit Minimum-Frame Padding.
//
// Verifies automatic transmit padding, frame-length formation, and FCS
// generation for client data shorter than the Ethernet minimum payload
// requirement (46 bytes).  The DUT must zero-pad short payloads to 46 bytes
// and generate a correct FCS over the padded frame.
//
// Stimulus: axi_tx_pad_seq_c — six scenario iterations plus additional
// stimulus (boundary, pattern, config/negative, protocol error, random/stress).
//
// Checking: scoreboard (TX path expected-vs-actual via mac_ref_model) and
// RS wire monitor (preamble/SFD/FCS extraction).
class mac_tx_pad_001_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_tx_pad_001_test_c)

  // Total frames driven across all sequence iterations:
  //   1 (basic) + 6 (boundary) + 5 (pattern) + 3 (config/neg) +
  //   4 (protocol) + 100 (random/stress) + 5 (addl A) + 10 (addl B) +
  //   5 (addl C) + 50 (addl D) = 189
  localparam int unsigned TX_PAD_001_FRAME_COUNT = 189;

  extern function new(string name = "mac_tx_pad_001_test_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_tx_pad_001_test_c::new(string name = "mac_tx_pad_001_test_c",
                                    uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 0;
  num_rs_passive_agents  = 1;
endfunction

function void mac_tx_pad_001_test_c::configure_test();
  super.configure_test();
  env_cfg_h.max_payload_bytes = 1500;
  env_cfg_h.max_frame_octets  = MAC_STANDARD_FRAME_OCTETS;
  // Reference model uses 46-byte minimum to predict zero padding.
  env_cfg_h.min_payload_bytes = 46;
  // Disable protocol checkers — protocol-error iterations intentionally
  // drive early/late TLAST frames.
  env_cfg_h.has_protocol_checkers = 0;
  env_cfg_h.scoreboard_check_error_flags = 0;
endfunction

task mac_tx_pad_001_test_c::run_stimulus(uvm_phase phase);
  axi_tx_pad_seq_c seq_h;
  bit timed_out;

  seq_h = axi_tx_pad_seq_c::type_id::create("tx_pad_001_seq");
  seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);

  mac_wait_utils_c::wait_for_count_at_least(
      TX_PAD_001_FRAME_COUNT,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("TX_PAD_001",
               $sformatf("Timed out waiting for %0d TX pad frames (received %0d)",
                          TX_PAD_001_FRAME_COUNT,
                          env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))
  else
    `uvm_info("TX_PAD_001",
              $sformatf("PASS: all %0d TX minimum-frame padding scenarios completed",
                         TX_PAD_001_FRAME_COUNT), UVM_NONE)
endtask

`endif  // MAC_TX_PAD_001_TEST_SV
