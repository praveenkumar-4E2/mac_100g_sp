`ifndef MAC_PREAMBLE_GEN_001_TEST_SVH
`define MAC_PREAMBLE_GEN_001_TEST_SVH

// TX_PREAMBLE_GEN_001 — TX Preamble Generation.
//
// Verifies that every transmitted frame has exactly seven 0x55 preamble
// bytes followed by 0xD5 SFD before the payload, with no missing,
// duplicate, or early payload byte.
//
// Stimulus: ps002_tx_preamble_sfd_seq_c (basic, boundary/pattern,
// timing/sequence, random/stress, byte-stream campaign).
//
// Checking: protocol checker (preamble/SFD assertion), scoreboard
// (TX path expected-vs-actual), and RS wire monitor (preamble byte
// extraction).
class mac_preamble_gen_001_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_preamble_gen_001_test_c)

  // Total frames driven across all sequence iterations:
  //   1 (basic) + 10 (boundary) + 20 (timing) + 1000 (stress) + 200 (byte-stream)
  localparam int unsigned PREAMBLE_GEN_001_FRAME_COUNT = 1231;

  extern function new(string name = "mac_preamble_gen_001_test_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_preamble_gen_001_test_c::new(string name = "mac_preamble_gen_001_test_c",
                                           uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 0;
  num_rs_active_agents   = 0;
  num_rs_passive_agents  = 1;
endfunction

function void mac_preamble_gen_001_test_c::configure_test();
  super.configure_test();
  env_cfg_h.max_payload_bytes = 1500;
  env_cfg_h.max_frame_octets  = 1518;
endfunction

task mac_preamble_gen_001_test_c::run_stimulus(uvm_phase phase);
  ps002_tx_preamble_sfd_seq_c seq_h;
  bit timed_out;

  seq_h = ps002_tx_preamble_sfd_seq_c::type_id::create("preamble_gen_001_seq");
  seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);

  mac_wait_utils_c::wait_for_count_at_least(
      PREAMBLE_GEN_001_FRAME_COUNT,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("TX_PREAMBLE_GEN_001",
               $sformatf("Timed out waiting for %0d TX preamble frames (received %0d)",
                          PREAMBLE_GEN_001_FRAME_COUNT,
                          env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))
  else
    `uvm_info("TX_PREAMBLE_GEN_001",
              $sformatf("PASS: all %0d TX preamble generation scenarios completed",
                         PREAMBLE_GEN_001_FRAME_COUNT), UVM_NONE)
endtask

`endif  // MAC_PREAMBLE_GEN_001_TEST_SVH
