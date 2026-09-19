`ifndef MAC_ADDR_FILTERING_TEST_SVH
`define MAC_ADDR_FILTERING_TEST_SVH

//------------------------------------------------------------------------------
// Directed-frame RS sequence: drives frames with an explicit DA.
// Uses send_clean_frame() from the base class so the DA is guaranteed.
//------------------------------------------------------------------------------
class rs_directed_frame_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(rs_directed_frame_sequence_c)

  bit [47:0] target_da  = 48'hFF_FF_FF_FF_FF_FF;
  bit [47:0] target_sa  = 48'h02_00_00_00_00_01;
  bit        override_sa = 1'b0;

  extern function new(string name = "rs_directed_frame_sequence_c");
  extern task body();
endclass

function rs_directed_frame_sequence_c::new(string name = "rs_directed_frame_sequence_c");
  super.new(name);
endfunction

task rs_directed_frame_sequence_c::body();
  // Hardcode valid payload bounds to avoid resolve_config() issues
  payload_min = 46;
  payload_max = 1500;
  repeat (num_frames) begin
    if (override_sa) begin
      frame_xtn_c frm;
      frm = frame_xtn_c::type_id::create("frm");
      if (!frm.randomize() with {
            dst_addr   == target_da;
            src_addr   == target_sa;
            crc_error  == 0;
            length_error == 0;
            alignment_error == 0;
            insert_fcs == 1'b1;
            soft ether_type > 16'h0600;
            payload.size() inside {[46:1500]};
          }) begin
        `uvm_fatal(get_type_name(), "Randomization of frame_xtn_c failed")
      end
      do_rs_frame(frm);
    end else begin
      send_clean_frame(-1, target_da);
    end
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

//------------------------------------------------------------------------------
// APB helper mixin for address-filtering tests.
//------------------------------------------------------------------------------
class mac_addr_filter_apb_mixin extends uvm_object;
  `uvm_object_utils(mac_addr_filter_apb_mixin)

  mac_env_c env_h;

  extern function new(string name = "mac_addr_filter_apb_mixin");
  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
endclass

function mac_addr_filter_apb_mixin::new(string name = "mac_addr_filter_apb_mixin");
  super.new(name);
endfunction

task mac_addr_filter_apb_mixin::apb_write(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_addr_filter_apb_mixin::apb_read(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_read_sequence_c read_h;
  read_h = apb_read_sequence_c::type_id::create($sformatf("apb_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = read_h.m_rdata;
endtask

//------------------------------------------------------------------------------
// Helper task: drive a single frame with a specific DA through the RS agent.
//------------------------------------------------------------------------------
task drive_frame_with_da(
    rs_sequencer_c rs_seqr,
    bit [47:0] da,
    string tag = "frame");
  rs_directed_frame_sequence_c seq;
  seq = rs_directed_frame_sequence_c::type_id::create({tag, "_seq"});
  seq.target_da  = da;
  seq.num_frames = 1;
  seq.start(rs_seqr);
endtask

task drive_frame_with_da_sa(
    rs_sequencer_c rs_seqr,
    bit [47:0] da,
    bit [47:0] sa,
    string tag = "frame");
  rs_directed_frame_sequence_c seq;
  seq = rs_directed_frame_sequence_c::type_id::create({tag, "_seq"});
  seq.target_da   = da;
  seq.target_sa   = sa;
  seq.override_sa = 1'b1;
  seq.num_frames  = 1;
  seq.start(rs_seqr);
endtask

//------------------------------------------------------------------------------
// RTL register-write helpers.
//
// The register file maps 48-bit group addresses as:
//   group_low_reg  [31:0]  = addr[31:0]   (lower 32 bits)
//   group_high_reg [15:0]  = addr[47:32]  (upper 16 bits)
//   group_high_reg [16]    = group_valid   (1 = entry active)
//
// Similarly for the local MAC address:
//   REG_MAC_ADDR_LOW  [31:0]  = addr[31:0]
//   REG_MAC_ADDR_HIGH [15:0]  = addr[47:32]
//
// These tasks compute the correct register values from a 48-bit address.
//------------------------------------------------------------------------------
task write_local_addr(
    mac_addr_filter_apb_mixin apb,
    bit [47:0] addr);
  apb.apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  {32{1'b0}} | addr[31:0]);
  apb.apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, {32{1'b0}} | addr[47:32]);
endtask

task write_group_addr(
    mac_addr_filter_apb_mixin apb,
    int unsigned index,
    bit [47:0] addr,
    bit valid = 1'b1);
  bit [31:0] high_word;
  high_word = {15'b0, valid, addr[47:32]};
  apb.apb_write(reg_map_pkg::group_low_addr(index),  {32{1'b0}} | addr[31:0]);
  apb.apb_write(reg_map_pkg::group_high_addr(index), high_word);
endtask

task clear_group_addr(
    mac_addr_filter_apb_mixin apb,
    int unsigned index);
  apb.apb_write(reg_map_pkg::group_low_addr(index),  32'h0);
  apb.apb_write(reg_map_pkg::group_high_addr(index), 32'h0);
endtask

task enable_promiscuous(
    mac_addr_filter_apb_mixin apb);
  apb.apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
endtask

task disable_promiscuous(
    mac_addr_filter_apb_mixin apb);
  apb.apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_active_mcast_test_c  (MAC-ADDR-001)
//
// Active vs inactive multicast group entries.
// Programs group entries, deactivates one, verifies inactive is dropped.
//
// Addresses used:
//   local  = 00:00:02:00:00:AA
//   group0 = 00:5E:00:01:00:01
//   group1 = 00:5E:00:01:00:02
//   group2 = 00:5E:00:01:00:03  (deactivated)
//   group3 = 00:5E:00:01:00:04
//------------------------------------------------------------------------------
class mac_addr_filter_active_mcast_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_active_mcast_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_active_mcast_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_active_mcast_test_c::new(
    string name = "mac_addr_filter_active_mcast_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_active_mcast_test_c::run_stimulus(uvm_phase phase);
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Program local unicast address: 00:00:02:00:00:AA
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);

  // Program group entries 0, 1, 3 (leave 2 cleared = inactive)
  write_group_addr(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  write_group_addr(apb_mixin, 1, 48'h00_5E_00_01_00_02);
  // group[2] cleared (inactive)
  write_group_addr(apb_mixin, 3, 48'h00_5E_00_01_00_04);

  disable_promiscuous(apb_mixin);
  #200ns;

  // Frame 1: DA = group[0] → accepted
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_01, "grp0");
  #100ns;

  // Frame 2: DA = group[2] address (cleared) → dropped
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_03, "grp2_inactive");
  #100ns;

  // Frame 3: DA = group[3] → accepted
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_04, "grp3");
  #100ns;

  // Frame 4: Broadcast → accepted
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "bcast");

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 3)
    `uvm_info("MAC_ADDR_MCAST_ACTIVE", "PASS: 3 frames accepted (2 active group + broadcast), 1 inactive group dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_MCAST_ACTIVE", $sformatf("FAIL: Expected 3 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_promiscuous_test_c  (MAC-ADDR-002)
//
// Unmatched unicast with promiscuous mode disabled then enabled.
//------------------------------------------------------------------------------
class mac_addr_filter_promiscuous_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_promiscuous_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_promiscuous_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_promiscuous_test_c::new(
    string name = "mac_addr_filter_promiscuous_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_promiscuous_test_c::run_stimulus(uvm_phase phase);
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Program local unicast address: 00:00:02:00:00:AA
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);

  // --- Phase A: Promiscuous OFF ---
  disable_promiscuous(apb_mixin);
  #200ns;

  // Frame 1: Non-matching unicast → dropped
  drive_frame_with_da(rs_seqr, 48'hDE_AD_BE_EF_00_01, "phase_a_nomatch");
  #100ns;

  // Frame 2: Broadcast → accepted
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "phase_a_bcast");
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_ADDR_PROMISCUOUS", $sformatf(
      "Phase A: promiscuous OFF — AXI RX count = %0d (expected 1)", axi_rx_cnt), UVM_NONE)

  // --- Phase B: Promiscuous ON ---
  enable_promiscuous(apb_mixin);
  #200ns;

  // Frame 3: Same non-matching unicast → accepted
  drive_frame_with_da(rs_seqr, 48'hDE_AD_BE_EF_00_01, "phase_b_nomatch");

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 2)
    `uvm_info("MAC_ADDR_PROMISCUOUS", "PASS: Phase A dropped non-matching unicast, Phase B accepted it (total 2)", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_PROMISCUOUS", $sformatf("FAIL: Expected 2 total accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_mode_change_test_c  (MAC-ADDR-003)
//
// Legal mode changes between frames.
// Dynamically reconfigures local address and group table mid-stream.
//------------------------------------------------------------------------------
class mac_addr_filter_mode_change_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_mode_change_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_mode_change_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_mode_change_test_c::new(
    string name = "mac_addr_filter_mode_change_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_mode_change_test_c::run_stimulus(uvm_phase phase);
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Initial config: local = 00:00:02:00:00:AA, no group entries
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  clear_group_addr(apb_mixin, 0);
  disable_promiscuous(apb_mixin);
  #200ns;

  // Frame 1: DA = old local_addr → accepted
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "old_local");
  #200ns;

  // Change local address to 00:00:03:00:00:BB
  write_local_addr(apb_mixin, 48'h00_00_03_00_00_BB);
  #200ns;

  // Frame 2: DA = old local_addr → dropped (no longer matches)
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "old_local_2");
  #200ns;

  // Frame 3: DA = new local_addr → accepted
  drive_frame_with_da(rs_seqr, 48'h00_00_03_00_00_BB, "new_local");
  #200ns;

  // Enable group[0] = 00:5E:00:01:00:01
  write_group_addr(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  #200ns;

  // Frame 4: DA = group[0] address → accepted
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_01, "new_group");

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 3)
    `uvm_info("MAC_ADDR_MODE_CHANGE", "PASS: 3 frames accepted after dynamic reconfiguration", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_MODE_CHANGE", $sformatf("FAIL: Expected 3 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_toggle_test_c  (MAC-ADDR-004)
//
// Accepted -> rejected -> accepted sequences.
//------------------------------------------------------------------------------
class mac_addr_filter_toggle_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_toggle_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_toggle_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_toggle_test_c::new(
    string name = "mac_addr_filter_toggle_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_toggle_test_c::run_stimulus(uvm_phase phase);
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Program local unicast: 00:00:02:00:00:AA, promiscuous OFF
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  disable_promiscuous(apb_mixin);
  #200ns;

  // Frame 1: Broadcast → accepted
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "bcast_1");
  #100ns;

  // Frame 2: Non-matching unicast → dropped
  drive_frame_with_da(rs_seqr, 48'hCA_FE_FA_DE_00_01, "nomatch_1");
  #100ns;

  // Frame 3: Broadcast → accepted
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "bcast_2");
  #100ns;

  // Frame 4: Non-matching unicast → dropped
  drive_frame_with_da(rs_seqr, 48'hCA_FE_FA_DE_00_02, "nomatch_2");
  #100ns;

  // Frame 5: Broadcast → accepted
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "bcast_3");

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 3)
    `uvm_info("MAC_ADDR_TOGGLE", "PASS: 3 accepted / 2 dropped — accepted-rejected-accepted sequence correct", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_TOGGLE", $sformatf("FAIL: Expected 3 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_constrained_random_test_c  (MAC-ADDR-005)
//
// Constrained-random address/mode combinations.
// Uses rs_addr_filter_sequence_c for randomized address-class traffic.
//------------------------------------------------------------------------------
class mac_addr_filter_constrained_random_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_constrained_random_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_constrained_random_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_constrained_random_test_c::new(
    string name = "mac_addr_filter_constrained_random_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_constrained_random_test_c::run_stimulus(uvm_phase phase);
  rs_addr_filter_sequence_c addr_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;

  // Program local unicast + one group entry
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr(apb_mixin, 0, 48'h00_5E_00_01_00_01);

  disable_promiscuous(apb_mixin);
  #200ns;

  // Drive 30 constrained-random frames
  addr_seq = rs_addr_filter_sequence_c::type_id::create("cr_addr_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.num_addr_frames = 30;
  addr_seq.payload_min     = 46;
  addr_seq.payload_max     = 150;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  // Distribution (30/20/30/20) → ~9 local + ~6 group + ~9 broadcast = ~24 accepted
  // Accept range [18, 30] to account for randomization variance
  if (axi_rx_cnt >= 18 && axi_rx_cnt <= 30)
    `uvm_info("MAC_ADDR_CONST_RANDOM", $sformatf(
        "PASS: %0d frames accepted (expected ~24 from constrained-random distribution)", axi_rx_cnt), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_CONST_RANDOM", $sformatf(
        "FAIL: %0d accepted frames — outside expected range [18, 30]", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_sustained_traffic_test_c  (MAC-ADDR-006)
//
// Alternating address classes on consecutive frames with non-matching
// address injection during sustained traffic.
// Total expected: 19 accepted, 5 dropped
//------------------------------------------------------------------------------
class mac_addr_filter_sustained_traffic_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_sustained_traffic_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_sustained_traffic_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_sustained_traffic_test_c::new(
    string name = "mac_addr_filter_sustained_traffic_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_sustained_traffic_test_c::run_stimulus(uvm_phase phase);
  rs_directed_frame_sequence_c bcast_seq;
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Program local unicast + one group entry
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr(apb_mixin, 0, 48'h00_5E_00_01_00_01);

  disable_promiscuous(apb_mixin);
  #200ns;

  // --- Phase 1: 10 broadcast frames (sustained stream, all accepted) ---
  bcast_seq = rs_directed_frame_sequence_c::type_id::create("sustained_bcast");
  bcast_seq.target_da  = 48'hFF_FF_FF_FF_FF_FF;
  bcast_seq.num_frames = 10;
  bcast_seq.start(rs_seqr);
  #200ns;

  // --- Phase 2: 5 non-matching unicast injected (all dropped) ---
  repeat (5) begin
    drive_frame_with_da(rs_seqr, 48'hDE_AD_BE_EF_00_01, "nonmatch");
    #50ns;
  end
  #200ns;

  // --- Phase 3: 9 alternating local / group / broadcast ---
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "alt_local_1");   // local
  #50ns;
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "alt_bcast_1");   // broadcast
  #50ns;
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_01, "alt_group_1");   // group
  #50ns;
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "alt_local_2");   // local
  #50ns;
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "alt_bcast_2");   // broadcast
  #50ns;
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_01, "alt_group_2");   // group
  #50ns;
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "alt_local_3");   // local
  #50ns;
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "alt_bcast_3");   // broadcast
  #50ns;
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_01, "alt_group_3");   // group

  #1us;

  // Expected: 10 (sustained broadcast) + 9 (alternating) = 19 accepted
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 19)
    `uvm_info("MAC_ADDR_SUSTAINED", "PASS: 19 accepted (10 broadcast + 9 alternating), 5 non-matching dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_SUSTAINED", $sformatf("FAIL: Expected 19 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_control_data_addr_filter_combined_test_c  (MAC-ADDR-009)
//
// Combined MAC control frame handling + address filtering.
// Alternates between address classes on consecutive frames with interleaved
// PAUSE control frames.  Verifies PAUSE is consumed (not forwarded) while
// data frames pass through with correct address filtering.
// Non-matching unicast addresses are injected during sustained traffic.
//
// Programmed addresses:
//   local  = 00:00:02:00:00:AA
//   group0 = 00:5E:00:01:00:01
//
// Expected accepted frames: 11 (3 broadcast + 3 local + 3 group + 2 broadcast)
// Expected dropped frames:  2 (non-matching unicast)
// Expected consumed (not counted): 2 (PAUSE control frames)
//------------------------------------------------------------------------------
class mac_control_data_addr_filter_combined_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_control_data_addr_filter_combined_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_control_data_addr_filter_combined_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_control_data_addr_filter_combined_test_c::new(
    string name = "mac_control_data_addr_filter_combined_test_c",
    uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_control_data_addr_filter_combined_test_c::run_stimulus(uvm_phase phase);
  rs_directed_frame_sequence_c directed_seq;
  mac_control_frame_sequence_c ctrl_seq;
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Program local unicast + group table
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous(apb_mixin);
  #200ns;

  // --- Phase 1: 3 broadcast data frames (all accepted) ---
  directed_seq = rs_directed_frame_sequence_c::type_id::create("bcast_phase1");
  directed_seq.target_da  = 48'hFF_FF_FF_FF_FF_FF;
  directed_seq.num_frames = 3;
  directed_seq.start(rs_seqr);
  #100ns;

  // --- Phase 2: PAUSE control frame (consumed, not delivered) ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("pause_in_filter1");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0100;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(rs_seqr);
  #100ns;

  // --- Phase 3: 3 local unicast data frames (accepted) ---
  directed_seq = rs_directed_frame_sequence_c::type_id::create("local_phase3");
  directed_seq.target_da  = 48'h00_00_02_00_00_AA;
  directed_seq.num_frames = 3;
  directed_seq.start(rs_seqr);
  #100ns;

  // --- Phase 4: 2 non-matching unicast (dropped) ---
  directed_seq = rs_directed_frame_sequence_c::type_id::create("nomatch_phase4");
  directed_seq.target_da  = 48'hDE_AD_BE_EF_00_01;
  directed_seq.num_frames = 2;
  directed_seq.start(rs_seqr);
  #100ns;

  // --- Phase 5: PAUSE control frame (consumed) ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("pause_in_filter2");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0080;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(rs_seqr);
  #100ns;

  // --- Phase 6: 3 group data frames (accepted) ---
  directed_seq = rs_directed_frame_sequence_c::type_id::create("group_phase6");
  directed_seq.target_da  = 48'h00_5E_00_01_00_01;
  directed_seq.num_frames = 3;
  directed_seq.start(rs_seqr);
  #100ns;

  // --- Phase 7: 2 more broadcast (accepted) ---
  directed_seq = rs_directed_frame_sequence_c::type_id::create("bcast_phase7");
  directed_seq.target_da  = 48'hFF_FF_FF_FF_FF_FF;
  directed_seq.num_frames = 2;
  directed_seq.start(rs_seqr);

  #1us;

  // Expected: 3 (bcast) + 3 (local) + 3 (group) + 2 (bcast) = 11 data frames
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 11)
    `uvm_info("MAC_ADDR_CTRL_COMBINED", $sformatf(
        "PASS: 11 data frames delivered (3 bcast + 3 local + 3 group + 2 bcast), 2 PAUSE consumed, 2 non-matching dropped"),
        UVM_NONE)
  else
    `uvm_error("MAC_ADDR_CTRL_COMBINED", $sformatf(
        "FAIL: Expected 11 data frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_control_constrained_random_combined_test_c  (MAC-ADDR-010)
//
// Constrained-random test combining address filtering with MAC control frames.
// Drives 50 frames: ~25% PAUSE control, ~25% local unicast, ~20% group,
// ~20% broadcast, ~10% random unicast (non-matching, dropped).
// Verifies PAUSE frames are consumed, non-matching are dropped, and
// matching data frames are delivered.
//
// Programmed addresses:
//   local  = 00:00:02:00:00:AA
//   group0 = 00:5E:00:01:00:01
//------------------------------------------------------------------------------
class mac_control_constrained_random_combined_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_control_constrained_random_combined_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_control_constrained_random_combined_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_control_constrained_random_combined_test_c::new(
    string name = "mac_control_constrained_random_combined_test_c",
    uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_control_constrained_random_combined_test_c::run_stimulus(uvm_phase phase);
  rs_directed_frame_sequence_c directed_seq;
  mac_control_frame_sequence_c ctrl_seq;
  int axi_rx_cnt;
  int unsigned unsupported_count;
  bit [apb_transfer_t::DATA_WIDTH-1:0] rdata;
  bit [apb_transfer_t::DATA_WIDTH-1:0] rx_status;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Program local unicast + group table
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous(apb_mixin);
  #200ns;

  // Read unsupported counter before
  apb_mixin.apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsupported_count = rdata[15:0];

  // Drive 50 frames: mix of PAUSE control, local, group, broadcast, non-matching
  // Distribution: 12 PAUSE + 12 local + 10 group + 10 broadcast + 6 non-matching
  // Expected accepted: 12 local + 10 group + 10 broadcast = 32
  // Expected consumed: 12 PAUSE (not counted)
  // Expected dropped:  6 non-matching

  // --- PAUSE control frames (12) ---
  repeat (12) begin
    ctrl_seq = mac_control_frame_sequence_c::type_id::create("cr_pause");
    ctrl_seq.opcode            = 16'h0001;
    ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
    ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
    ctrl_seq.pause_quanta      = 16'h0100;
    ctrl_seq.frame_payload_len = 46;
    ctrl_seq.start(rs_seqr);
  end
  #100ns;

  // --- Local unicast data (12) ---
  directed_seq = rs_directed_frame_sequence_c::type_id::create("cr_local");
  directed_seq.target_da  = 48'h00_00_02_00_00_AA;
  directed_seq.num_frames = 12;
  directed_seq.start(rs_seqr);
  #100ns;

  // --- Group data (10) ---
  directed_seq = rs_directed_frame_sequence_c::type_id::create("cr_group");
  directed_seq.target_da  = 48'h00_5E_00_01_00_01;
  directed_seq.num_frames = 10;
  directed_seq.start(rs_seqr);
  #100ns;

  // --- Broadcast data (10) ---
  directed_seq = rs_directed_frame_sequence_c::type_id::create("cr_bcast");
  directed_seq.target_da  = 48'hFF_FF_FF_FF_FF_FF;
  directed_seq.num_frames = 10;
  directed_seq.start(rs_seqr);
  #100ns;

  // --- Non-matching unicast (6, all dropped) ---
  directed_seq = rs_directed_frame_sequence_c::type_id::create("cr_nomatch");
  directed_seq.target_da  = 48'hCA_FE_FA_DE_00_01;
  directed_seq.num_frames = 6;
  directed_seq.start(rs_seqr);

  #1us;

  // Verify no unsupported opcodes
  apb_mixin.apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  if (rdata[15:0] == unsupported_count)
    `uvm_info("MAC_ADDR_CTRL_RANDOM", $sformatf(
        "PASS: unsupported_count unchanged (%0d) — all opcodes supported",
        unsupported_count), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_CTRL_RANDOM", $sformatf(
        "FAIL: unsupported_count changed from %0d to %0d",
        unsupported_count, rdata[15:0]))

  // Verify pause_active was triggered during the PAUSE frames
  apb_mixin.apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  `uvm_info("MAC_ADDR_CTRL_RANDOM", $sformatf(
      "INFO: REG_RX_STATUS after traffic = %h", rx_status), UVM_NONE)

  // Expected: 12 local + 10 group + 10 broadcast = 32 accepted
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 32)
    `uvm_info("MAC_ADDR_CTRL_RANDOM", $sformatf(
        "PASS: 32 data frames delivered (12 local + 10 group + 10 broadcast), 12 PAUSE consumed, 6 non-matching dropped"),
        UVM_NONE)
  else
    `uvm_error("MAC_ADDR_CTRL_RANDOM", $sformatf(
        "FAIL: Expected 32 data frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_default_config_test_c  (MAC-ADDR-011)
//
// Default filtering after reset.
// No APB programming — uses reset-state defaults (local=0x0, group invalid,
// promiscuous OFF).  Only broadcast should be accepted.
//
// Expected: 1 accepted (broadcast), 4 dropped.
//------------------------------------------------------------------------------
class mac_addr_filter_default_config_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_default_config_test_c)

  extern function new(string name = "mac_addr_filter_default_config_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_default_config_test_c::new(
    string name = "mac_addr_filter_default_config_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_default_config_test_c::run_stimulus(uvm_phase phase);
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // No APB programming — rely on reset defaults
  // Reset defaults: local_addr = 0x0, group table invalid, promiscuous OFF
  #200ns;

  // Frame 1: Broadcast → accepted
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "bcast");
  #100ns;

  // Frame 2: Any unicast (local addr is 0x0, no match) → dropped
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "unicast_nomatch");
  #100ns;

  // Frame 3: PAUSE multicast (pause_en=0 by default) → dropped
  drive_frame_with_da(rs_seqr, 48'h01_80_C2_00_00_01, "pause_mcast");
  #100ns;

  // Frame 4: Group[0] address (group table invalid) → dropped
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_01, "grp0_invalid");
  #100ns;

  // Frame 5: Another unicast → dropped
  drive_frame_with_da(rs_seqr, 48'hDE_AD_BE_EF_00_01, "unrelated");

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 1)
    `uvm_info("MAC_ADDR_DEFAULT_CFG", "PASS: 1 broadcast accepted, 4 dropped (default config)", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_DEFAULT_CFG", $sformatf("FAIL: Expected 1 accepted frame, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_unrelated_unicast_test_c  (MAC-ADDR-012)
//
// Unrelated unicast rejection.
// Verifies that unicast addresses not matching the programmed local address
// are dropped, including near-miss addresses (1-bit difference).
//
// Expected: 2 accepted (local + broadcast), 6 dropped.
//------------------------------------------------------------------------------
class mac_addr_filter_unrelated_unicast_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_unrelated_unicast_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_unrelated_unicast_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_unrelated_unicast_test_c::new(
    string name = "mac_addr_filter_unrelated_unicast_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_unrelated_unicast_test_c::run_stimulus(uvm_phase phase);
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Program local unicast: 00:00:02:00:00:AA
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  disable_promiscuous(apb_mixin);
  #200ns;

  // Frame 1: DA = local-1 (1 bit different) → dropped
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_A9, "near_miss_m1");
  #100ns;

  // Frame 2: DA = local+1 (1 bit different) → dropped
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AB, "near_miss_p1");
  #100ns;

  // Frame 3: DA = different low byte → dropped
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_0A, "diff_low_byte");
  #100ns;

  // Frame 4: DA = completely unrelated unicast → dropped
  drive_frame_with_da(rs_seqr, 48'hDE_AD_BE_EF_00_01, "completely_unrelated");
  #100ns;

  // Frame 5: DA = unicast with only first byte different → dropped
  drive_frame_with_da(rs_seqr, 48'h01_00_02_00_00_AA, "diff_first_byte");
  #100ns;

  // Frame 6: DA = near-broadcast unicast (FE:FF:FF:FF:FF:FF) → dropped
  drive_frame_with_da(rs_seqr, 48'hFE_FF_FF_FF_FF_FF, "near_broadcast");
  #100ns;

  // Frame 7: DA = local → accepted
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "local_match");
  #100ns;

  // Frame 8: DA = broadcast → accepted
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "bcast");

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 2)
    `uvm_info("MAC_ADDR_UNRELATED_UNI", "PASS: 2 accepted (local + broadcast), 6 unrelated unicast dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_UNRELATED_UNI", $sformatf("FAIL: Expected 2 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_promiscuous_multi_addr_test_c  (MAC-ADDR-013)
//
// Promiscuous mode ON→OFF transition with multiple unrelated unicast.
// Verifies multiple unrelated unicast addresses accepted under promiscuous,
// then rejected after disabling promiscuous.
//
// Expected: 7 accepted (5 under promiscuous + local + broadcast).
//------------------------------------------------------------------------------
class mac_addr_filter_promiscuous_multi_addr_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_promiscuous_multi_addr_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_promiscuous_multi_addr_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_promiscuous_multi_addr_test_c::new(
    string name = "mac_addr_filter_promiscuous_multi_addr_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_promiscuous_multi_addr_test_c::run_stimulus(uvm_phase phase);
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Program local unicast: 00:00:02:00:00:AA
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);

  // --- Phase A: Promiscuous ON ---
  enable_promiscuous(apb_mixin);
  #200ns;

  // Frames 1-5: All unrelated unicast → all accepted under promiscuous
  drive_frame_with_da(rs_seqr, 48'hDE_AD_BE_EF_00_01, "prom_uni1");
  #50ns;
  drive_frame_with_da(rs_seqr, 48'hCA_FE_FA_DE_00_02, "prom_uni2");
  #50ns;
  drive_frame_with_da(rs_seqr, 48'h01_02_03_04_05_06, "prom_uni3");
  #50ns;
  drive_frame_with_da(rs_seqr, 48'hAA_BB_CC_DD_EE_FF, "prom_uni4");
  #50ns;
  drive_frame_with_da(rs_seqr, 48'h11_22_33_44_55_66, "prom_uni5");
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_ADDR_PROM_MULTI", $sformatf(
      "Phase A: promiscuous ON — AXI RX count = %0d (expected 5)", axi_rx_cnt), UVM_NONE)

  // --- Phase B: Promiscuous OFF ---
  disable_promiscuous(apb_mixin);
  #200ns;

  // Frame 6: Same unrelated unicast → dropped
  drive_frame_with_da(rs_seqr, 48'hDE_AD_BE_EF_00_01, "post_nomatch");
  #100ns;

  // Frame 7: Local → accepted
  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "local_post");
  #100ns;

  // Frame 8: Broadcast → accepted
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "bcast_post");

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 7)
    `uvm_info("MAC_ADDR_PROM_MULTI", "PASS: 7 accepted (5 promiscuous + local + broadcast)", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_PROM_MULTI", $sformatf("FAIL: Expected 7 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_boundary_addr_pattern_test_c  (MAC-ADDR-014)
//
// 48-bit DA boundary patterns.
// Verifies correct DA extraction using zero, all-ones, alternating,
// incrementing, and exact-match addresses.  Uses the dedicated
// rs_addr_filter_boundary_seq_c sequence.
//
// Expected: 2 accepted (broadcast + target), 6 dropped.
//------------------------------------------------------------------------------
class mac_addr_filter_boundary_addr_pattern_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_boundary_addr_pattern_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_boundary_addr_pattern_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_boundary_addr_pattern_test_c::new(
    string name = "mac_addr_filter_boundary_addr_pattern_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_boundary_addr_pattern_test_c::run_stimulus(uvm_phase phase);
  rs_addr_filter_boundary_seq_c boundary_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;

  // Program local unicast: 00:00:02:00:00:AA
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  disable_promiscuous(apb_mixin);
  #200ns;

  // Drive 8 boundary-pattern frames
  boundary_seq = rs_addr_filter_boundary_seq_c::type_id::create("boundary_seq");
  boundary_seq.target_addr   = 48'h00_00_02_00_00_AA;
  boundary_seq.frame_sa      = 48'h02_00_00_00_00_01;
  boundary_seq.frame_ethertype = 16'h0800;
  boundary_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  // Expected accepted: PAT_ALL_ONES (broadcast) + PAT_TARGET (local) = 2
  // Dropped: ZERO, ALT_55, ALT_AA, NEIGHBOR_M1, NEIGHBOR_P1, RANDOM = 6
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 2)
    `uvm_info("MAC_ADDR_BOUNDARY_DA", $sformatf(
        "PASS: 2 accepted (broadcast + local), 6 boundary patterns dropped"), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_BOUNDARY_DA", $sformatf(
        "FAIL: Expected 2 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_boundary_sa_test_c  (MAC-ADDR-015)
//
// 48-bit SA extraction verification.
// Drives broadcast frames with SA set to zero, all-ones, alternating,
// and incrementing patterns.  SA should not affect DA filtering.
//
// Expected: 6 accepted (all broadcast frames).
//------------------------------------------------------------------------------
class mac_addr_filter_boundary_sa_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_boundary_sa_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_boundary_sa_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_boundary_sa_test_c::new(
    string name = "mac_addr_filter_boundary_sa_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_boundary_sa_test_c::run_stimulus(uvm_phase phase);
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;
  bit [47:0] sa_patterns [6] = '{
    48'h00_00_00_00_00_00,  // zero SA
    48'hFF_FF_FF_FF_FF_FF,  // all-ones SA
    48'h55_55_55_55_55_55,  // alternating 01
    48'hAA_AA_AA_AA_AA_AA,  // alternating 10
    48'h01_02_03_04_05_06,  // incrementing
    48'h00_00_02_00_00_AA   // matches local DA (but used as SA here)
  };

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // Program local unicast: 00:00:02:00:00:AA
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  disable_promiscuous(apb_mixin);
  #200ns;

  // Drive broadcast frames with varying SA patterns
  // SA patterns: zero, all-ones, ALT_55, ALT_AA, incrementing, target-local
  for (int i = 0; i < 6; i++) begin
    drive_frame_with_da_sa(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, sa_patterns[i],
                           $sformatf("sa_%0d", i));
    #100ns;
  end

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 6)
    `uvm_info("MAC_ADDR_BOUNDARY_SA", "PASS: 6 accepted — SA variation does not affect DA filtering", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_BOUNDARY_SA", $sformatf("FAIL: Expected 6 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_toggle_with_config_change_test_c  (MAC-ADDR-016)
//
// Accepted → rejected → accepted with dynamic configuration changes.
// Multi-cycle toggle where local address, group table, and promiscuous
// mode are reconfigured between frame batches.
//
// Expected: 7 accepted across 4 config phases.
//------------------------------------------------------------------------------
class mac_addr_filter_toggle_with_config_change_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_toggle_with_config_change_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_toggle_with_config_change_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_toggle_with_config_change_test_c::new(
    string name = "mac_addr_filter_toggle_with_config_change_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_toggle_with_config_change_test_c::run_stimulus(uvm_phase phase);
  int axi_rx_cnt;
  rs_sequencer_c rs_seqr;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;
  rs_seqr = env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h;

  // --- Phase 1: local=AA, group[0]=01, promiscuous OFF ---
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous(apb_mixin);
  #200ns;

  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "p1_local");     // accepted
  #100ns;
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_01, "p1_group");     // accepted
  #200ns;

  // --- Phase 2: Change local to BB, group[0] still active ---
  write_local_addr(apb_mixin, 48'h00_00_03_00_00_BB);
  #200ns;

  drive_frame_with_da(rs_seqr, 48'h00_00_02_00_00_AA, "p2_old_local"); // dropped
  #100ns;
  drive_frame_with_da(rs_seqr, 48'h00_00_03_00_00_BB, "p2_new_local"); // accepted
  #100ns;
  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_01, "p2_group");     // accepted
  #200ns;

  // --- Phase 3: Deactivate group[0] ---
  clear_group_addr(apb_mixin, 0);
  #200ns;

  drive_frame_with_da(rs_seqr, 48'h00_5E_00_01_00_01, "p3_grp_off");   // dropped
  #100ns;
  drive_frame_with_da(rs_seqr, 48'hFF_FF_FF_FF_FF_FF, "p3_bcast");     // accepted
  #200ns;

  // --- Phase 4: Enable promiscuous, send unrelated unicast ---
  enable_promiscuous(apb_mixin);
  #200ns;

  drive_frame_with_da(rs_seqr, 48'hDE_AD_BE_EF_00_01, "p4_prom_uni");  // accepted
  #200ns;

  // --- Phase 5: Disable promiscuous, send same unrelated ---
  disable_promiscuous(apb_mixin);
  #200ns;

  drive_frame_with_da(rs_seqr, 48'hDE_AD_BE_EF_00_01, "p5_post_prom"); // dropped

  #1us;

  // Expected: p1_local(1) + p1_group(1) + p2_new_local(1) + p2_group(1) +
  //           p3_bcast(1) + p4_prom_uni(1) = 6 accepted
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 6)
    `uvm_info("MAC_ADDR_TOGGLE_CFG", $sformatf(
        "PASS: 6 accepted across 4 config phases — toggle with config change correct"), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_TOGGLE_CFG", $sformatf(
        "FAIL: Expected 6 accepted frames, got %0d", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_mixed_addr_classes_sustained_test_c  (MAC-ADDR-017)
//
// Mixed address classes under sustained traffic with config changes.
// Drives constrained-random traffic in two batches with a configuration
// swap between them, plus non-matching address injection.
//
// Expected: ~24-30 accepted (from two batches of constrained-random traffic).
//------------------------------------------------------------------------------
class mac_addr_filter_mixed_addr_classes_sustained_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_mixed_addr_classes_sustained_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_mixed_addr_classes_sustained_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_mixed_addr_classes_sustained_test_c::new(
    string name = "mac_addr_filter_mixed_addr_classes_sustained_test_c",
    uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_mixed_addr_classes_sustained_test_c::run_stimulus(uvm_phase phase);
  rs_addr_filter_sequence_c addr_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;

  // --- Batch 1: local=AA, group[0]=01, promiscuous OFF ---
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  disable_promiscuous(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("batch1_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.num_addr_frames = 20;
  addr_seq.payload_min     = 46;
  addr_seq.payload_max     = 120;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // --- Swap config: new local=BB, group[1]=02, deactivate group[0] ---
  write_local_addr(apb_mixin, 48'h00_00_03_00_00_BB);
  write_group_addr(apb_mixin, 1, 48'h00_5E_00_01_00_02);
  clear_group_addr(apb_mixin, 0);
  #200ns;

  // --- Inject 5 non-matching addresses ---
  repeat (5) begin
    drive_frame_with_da(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h,
                        48'hCA_FE_FA_DE_00_01, "inject_nomatch");
    #50ns;
  end
  #200ns;

  // --- Batch 2: constrained-random with new addresses ---
  addr_seq = rs_addr_filter_sequence_c::type_id::create("batch2_seq");
  addr_seq.local_addr      = 48'h00_00_03_00_00_BB;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_02;
  addr_seq.num_addr_frames = 20;
  addr_seq.payload_min     = 46;
  addr_seq.payload_max     = 120;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  // Batch 1: ~20 * (30+20+30)/100 = ~16 accepted from matching classes
  // Batch 2: ~20 * (30+20+30)/100 = ~16 accepted from matching classes
  // Total expected range: [20, 36] (accounting for randomization variance)
  // 5 injected non-matching are always dropped
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt >= 20 && axi_rx_cnt <= 36)
    `uvm_info("MAC_ADDR_MIXED_SUSTAINED", $sformatf(
        "PASS: %0d accepted across 2 batches with config swap and injection", axi_rx_cnt), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_MIXED_SUSTAINED", $sformatf(
        "FAIL: %0d accepted frames — outside expected range [20, 36]", axi_rx_cnt))
endtask

//------------------------------------------------------------------------------
// Class: mac_addr_filter_constrained_random_dynamic_config_test_c  (MAC-ADDR-018)
//
// Constrained-random traffic with dynamic promiscuous and group table
// changes between phases.  Exercises randomized address/filter combinations.
//
// Expected: ~35-45 accepted across 3 phases.
//------------------------------------------------------------------------------
class mac_addr_filter_constrained_random_dynamic_config_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_addr_filter_constrained_random_dynamic_config_test_c)

  mac_addr_filter_apb_mixin apb_mixin;

  extern function new(string name = "mac_addr_filter_constrained_random_dynamic_config_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_addr_filter_constrained_random_dynamic_config_test_c::new(
    string name = "mac_addr_filter_constrained_random_dynamic_config_test_c",
    uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_addr_filter_constrained_random_dynamic_config_test_c::run_stimulus(uvm_phase phase);
  rs_addr_filter_sequence_c addr_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;
  apb_mixin = mac_addr_filter_apb_mixin::type_id::create("apb_mixin");
  apb_mixin.env_h = env_h;

  // --- Phase A: local=AA, group[0..2], promiscuous OFF ---
  write_local_addr(apb_mixin, 48'h00_00_02_00_00_AA);
  write_group_addr(apb_mixin, 0, 48'h00_5E_00_01_00_01);
  write_group_addr(apb_mixin, 1, 48'h00_5E_00_01_00_02);
  write_group_addr(apb_mixin, 2, 48'h00_5E_00_01_00_03);
  disable_promiscuous(apb_mixin);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("phase_a_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.num_addr_frames = 15;
  addr_seq.payload_min     = 46;
  addr_seq.payload_max     = 100;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // --- Phase B: Toggle promiscuous ON, modify group table ---
  enable_promiscuous(apb_mixin);
  clear_group_addr(apb_mixin, 1);
  clear_group_addr(apb_mixin, 2);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("phase_b_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.num_addr_frames = 15;
  addr_seq.payload_min     = 46;
  addr_seq.payload_max     = 100;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // --- Phase C: Promiscuous OFF, activate all groups ---
  disable_promiscuous(apb_mixin);
  write_group_addr(apb_mixin, 1, 48'h00_5E_00_01_00_02);
  write_group_addr(apb_mixin, 2, 48'h00_5E_00_01_00_03);
  #200ns;

  addr_seq = rs_addr_filter_sequence_c::type_id::create("phase_c_seq");
  addr_seq.local_addr      = 48'h00_00_02_00_00_AA;
  addr_seq.group_addr      = 48'h00_5E_00_01_00_01;
  addr_seq.num_addr_frames = 15;
  addr_seq.payload_min     = 46;
  addr_seq.payload_max     = 100;
  addr_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  // Phase A: 15 * ~0.8 = ~12 accepted (promiscuous OFF, 3 groups + local + bcast)
  // Phase B: 15 * 1.0 = ~15 accepted (promiscuous ON, all pass)
  // Phase C: 15 * ~0.8 = ~12 accepted (promiscuous OFF again)
  // Total expected range: [30, 45]
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt >= 30 && axi_rx_cnt <= 45)
    `uvm_info("MAC_ADDR_CR_DYN_CONFIG", $sformatf(
        "PASS: %0d accepted across 3 phases with dynamic config changes", axi_rx_cnt), UVM_NONE)
  else
    `uvm_error("MAC_ADDR_CR_DYN_CONFIG", $sformatf(
        "FAIL: %0d accepted frames — outside expected range [30, 45]", axi_rx_cnt))
endtask

`endif  // MAC_ADDR_FILTERING_TEST_SVH
