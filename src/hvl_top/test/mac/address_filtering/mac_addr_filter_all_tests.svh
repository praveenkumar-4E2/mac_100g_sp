`ifndef MAC_ADDR_FILTER_ALL_TESTS_SVH
`define MAC_ADDR_FILTER_ALL_TESTS_SVH

//------------------------------------------------------------------------------
// Class: mac_addr_filter_all_tests_c
//
// Consolidated boundary-pattern MAC address filter tests (BND-001 through 007).
// Single class with one method per test scenario.  run_stimulus() calls all
// seven methods sequentially.
//
// Test IDs preserved in per-method comments:
//   001 - boundary pattern
//   002 - promiscuous burst
//   003 - multicast burst
//   004 - accepted/rejected sequence
//   005 - constrained random
//   006 - class alternation
//   007 - sustained injection
//------------------------------------------------------------------------------
class mac_addr_filter_all_tests_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_all_tests_c)

  rs_addr_filter_apb_mixin_c apb_mixin;

  extern function new(string name = "mac_addr_filter_all_tests_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);

  // --- Test scenario methods ---
  extern task run_boundary_pattern();              // MAC-ADDR-BND-001
  extern task run_promiscuous_burst();             // MAC-ADDR-BND-002
  extern task run_multicast_burst();               // MAC-ADDR-BND-003
  extern task run_accepted_rejected_seq();         // MAC-ADDR-BND-004
  extern task run_constrained_random_bnd();        // MAC-ADDR-BND-005
  extern task run_class_alternation();             // MAC-ADDR-BND-006
  extern task run_sustained_injection();           // MAC-ADDR-BND-007
endclass

function mac_addr_filter_all_tests_c::new(
    string name = "mac_addr_filter_all_tests_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_all_tests_c::run_stimulus(uvm_phase phase);
  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = rs_addr_filter_apb_mixin_c::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;

  run_boundary_pattern();
  #200ns;

  run_promiscuous_burst();
  #200ns;

  run_multicast_burst();
  #200ns;

  run_accepted_rejected_seq();
  #200ns;

  run_constrained_random_bnd();
  #200ns;

  run_class_alternation();
  #200ns;

  run_sustained_injection();
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-BND-001: Boundary pattern
//
// 48-bit DA boundary patterns: zero, all-ones, alternating, sequential
// neighbors, and random unicast.  Tests MODE_BOUNDARY_PATTERN.
//
// Programs local = 00:00:02:00:00:AA, disables promiscuous.
// Runs 8 boundary-pattern frames.
//
// Expected: 2 accepted (broadcast + target), 6 dropped.
//------------------------------------------------------------------------------
task mac_addr_filter_all_tests_c::run_boundary_pattern();
  rs_addr_filter_boundary_seq_c bnd_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_seq");
  bnd_seq.local_addr     = 48'h00_00_02_00_00_AA;
  bnd_seq.target_addr    = 48'h00_00_02_00_00_AA;
  bnd_seq.group_addr     = 48'h00_5E_00_01_00_01;
  bnd_seq.frame_sa       = 48'h02_00_00_00_00_01;
  bnd_seq.frame_ethertype = 16'h0800;
  bnd_seq.seq_mode       = rs_addr_filter_boundary_seq_c::MODE_BOUNDARY_PATTERN;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 2)
    `uvm_info("MAC_ADDR_BND_PATTERN", $sformatf(
        "PASS: 2 accepted (broadcast + local), 6 boundary patterns dropped"), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_BND_PATTERN", $sformatf(
        "FAIL: Expected 2 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-BND-002: Promiscuous burst
//
// Promiscuous-mode interaction: OFF -> ON -> OFF with unmatched unicast.
//
// Three sequence runs of MODE_PROMISCUOUS_BURST (5 non-matching frames each).
// Test re-programs promiscuous between runs:
//   Run 1: promiscuous OFF  -> 0 accepted (5 dropped)
//   Run 2: promiscuous ON   -> 5 accepted
//   Run 3: promiscuous OFF  -> 0 accepted (5 dropped)
//
// Expected: 5 accepted total.
//------------------------------------------------------------------------------
task mac_addr_filter_all_tests_c::run_promiscuous_burst();
  rs_addr_filter_boundary_seq_c bnd_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  #200ns;

  // --- Run 1: Promiscuous OFF -> 5 non-matching frames dropped ---
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_prom_off");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.num_frames  = 5;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_PROMISCUOUS_BURST;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_ADDR_BND_PROM", $sformatf(
      "Run 1: promiscuous OFF -- AXI RX count = %0d (expected 0)", axi_rx_cnt), UVM_NONE)

  // --- Run 2: Promiscuous ON -> 5 non-matching frames accepted ---
  enable_promiscuous_on_dut(apb_mixin);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_prom_on");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.num_frames  = 5;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_PROMISCUOUS_BURST;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_ADDR_BND_PROM", $sformatf(
      "Run 2: promiscuous ON -- AXI RX count = %0d (expected 5)", axi_rx_cnt), UVM_NONE)

  // --- Run 3: Promiscuous OFF -> 5 non-matching frames dropped ---
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_prom_off2");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.num_frames  = 5;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_PROMISCUOUS_BURST;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 5)
    `uvm_info("MAC_ADDR_BND_PROM", "PASS: 5 accepted (Run 2 only), Run 1 and 3 dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_BND_PROM", $sformatf("FAIL: Expected 5 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-BND-003: Multicast burst
//
// Active vs inactive multicast group entries.
//
// Three sequence runs of MODE_MULTICAST_BURST (3 group-addressed frames each).
// Test re-programs group table between runs:
//   Run 1: group[0] active   -> 3 accepted
//   Run 2: group[0] cleared  -> 0 accepted (3 dropped)
//   Run 3: group[0] restored -> 3 accepted
//
// Expected: 6 accepted total.
//------------------------------------------------------------------------------
task mac_addr_filter_all_tests_c::run_multicast_burst();
  rs_addr_filter_boundary_seq_c bnd_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  // --- Run 1: group[0] active -> 3 accepted ---
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_mcast_on");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.group_addr  = 48'h00_5E_00_01_00_01;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.num_frames  = 3;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_MULTICAST_BURST;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_ADDR_BND_MCAST", $sformatf(
      "Run 1: group active -- AXI RX count = %0d (expected 3)", axi_rx_cnt), UVM_NONE)

  // --- Run 2: group[0] cleared -> 0 accepted ---
  clear_group_addr_from_dut(apb_mixin, 0);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_mcast_off");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.group_addr  = 48'h00_5E_00_01_00_01;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.num_frames  = 3;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_MULTICAST_BURST;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_ADDR_BND_MCAST", $sformatf(
      "Run 2: group cleared -- AXI RX count = %0d (expected 0)", axi_rx_cnt), UVM_NONE)

  // --- Run 3: group[0] restored -> 3 accepted ---
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_mcast_restored");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.group_addr  = 48'h00_5E_00_01_00_01;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.num_frames  = 3;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_MULTICAST_BURST;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 6)
    `uvm_info("MAC_ADDR_BND_MCAST", "PASS: 6 accepted (Run 1 + Run 3), Run 2 dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_BND_MCAST", $sformatf("FAIL: Expected 6 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-BND-004: Accepted/rejected sequence
//
// Accepted -> rejected -> accepted toggle sequences with sustained traffic.
// Uses MODE_ACCEPTED_REJECTED_SEQ (19 frames).
//
// Programs local = 00:00:02:00:00:AA, group[0] = 00:5E:00:01:00:01.
//
// Expected: 11 accepted (3 + 0 + 3 + 5 across 4 phases).
//           8 dropped.
//------------------------------------------------------------------------------
task mac_addr_filter_all_tests_c::run_accepted_rejected_seq();
  rs_addr_filter_boundary_seq_c bnd_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_toggle");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.group_addr  = 48'h00_5E_00_01_00_01;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_ACCEPTED_REJECTED_SEQ;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 11)
    `uvm_info("MAC_ADDR_BND_TOGGLE", $sformatf(
        "PASS: 11 accepted across 4 phases (3+0+3+5), 8 dropped"), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_BND_TOGGLE", $sformatf(
        "FAIL: Expected 11 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-BND-005: Constrained random
//
// Constrained-random address/mode combinations using MODE_CONSTRAINED_RANDOM.
// Drives 30 frames with weighted 4-class DA distribution:
//   LOCAL 30%, GROUP 20%, BROADCAST 30%, RANDOM_UNI 20%
//
// Programs local + group[0], disables promiscuous.
//
// Expected: ~18-24 accepted (from 4-class weighted distribution).
//------------------------------------------------------------------------------
task mac_addr_filter_all_tests_c::run_constrained_random_bnd();
  rs_addr_filter_boundary_seq_c bnd_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_cr");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.group_addr  = 48'h00_5E_00_01_00_01;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.num_frames  = 30;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_CONSTRAINED_RANDOM;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt >= 18 && axi_rx_cnt <= 30)
    `uvm_info("MAC_ADDR_BND_CR", $sformatf(
        "PASS: %0d accepted from 30 constrained-random frames (expected ~18-24)", axi_rx_cnt), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_BND_CR", $sformatf(
        "FAIL: %0d accepted frames -- outside expected range [18, 30]", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-BND-006: Class alternation
//
// Alternating address classes on consecutive frames using MODE_CLASS_ALTERNATION.
// Drives 12 frames: local -> group -> broadcast repeated 4 times.
//
// Programs local + group[0], disables promiscuous.
//
// Expected: 12 accepted (all frames match programmed addresses).
//------------------------------------------------------------------------------
task mac_addr_filter_all_tests_c::run_class_alternation();
  rs_addr_filter_boundary_seq_c bnd_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_alt");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.group_addr  = 48'h00_5E_00_01_00_01;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_CLASS_ALTERNATION;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 12)
    `uvm_info("MAC_ADDR_BND_ALT", $sformatf(
        "PASS: 12 accepted -- local/group/broadcast alternation correct"), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_BND_ALT", $sformatf(
        "FAIL: Expected 12 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-BND-007: Sustained injection
//
// Sustained traffic with non-matching address injection.
// Uses MODE_SUSTAINED_WITH_INJECTION (24 frames).
//
// Phase 1: 10 broadcast (sustained, all accepted)
// Phase 2: 5 non-matching unicast injected (all dropped)
// Phase 3: 9 alternating local/group/broadcast (all accepted)
//
// Programs local + group[0], disables promiscuous.
//
// Expected: 19 accepted, 5 dropped.
//------------------------------------------------------------------------------
task mac_addr_filter_all_tests_c::run_sustained_injection();
  rs_addr_filter_boundary_seq_c bnd_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  bnd_seq = rs_addr_filter_boundary_seq_c::type_id::create("bnd_inject");
  bnd_seq.local_addr  = 48'h00_00_02_00_00_AA;
  bnd_seq.group_addr  = 48'h00_5E_00_01_00_01;
  bnd_seq.frame_sa    = 48'h02_00_00_00_00_01;
  bnd_seq.seq_mode    = rs_addr_filter_boundary_seq_c::MODE_SUSTAINED_WITH_INJECTION;
  bnd_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 19)
    `uvm_info("MAC_ADDR_BND_INJECT", $sformatf(
        "PASS: 19 accepted (10 broadcast + 9 alternating), 5 non-matching dropped"), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_BND_INJECT", $sformatf(
        "FAIL: Expected 19 accepted frames, got %0d", axi_rx_cnt))
endtask

`endif  // MAC_ADDR_FILTER_ALL_TESTS_SVH
