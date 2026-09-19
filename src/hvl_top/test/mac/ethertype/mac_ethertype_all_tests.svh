`ifndef MAC_ETHERTYPE_ALL_TESTS_SVH
`define MAC_ETHERTYPE_ALL_TESTS_SVH

// ============================================================================
// Combined EtherType test file — all scenarios in a single class.
//
// Uses the single mac_ethertype_seq_c which covers all seven scenarios:
//   1. basic        — single 0x8808 frame (1)
//   2. boundary     — 0x8807, 0x8808, 0x8809 (3)
//   3. bitflip      — 16 bit-flips of 0x8808 (16)
//   4. malformed    — wrong opcode / wrong DA (6)
//   5. typical      — common Type + Length + invalid (10)
//   6. stress       — mixed, B2B, constrained-random (33)
//   7. address      — DA class alternation, SA vary (15)
//
// Total frames: 84
// ============================================================================

localparam int unsigned ETHERTYPE_TOTAL_FRAME_COUNT = 84;

class mac_ethertype_all_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_ethertype_all_test_c)

  extern function new(string name = "mac_ethertype_all_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);

  extern local function void configure_ethertype_test();
  extern local task run_ethertype_stimulus(uvm_phase phase, string tag);
endclass

function mac_ethertype_all_test_c::new(string name = "mac_ethertype_all_test_c",
                                       uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 0;
  num_rs_active_agents   = 0;
  num_rs_passive_agents  = 1;
endfunction

function void mac_ethertype_all_test_c::configure_ethertype_test();
  env_cfg_h.scoreboard_enable_tx_check    = 1;
  env_cfg_h.scoreboard_enable_rx_check    = 0;
  env_cfg_h.scoreboard_check_ether_type   = 1;
  env_cfg_h.scoreboard_check_error_flags  = 0;
  env_cfg_h.has_protocol_checkers         = 1;
endfunction

function void mac_ethertype_all_test_c::configure_test();
  super.configure_test();
  configure_ethertype_test();
endfunction

task mac_ethertype_all_test_c::run_ethertype_stimulus(uvm_phase phase, string tag);
  mac_ethertype_seq_c seq_h;
  bit timed_out;

  seq_h = mac_ethertype_seq_c::type_id::create("ethertype_seq");
  seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);

  mac_wait_utils_c::wait_for_count_at_least(
      ETHERTYPE_TOTAL_FRAME_COUNT,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error(tag, $sformatf(
        "Timed out waiting for %0d RS TX frames (received %0d)",
        ETHERTYPE_TOTAL_FRAME_COUNT,
        env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))
  else
    `uvm_info(tag, "PASS: All EtherType scenarios completed", UVM_NONE)
endtask

task mac_ethertype_all_test_c::run_stimulus(uvm_phase phase);
  run_ethertype_stimulus(phase, "ETHERTYPE_ALL");
endtask

`endif
