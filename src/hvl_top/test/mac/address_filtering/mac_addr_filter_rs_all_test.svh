`ifndef MAC_ADDR_FILTER_RS_ALL_TEST_SVH
`define MAC_ADDR_FILTER_RS_ALL_TEST_SVH

//------------------------------------------------------------------------------
// APB helper mixin for address-filtering tests (self-contained).
//------------------------------------------------------------------------------
class rs_addr_filter_apb_mixin_c extends uvm_object;
  `uvm_object_utils(rs_addr_filter_apb_mixin_c)

  mac_env_c env_h;

  extern function new(string name = "rs_addr_filter_apb_mixin_c");
  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
endclass

function rs_addr_filter_apb_mixin_c::new(string name = "rs_addr_filter_apb_mixin_c");
  super.new(name);
endfunction

task rs_addr_filter_apb_mixin_c::apb_write(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task rs_addr_filter_apb_mixin_c::apb_read(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_read_sequence_c read_h;
  read_h = apb_read_sequence_c::type_id::create($sformatf("apb_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = read_h.m_rdata;
endtask

//------------------------------------------------------------------------------
// Register-write helper tasks.
//------------------------------------------------------------------------------
task write_local_addr_to_dut(
    rs_addr_filter_apb_mixin_c apb,
    bit [47:0] addr);
  apb.apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  {32{1'b0}} | addr[31:0]);
  apb.apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, {32{1'b0}} | addr[47:32]);
endtask

task write_group_addr_to_dut(
    rs_addr_filter_apb_mixin_c apb,
    int unsigned index,
    bit [47:0] addr,
    bit valid = 1'b1);
  bit [31:0] high_word;
  high_word = {15'b0, valid, addr[47:32]};
  apb.apb_write(reg_map_pkg::group_low_addr(index),  {32{1'b0}} | addr[31:0]);
  apb.apb_write(reg_map_pkg::group_high_addr(index), high_word);
endtask

task clear_group_addr_from_dut(
    rs_addr_filter_apb_mixin_c apb,
    int unsigned index);
  apb.apb_write(reg_map_pkg::group_low_addr(index),  32'h0);
  apb.apb_write(reg_map_pkg::group_high_addr(index), 32'h0);
endtask

task enable_promiscuous_on_dut(
    rs_addr_filter_apb_mixin_c apb);
  apb.apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
endtask

task disable_promiscuous_on_dut(
    rs_addr_filter_apb_mixin_c apb);
  apb.apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_rs_all_tests_c
//
// Consolidated RS-sequence MAC address filter tests (RS-001 through RS-006).
// Single class with one method per test scenario.  run_stimulus() calls all
// six methods sequentially.
//
// Test IDs preserved in per-method comments:
//   001 - basic config
//   002 - address classes
//   003 - promiscuous sequence
//   004 - boundary sequence
//   005 - toggle stress sequence
//   006 - random modes
//------------------------------------------------------------------------------
class mac_addr_filter_rs_all_tests_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_rs_all_tests_c)

  rs_addr_filter_apb_mixin_c apb_mixin;

  extern function new(string name = "mac_addr_filter_rs_all_tests_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);

  // --- Test scenario methods ---
  extern task run_basic_config();              // MAC-ADDR-RS-001
  extern task run_addr_classes();              // MAC-ADDR-RS-002
  extern task run_promiscuous_seq();           // MAC-ADDR-RS-003
  extern task run_boundary_seq();              // MAC-ADDR-RS-004
  extern task run_toggle_stress_seq();         // MAC-ADDR-RS-005
  extern task run_random_modes();              // MAC-ADDR-RS-006
endclass

function mac_addr_filter_rs_all_tests_c::new(
    string name = "mac_addr_filter_rs_all_tests_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_rs_all_tests_c::run_stimulus(uvm_phase phase);
  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = rs_addr_filter_apb_mixin_c::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;

  run_basic_config();
  #200ns;

  run_addr_classes();
  #200ns;

  run_promiscuous_seq();
  #200ns;

  run_boundary_seq();
  #200ns;

  run_toggle_stress_seq();
  #200ns;

  run_random_modes();
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-RS-001: Basic config
//
// Basic configuration: default filtering with valid local-unicast DA,
// valid SA, valid EtherType, valid payload, and valid FCS.
//
// Programs local + group, disables promiscuous.
// Runs MODE_BASIC_CONFIG (5 deterministic frames).
//
// Expected: 3 accepted (local + broadcast + group), 2 dropped.
//------------------------------------------------------------------------------
task mac_addr_filter_rs_all_tests_c::run_basic_config();
  rs_addr_filter_sequence_c addr_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("basic_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.num_addr_frames = 5;
  addr_seq.seq_mode        = rs_addr_filter_sequence_c::MODE_BASIC_CONFIG;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 3)
    `uvm_info("MAC_ADDR_RS_BASIC", "PASS: 3 accepted (local + bcast + group), 2 dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_RS_BASIC", $sformatf("FAIL: Expected 3 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-RS-002: Address classes
//
// Address class coverage: local unicast, unrelated unicast, broadcast,
// active multicast, inactive/unconfigured multicast, and near-miss unicast.
//
// Programs local + group[0], disables promiscuous.
// Runs MODE_ADDR_CLASSES (6 deterministic frames).
//
// Expected: 3 accepted (local + bcast + active mcast), 3 dropped.
//------------------------------------------------------------------------------
task mac_addr_filter_rs_all_tests_c::run_addr_classes();
  rs_addr_filter_sequence_c addr_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("classes_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.num_addr_frames = 6;
  addr_seq.seq_mode        = rs_addr_filter_sequence_c::MODE_ADDR_CLASSES;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 3)
    `uvm_info("MAC_ADDR_RS_CLASSES", "PASS: 3 accepted (local + bcast + active mcast), 3 dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_RS_CLASSES", $sformatf("FAIL: Expected 3 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-RS-003: Promiscuous sequence
//
// Promiscuous-mode interaction: OFF -> ON -> OFF with unmatched unicast.
//
// Three sequence runs of MODE_PROMISCUOUS (5 non-matching frames each).
// Test re-programs promiscuous between runs:
//   Run 1: promiscuous OFF  -> 0 accepted (5 dropped)
//   Run 2: promiscuous ON   -> 5 accepted
//   Run 3: promiscuous OFF  -> 0 accepted (5 dropped)
//
// Expected: 5 accepted total.
//------------------------------------------------------------------------------
task mac_addr_filter_rs_all_tests_c::run_promiscuous_seq();
  rs_addr_filter_sequence_c addr_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  #200ns;

  // --- Phase A: Promiscuous OFF -> 5 non-matching frames dropped ---
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("prom_off_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.num_burst_frames = 5;
  addr_seq.seq_mode        = rs_addr_filter_sequence_c::MODE_PROMISCUOUS;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_ADDR_RS_PROM", $sformatf(
      "Phase A: promiscuous OFF -- AXI RX count = %0d (expected 0)", axi_rx_cnt), UVM_NONE)

  // --- Phase B: Promiscuous ON -> 5 non-matching frames accepted ---
  enable_promiscuous_on_dut(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("prom_on_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.num_burst_frames = 5;
  addr_seq.seq_mode        = rs_addr_filter_sequence_c::MODE_PROMISCUOUS;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_ADDR_RS_PROM", $sformatf(
      "Phase B: promiscuous ON -- AXI RX count = %0d (expected 5)", axi_rx_cnt), UVM_NONE)

  // --- Phase C: Promiscuous OFF -> 5 non-matching frames dropped ---
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("prom_off2_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.num_burst_frames = 5;
  addr_seq.seq_mode        = rs_addr_filter_sequence_c::MODE_PROMISCUOUS;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 5)
    `uvm_info("MAC_ADDR_RS_PROM", "PASS: 5 accepted (Phase B only), Phase A and C dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_RS_PROM", $sformatf("FAIL: Expected 5 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-RS-004: Boundary sequence
//
// 48-bit DA/SA boundary patterns: zero, all-ones, alternating, sequential
// neighbors (target-2, target-1, target, target+1, target+2), and random.
// SA tested with zero, all-ones, and alternating patterns.
//
// Programs local = 00:00:02:00:00:AA, disables promiscuous.
// Runs MODE_BOUNDARY_PATTERN (10 DA x 3 SA = 30 frames).
//
// Expected: 6 accepted (PAT_ALL_ONES x 3 SAs + PAT_TARGET x 3 SAs).
//           24 dropped.
//------------------------------------------------------------------------------
task mac_addr_filter_rs_all_tests_c::run_boundary_seq();
  rs_addr_filter_sequence_c addr_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("boundary_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.seq_mode        = rs_addr_filter_sequence_c::MODE_BOUNDARY_PATTERN;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 6)
    `uvm_info("MAC_ADDR_RS_BOUNDARY", $sformatf(
        "PASS: 6 accepted (broadcast x 3 SAs + local x 3 SAs), 24 dropped"), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_RS_BOUNDARY", $sformatf("FAIL: Expected 6 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-RS-005: Toggle stress sequence
//
// Accepted -> rejected -> accepted with mixed address classes and sustained
// traffic with non-matching injection.
//
// Programs local + group[0], disables promiscuous.
// Runs MODE_TOGGLE_STRESS (19 frames).
//
// Expected: 11 accepted (3 + 0 + 3 + 5 across 4 phases).
//           8 dropped.
//------------------------------------------------------------------------------
task mac_addr_filter_rs_all_tests_c::run_toggle_stress_seq();
  rs_addr_filter_sequence_c addr_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("toggle_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.num_addr_frames = 19;
  addr_seq.seq_mode        = rs_addr_filter_sequence_c::MODE_TOGGLE_STRESS;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 11)
    `uvm_info("MAC_ADDR_RS_TOGGLE", $sformatf(
        "PASS: 11 accepted across 4 phases (3+0+3+5), 8 dropped"), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_RS_TOGGLE", $sformatf("FAIL: Expected 11 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// MAC-ADDR-RS-006: Random modes
//
// Constrained-random mixed traffic using MODE_RANDOM_COMBINED (default).
// Backward-compatible with existing constrained-random tests.
//
// Programs local + group[0], disables promiscuous.
// Runs 30 constrained-random frames.
//
// Expected: ~18-24 accepted (from 4-class weighted distribution).
//------------------------------------------------------------------------------
task mac_addr_filter_rs_all_tests_c::run_random_modes();
  rs_addr_filter_sequence_c addr_seq;
  int axi_rx_cnt;

  write_local_addr_to_dut(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr_to_dut(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous_on_dut(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("random_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.num_addr_frames = 30;
  addr_seq.seq_mode        = rs_addr_filter_sequence_c::MODE_RANDOM_COMBINED;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt >= 18 && axi_rx_cnt <= 30)
    `uvm_info("MAC_ADDR_RS_RANDOM", $sformatf(
        "PASS: %0d accepted from 30 constrained-random frames (expected ~18-24)", axi_rx_cnt), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_RS_RANDOM", $sformatf(
        "FAIL: %0d accepted frames -- outside expected range [18, 30]", axi_rx_cnt))
endtask

`endif  // MAC_ADDR_FILTER_RS_ALL_TEST_SVH
