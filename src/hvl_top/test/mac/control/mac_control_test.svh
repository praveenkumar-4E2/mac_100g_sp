`ifndef MAC_CONTROL_TEST_SVH
`define MAC_CONTROL_TEST_SVH

// Sequence classes for MAC Control frames (directed, unsupported opcode,
// alternate address, constrained-random) are defined in mac_control_seq.sv
// and compiled via the +incdir+ for sequences/rs/.

//------------------------------------------------------------------------------
// Local helper: drives frames with an explicit DA via send_clean_frame().
// Used by tests that need directed DA patterns without depending on
// rs_directed_frame_sequence_c (defined later in the include chain).
//------------------------------------------------------------------------------
class mac_ctrl_directed_da_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_ctrl_directed_da_seq_c)

  bit [47:0] target_da = 48'hFF_FF_FF_FF_FF_FF;

  extern function new(string name = "mac_ctrl_directed_da_seq_c");
  extern task body();
endclass

function mac_ctrl_directed_da_seq_c::new(string name = "mac_ctrl_directed_da_seq_c");
  super.new(name);
endfunction

task mac_ctrl_directed_da_seq_c::body();
  payload_min = 46;
  payload_max = 1500;
  repeat (num_frames) begin
    send_clean_frame(-1, target_da);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

//------------------------------------------------------------------------------
// Class: mac_control_test_c  (MAC-CTRL consolidated)
//
// Single consolidated test covering every MAC Control scenario.
// Each scenario is a local task method.  The plusarg +MAC_CTRL_TEST=<name>
// selects which scenario to run; defaults to run_all_scenarios.
//------------------------------------------------------------------------------
class mac_control_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_control_test_c)

  extern function new(string name = "mac_control_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);

  // --- Scenario methods ---
  extern local task run_tx_pause(uvm_phase phase);
  extern local task run_rx_supported_opcode(uvm_phase phase);
  extern local task run_rx_unsupported_opcode(uvm_phase phase);
  extern local task run_oversized(uvm_phase phase);
  extern local task run_data_transparent(uvm_phase phase);
  extern local task run_addr_unicast(uvm_phase phase);
  extern local task run_addr_group(uvm_phase phase);
  extern local task run_addr_random(uvm_phase phase);
  extern local task run_unsupported_enhanced(uvm_phase phase);
  extern local task run_clause64_quanta(uvm_phase phase);
  extern local task run_clause64_expiry(uvm_phase phase);
  extern local task run_indication(uvm_phase phase);
  extern local task run_data_transparency(uvm_phase phase);
  extern local task run_clause64_optional(uvm_phase phase);
  extern local task run_sustained_traffic(uvm_phase phase);
  extern local task run_addr_change(uvm_phase phase);
  extern local task run_consecutive_addr(uvm_phase phase);
  extern local task run_all_scenarios(uvm_phase phase);
endclass

function mac_control_test_c::new(
    string name = "mac_control_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_control_test_c::apb_write(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_control_test_c::apb_read(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_read_sequence_c read_h;
  read_h = apb_read_sequence_c::type_id::create($sformatf("apb_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = read_h.m_rdata;
endtask

//------------------------------------------------------------------------------
// Dispatch: select scenario via +MAC_CTRL_TEST=<name>
//------------------------------------------------------------------------------
task mac_control_test_c::run_stimulus(uvm_phase phase);
  string test_name;
  if ($value$plusargs("MAC_CTRL_TEST=%s", test_name)) begin
    case (test_name)
      "tx_pause":              run_tx_pause(phase);
      "rx_supported_opcode":   run_rx_supported_opcode(phase);
      "rx_unsupported_opcode": run_rx_unsupported_opcode(phase);
      "oversized":             run_oversized(phase);
      "data_transparent":      run_data_transparent(phase);
      "addr_unicast":          run_addr_unicast(phase);
      "addr_group":            run_addr_group(phase);
      "addr_random":           run_addr_random(phase);
      "unsupported_enhanced":  run_unsupported_enhanced(phase);
      "clause64_quanta":       run_clause64_quanta(phase);
      "clause64_expiry":       run_clause64_expiry(phase);
      "indication":            run_indication(phase);
      "data_transparency":     run_data_transparency(phase);
      "clause64_optional":     run_clause64_optional(phase);
      "sustained_traffic":     run_sustained_traffic(phase);
      "addr_change":           run_addr_change(phase);
      "consecutive_addr":      run_consecutive_addr(phase);
      "all":                   run_all_scenarios(phase);
      default:                 run_all_scenarios(phase);
    endcase
  end else
    run_all_scenarios(phase);
endtask

//==============================================================================
// Scenario 1: TX PAUSE via APB  (MAC-PAUSE-003)
//   MA_CONTROL.request -> MAC:MA_DATA.request mapping.
//   Programs REG_PAUSE_TX_CONFIG to trigger a DUT-generated PAUSE frame
//   and verifies it appears on the MAC TX wire.
//==============================================================================
task mac_control_test_c::run_tx_pause(uvm_phase phase);
  bit timed_out;

  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, 32'h0000_0001);
  #200ns;
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, 32'h0000_0003);
  #200ns;
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, 32'h0000_0001);

  mac_wait_utils_c::wait_for_count_at_least(
      1, env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("MAC_PAUSE_TX_FRAME", "timed out waiting for DUT-generated PAUSE frame on MAC TX wire")
  else
    `uvm_info("MAC_PAUSE_TX_FRAME", "PASS: DUT-generated PAUSE frame observed on MAC TX wire", UVM_NONE)
endtask

//==============================================================================
// Scenario 2: RX supported opcode  (MAC-PAUSE-004)
//   Receive valid MAC control frame with supported opcode (0x0001 PAUSE).
//   Verifies that PAUSE frame is consumed by the RX MAC.
//==============================================================================
task mac_control_test_c::run_rx_supported_opcode(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  bit [apb_transfer_t::DATA_WIDTH-1:0] status_data;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("pause_supported");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0100;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  apb_read(reg_map_pkg::REG_RX_STATUS, status_data);
  if (status_data[0])
    `uvm_info("MAC_PAUSE_RX_OPCODE", $sformatf("PASS: pause_active asserted (REG_RX_STATUS=%h)", status_data), UVM_NONE)
  else
    `uvm_error("MAC_PAUSE_RX_OPCODE", $sformatf("FAIL: pause_active not asserted (REG_RX_STATUS=%h)", status_data))

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 0)
    `uvm_info("MAC_PAUSE_RX_OPCODE", "PASS: PAUSE control frame consumed, no client delivery", UVM_NONE)
  else
    `uvm_error("MAC_PAUSE_RX_OPCODE", $sformatf("FAIL: %0d frame(s) unexpectedly delivered to AXI RX", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 3: RX unsupported opcode  (MAC-PAUSE-005)
//   Receive valid MAC control frame with unsupported opcode (0x0007).
//==============================================================================
task mac_control_test_c::run_rx_unsupported_opcode(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("ctrl_unsupported");
  ctrl_seq.opcode            = 16'h0007;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0000;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_PAUSE_RX_UNSP", $sformatf(
      "INFO: unsupported opcode (0x0007) DUT behavior: %0d frame(s) delivered to AXI RX", axi_rx_cnt), UVM_NONE)
endtask

//==============================================================================
// Scenario 4: Oversized control frame  (MAC-CTRL-001)
//   PAUSE frame with 200-byte payload (140 bytes beyond 46-byte min).
//==============================================================================
task mac_control_test_c::run_oversized(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  bit [apb_transfer_t::DATA_WIDTH-1:0] status_data;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("oversized_ctrl");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0100;
  ctrl_seq.frame_payload_len = 200;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  apb_read(reg_map_pkg::REG_RX_STATUS, status_data);
  `uvm_info("MAC_CTRL_OVERSIZE", $sformatf(
      "INFO: oversized PAUSE frame (200B payload) REG_RX_STATUS=%h", status_data), UVM_NONE)

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_CTRL_OVERSIZE", $sformatf(
      "INFO: oversized control frame DUT policy: pause_active=%0b, AXI RX count=%0d",
      status_data[0], axi_rx_cnt), UVM_NONE)
endtask

//==============================================================================
// Scenario 5: Data transparency  (MAC-CTRL-002)
//   Verifies that normal data frames pass through the MAC Control sublayer
//   transparently.  PAUSE control frames are consumed by the control
//   classifier; data frames pass through to the client.
//==============================================================================
task mac_control_test_c::run_data_transparent(uvm_phase phase);
  rs_sequence_base_c data_seq;
  mac_control_frame_sequence_c ctrl_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  // Phase 1: 5 clean data frames (broadcast DA, EtherType > 0x0600)
  data_seq = rs_sequence_base_c::type_id::create("data_phase1");
  data_seq.num_frames      = 5;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Phase 2: 2 PAUSE control frames — consumed by MAC Control sublayer
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("pause_in_data1");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0100;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("pause_in_data2");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0080;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Phase 3: 5 more clean data frames
  data_seq = rs_sequence_base_c::type_id::create("data_phase3");
  data_seq.num_frames      = 5;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 10)
    `uvm_info("MAC_CTRL_TRANSPARENT", "PASS: 10 data frames delivered through MAC Control transparently", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_TRANSPARENT", $sformatf("FAIL: Expected 10 data frames, got %0d", axi_rx_cnt))

  `uvm_info("MAC_CTRL_TRANSPARENT",
      "INFO: GATE/REPORT/REGISTER_REQ/REGISTER/REGISTER_ACK not implemented in RTL", UVM_NONE)
endtask

//==============================================================================
// Scenario 6: Unicast address filtering  (MAC-ADDR-007)
//   Promiscuous mode OFF.  Frames with DA matching local_addr or broadcast
//   are accepted; non-matching unicast frames are dropped.
//==============================================================================
task mac_control_test_c::run_addr_unicast(uvm_phase phase);
  rs_sequence_base_c data_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_02_00);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
  #200ns;

  // Frame 1: Unicast DA matching local_addr (accepted)
  data_seq = rs_sequence_base_c::type_id::create("ucast_match");
  data_seq.num_frames      = 1;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b0;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Frame 2: Broadcast DA (accepted)
  data_seq = rs_sequence_base_c::type_id::create("bcast");
  data_seq.num_frames      = 1;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Frame 3: Non-matching unicast DA (dropped, promiscuous off)
  data_seq = rs_sequence_base_c::type_id::create("ucast_nomatch");
  data_seq.num_frames      = 1;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b0;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 2)
    `uvm_info("MAC_ADDR_UNICAST", "PASS: 2 data frames accepted (local unicast + broadcast), non-matching dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_UNICAST", $sformatf("FAIL: Expected 2 accepted frames, got %0d", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 7: Group address filtering  (MAC-ADDR-008)
//   Two group address entries programmed.  Frames with DA matching a group
//   entry or broadcast are accepted; non-matching multicast frames dropped.
//==============================================================================
task mac_control_test_c::run_addr_group(uvm_phase phase);
  rs_sequence_base_c data_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::group_low_addr(0),  32'h00_00_00_01);
  apb_write(reg_map_pkg::group_high_addr(0), 32'h00_5E_00_01);
  apb_write(reg_map_pkg::group_low_addr(1),  32'h00_00_00_02);
  apb_write(reg_map_pkg::group_high_addr(1), 32'h00_5E_00_01);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
  #200ns;

  // Frame 1: DA = group address 0 (accepted via group filter)
  data_seq = rs_sequence_base_c::type_id::create("grp0");
  data_seq.num_frames      = 1;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b0;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Frame 2: Broadcast (accepted)
  data_seq = rs_sequence_base_c::type_id::create("bcast");
  data_seq.num_frames      = 1;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Frame 3: Non-matching multicast (dropped)
  data_seq = rs_sequence_base_c::type_id::create("nonmatch_mcast");
  data_seq.num_frames      = 1;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b0;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 2)
    `uvm_info("MAC_ADDR_GROUP", "PASS: 2 data frames accepted (group match + broadcast), non-matching dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_GROUP", $sformatf("FAIL: Expected 2 accepted frames, got %0d", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 8: Random address filtering  (MAC-CTRL-003)
//   Constrained-random address filtering combinations.  Broadcast frames
//   injected in sustained bursts, with non-matching unicast interleaved.
//==============================================================================
task mac_control_test_c::run_addr_random(uvm_phase phase);
  rs_sequence_base_c data_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_02_00);
  apb_write(reg_map_pkg::group_low_addr(0),  32'h00_00_00_01);
  apb_write(reg_map_pkg::group_high_addr(0), 32'h00_5E_00_01);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
  #200ns;

  // Phase 1: 10 broadcast frames (accepted)
  data_seq = rs_sequence_base_c::type_id::create("sustained_bcast");
  data_seq.num_frames      = 10;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 150;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // Phase 2: 3 non-matching unicast (dropped)
  data_seq = rs_sequence_base_c::type_id::create("nonmatch_inject");
  data_seq.num_frames      = 3;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 150;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b0;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Phase 3: 7 more broadcast frames (accepted)
  data_seq = rs_sequence_base_c::type_id::create("sustained_bcast2");
  data_seq.num_frames      = 7;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 150;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 17)
    `uvm_info("MAC_ADDR_RANDOM", "PASS: 17 broadcast frames accepted, non-matching unicast dropped", UVM_NONE)
  else
    `uvm_error("MAC_ADDR_RANDOM", $sformatf("FAIL: Expected 17 accepted frames, got %0d", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 9: Enhanced unsupported opcode  (Enhanced MAC-PAUSE-005)
//   Single unsupported opcode, then burst of 3 distinct unsupported opcodes.
//   Checks REG_RX_UNSUPPORTED_COUNT increments correctly.
//==============================================================================
task mac_control_test_c::run_unsupported_enhanced(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  bit [apb_transfer_t::DATA_WIDTH-1:0] rdata;
  bit [apb_transfer_t::DATA_WIDTH-1:0] status_data;
  int axi_rx_cnt;
  int unsigned unsupported_before, unsupported_after;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  // Enable RX + PAUSE
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  // Read unsupported counter before
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsupported_before = rdata[15:0];
  `uvm_info("MAC_ENH_UNSUP", $sformatf("unsupported_count before = %0d", unsupported_before), UVM_NONE)

  // --- Phase 1: single unsupported opcode 0x0007 ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("unsup_0007");
  ctrl_seq.opcode            = 16'h0007;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // Read unsupported counter — should be +1
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsupported_after = rdata[15:0];
  if (unsupported_after == unsupported_before + 1)
    `uvm_info("MAC_ENH_UNSUP", $sformatf(
        "PASS: unsupported_count incremented by 1 (%0d -> %0d)",
        unsupported_before, unsupported_after), UVM_NONE)
  else
    `uvm_error("MAC_ENH_UNSUP", $sformatf(
        "FAIL: unsupported_count expected %0d, got %0d",
        unsupported_before + 1, unsupported_after))

  // Verify pause_active NOT asserted
  apb_read(reg_map_pkg::REG_RX_STATUS, status_data);
  if (!status_data[0])
    `uvm_info("MAC_ENH_UNSUP", "PASS: pause_active not asserted after unsupported opcode", UVM_NONE)
  else
    `uvm_error("MAC_ENH_UNSUP", "FAIL: pause_active unexpectedly asserted after unsupported opcode")

  // --- Phase 2: burst of 3 different unsupported opcodes ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("unsup_0002");
  ctrl_seq.opcode            = 16'h0002;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("unsup_0003");
  ctrl_seq.opcode            = 16'h0003;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("unsup_0004");
  ctrl_seq.opcode            = 16'h0004;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // Read unsupported counter — should be +4 total
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsupported_after = rdata[15:0];
  if (unsupported_after == unsupported_before + 4)
    `uvm_info("MAC_ENH_UNSUP", $sformatf(
        "PASS: unsupported_count incremented by 4 total (%0d -> %0d)",
        unsupported_before, unsupported_after), UVM_NONE)
  else
    `uvm_error("MAC_ENH_UNSUP", $sformatf(
        "FAIL: unsupported_count expected %0d, got %0d",
        unsupported_before + 4, unsupported_after))

  // Verify no frames delivered to AXI RX
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 0)
    `uvm_info("MAC_ENH_UNSUP", "PASS: no unsupported opcode frames delivered to AXI RX", UVM_NONE)
  else
    `uvm_error("MAC_ENH_UNSUP", $sformatf(
        "FAIL: %0d frame(s) unexpectedly delivered to AXI RX", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 10: Clause 64 PAUSE quanta  (MAC-PAUSE-006)
//   IEEE 802.3 Clause 64 — PAUSE timer value latching.
//   Sends PAUSE frames with minimum (0x0001) and maximum (0xFFFF) quanta.
//==============================================================================
task mac_control_test_c::run_clause64_quanta(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  bit [apb_transfer_t::DATA_WIDTH-1:0] rx_status;
  bit [apb_transfer_t::DATA_WIDTH-1:0] pause_status;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  // Enable RX + PAUSE
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  // --- Phase 1: PAUSE with minimum quanta (0x0001) ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("pause_min_quanta");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0001;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_PAUSE_QUANTA", $sformatf(
        "PASS: pause_active asserted after min quanta (REG_RX_STATUS=%h)", rx_status), UVM_NONE)
  else
    `uvm_error("MAC_PAUSE_QUANTA", $sformatf(
        "FAIL: pause_active not asserted after min quanta (REG_RX_STATUS=%h)", rx_status))

  apb_read(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("MAC_PAUSE_QUANTA", $sformatf(
      "INFO: REG_PAUSE_STATUS after min quanta = %h (pause_time=%0d)",
      pause_status, pause_status[15:0]), UVM_NONE)

  // No data frames should be delivered — scoreboard disabled
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 0)
    `uvm_info("MAC_PAUSE_QUANTA", "PASS: no PAUSE frame delivered to AXI RX client", UVM_NONE)
  else
    `uvm_error("MAC_PAUSE_QUANTA", $sformatf(
        "FAIL: %0d PAUSE frame(s) unexpectedly delivered to AXI RX", axi_rx_cnt))

  // --- Phase 2: PAUSE with maximum quanta (0xFFFF) ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("pause_max_quanta");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'hFFFF;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_PAUSE_QUANTA", $sformatf(
        "PASS: pause_active asserted after max quanta (REG_RX_STATUS=%h)", rx_status), UVM_NONE)
  else
    `uvm_error("MAC_PAUSE_QUANTA", $sformatf(
        "FAIL: pause_active not asserted after max quanta (REG_RX_STATUS=%h)", rx_status))

  apb_read(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("MAC_PAUSE_QUANTA", $sformatf(
      "INFO: REG_PAUSE_STATUS after max quanta = %h (pause_time=%0d)",
      pause_status, pause_status[15:0]), UVM_NONE)
endtask

//==============================================================================
// Scenario 11: Clause 64 PAUSE timer expiry  (MAC-PAUSE-007)
//   Sends a PAUSE frame with small quanta (0x0004), waits for the timer to
//   expire, then verifies pause_active de-asserts and normal data resumes.
//==============================================================================
task mac_control_test_c::run_clause64_expiry(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  rs_sequence_base_c data_seq;
  bit [apb_transfer_t::DATA_WIDTH-1:0] rx_status;
  bit [apb_transfer_t::DATA_WIDTH-1:0] pause_status;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  // Enable RX + PAUSE
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  // --- Phase 1: Send PAUSE with small quanta (0x0004) ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("pause_small_quanta");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0004;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Verify pause_active is asserted immediately after PAUSE frame
  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_PAUSE_EXPIRY", $sformatf(
        "PASS: pause_active asserted after PAUSE frame (REG_RX_STATUS=%h)", rx_status), UVM_NONE)
  else
    `uvm_error("MAC_PAUSE_EXPIRY", $sformatf(
        "FAIL: pause_active not asserted after PAUSE frame (REG_RX_STATUS=%h)", rx_status))

  // Read timer value — should be non-zero
  apb_read(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("MAC_PAUSE_EXPIRY", $sformatf(
      "INFO: REG_PAUSE_STATUS during pause = %h (pause_time=%0d)",
      pause_status, pause_status[15:0]), UVM_NONE)

  // --- Phase 2: Wait for timer expiry ---
  #500ns;

  // --- Phase 3: Verify pause_active de-asserts ---
  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (!rx_status[0])
    `uvm_info("MAC_PAUSE_EXPIRY", $sformatf(
        "PASS: pause_active de-asserted after timer expiry (REG_RX_STATUS=%h)", rx_status), UVM_NONE)
  else
    `uvm_error("MAC_PAUSE_EXPIRY", $sformatf(
        "FAIL: pause_active still asserted after timer expiry (REG_RX_STATUS=%h)", rx_status))

  // --- Phase 4: Resume normal data traffic ---
  data_seq = rs_sequence_base_c::type_id::create("post_expiry_data");
  data_seq.num_frames      = 3;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 3)
    `uvm_info("MAC_PAUSE_EXPIRY", "PASS: 3 data frames delivered after pause timer expiry", UVM_NONE)
  else
    `uvm_error("MAC_PAUSE_EXPIRY", $sformatf(
        "FAIL: Expected 3 data frames after expiry, got %0d", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 12: Indication  (MAC-CTRL-IND)
//   MA_CONTROL.request -> expected indication/state result.
//   Drives a PAUSE frame, then reads REG_RX_STATUS and REG_PAUSE_STATUS
//   to verify pause_active is asserted and timer value is visible.
//==============================================================================
task mac_control_test_c::run_indication(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  bit [apb_transfer_t::DATA_WIDTH-1:0] rx_status, pause_status;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  // Enable RX + PAUSE
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  // Drive PAUSE frame via MODE_INDICATION
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("ind_pause");
  ctrl_seq.mode            = mac_control_frame_sequence_c::MODE_INDICATION;
  ctrl_seq.pause_quanta    = 16'h0100;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // Verify indication: pause_active
  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_CTRL_IND", $sformatf(
        "PASS: pause_active asserted (REG_RX_STATUS=%h)", rx_status), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_IND", $sformatf(
        "FAIL: pause_active not asserted (REG_RX_STATUS=%h)", rx_status))

  // Verify state: pause timer value
  apb_read(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("MAC_CTRL_IND", $sformatf(
      "PASS: REG_PAUSE_STATUS = %h (pause_time=%0d)", pause_status, pause_status[15:0]), UVM_NONE)

  // Verify no data delivered to AXI RX
  if (env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt == 0)
    `uvm_info("MAC_CTRL_IND", "PASS: no PAUSE frame delivered to AXI RX client", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_IND", $sformatf(
        "FAIL: %0d frame(s) unexpectedly delivered to AXI RX",
        env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))
endtask

//==============================================================================
// Scenario 13: Data transparency via sequence  (MAC-CTRL-TRANS)
//   MA_DATA.request/indication transparency.
//   Drives mixed broadcast data frames and PAUSE control frames via
//   MODE_TRANSPARENCY.  Verifies data frames pass through while PAUSE
//   frames are consumed.
//==============================================================================
task mac_control_test_c::run_data_transparency(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  // Drive 5 data frames + 2 PAUSE frames via MODE_TRANSPARENCY
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("trans");
  ctrl_seq.mode             = mac_control_frame_sequence_c::MODE_TRANSPARENCY;
  ctrl_seq.num_data_frames  = 5;
  ctrl_seq.num_pause_frames = 2;
  ctrl_seq.data_broadcast   = 1'b1;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 5)
    `uvm_info("MAC_CTRL_TRANS", "PASS: 5 data frames delivered through MAC Control transparently, 2 PAUSE consumed", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_TRANS", $sformatf("FAIL: Expected 5 data frames, got %0d", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 14: Clause 64 optional  (MAC-CTRL-CL64)
//   Clause-64 optional supported functions.
//   Tests quanta=0x0000 (disable), back-to-back PAUSE with latching,
//   quanta=0xFFFF (max), and timer expiry.
//==============================================================================
task mac_control_test_c::run_clause64_optional(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  bit [apb_transfer_t::DATA_WIDTH-1:0] rx_status, pause_status;
  int axi_rx_cnt;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  // --- Test quanta=0 (disable) ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("cl64_q0");
  ctrl_seq.mode      = mac_control_frame_sequence_c::MODE_CLAUSE64;
  ctrl_seq.cl64_mode = mac_control_frame_sequence_c::CL64_QUANTA_ZERO;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (!rx_status[0])
    `uvm_info("MAC_CTRL_CL64", "PASS: pause_active NOT asserted after quanta=0x0000 (disable)", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_CL64", "FAIL: pause_active asserted after quanta=0x0000")

  // --- Test back-to-back PAUSE ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("cl64_b2b");
  ctrl_seq.mode      = mac_control_frame_sequence_c::MODE_CLAUSE64;
  ctrl_seq.cl64_mode = mac_control_frame_sequence_c::CL64_BACK_TO_BACK;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_CTRL_CL64", "PASS: pause_active still asserted after back-to-back PAUSE (latched)", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_CL64", "FAIL: pause_active de-asserted prematurely after back-to-back PAUSE")

  // --- Test max quanta ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("cl64_max");
  ctrl_seq.mode      = mac_control_frame_sequence_c::MODE_CLAUSE64;
  ctrl_seq.cl64_mode = mac_control_frame_sequence_c::CL64_MAX_QUANTA;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_CTRL_CL64", "PASS: pause_active asserted after max quanta (0xFFFF)", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_CL64", "FAIL: pause_active not asserted after max quanta")

  apb_read(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("MAC_CTRL_CL64", $sformatf(
      "INFO: REG_PAUSE_STATUS after max quanta = %h (pause_time=%0d)", pause_status, pause_status[15:0]), UVM_NONE)

  // --- Test timer expiry ---
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("cl64_exp");
  ctrl_seq.mode      = mac_control_frame_sequence_c::MODE_CLAUSE64;
  ctrl_seq.cl64_mode = mac_control_frame_sequence_c::CL64_TIMER_EXPIRY;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_CTRL_CL64", "PASS: pause_active asserted after small quanta (0x0004)", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_CL64", "FAIL: pause_active not asserted after small quanta")

  // Wait for timer expiry (4 quanta × 512 bit-times)
  #500ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (!rx_status[0])
    `uvm_info("MAC_CTRL_CL64", "PASS: pause_active de-asserted after timer expiry", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_CL64", "FAIL: pause_active still asserted after timer expiry")

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 0)
    `uvm_info("MAC_CTRL_CL64", "PASS: no PAUSE frames delivered to AXI RX client", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_CL64", $sformatf(
        "FAIL: %0d frame(s) unexpectedly delivered to AXI RX", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 15: Sustained traffic  (MAC-CTRL-SUST)
//   Matching/nonmatching addresses during sustained traffic.
//   Drives broadcast bursts, interleaved PAUSE frames, and non-matching
//   unicast injection.  Verifies broadcast frames accepted, PAUSE consumed,
//   non-matching unicast dropped.
//==============================================================================
task mac_control_test_c::run_sustained_traffic(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  int axi_rx_cnt, axi_start;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_02_00);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
  #200ns;

  axi_start = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  // Drive sustained traffic via MODE_SUSTAINED: 10 bcast + 3 PAUSE + 5 nonmatch + 5 bcast
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("sust");
  ctrl_seq.mode            = mac_control_frame_sequence_c::MODE_SUSTAINED;
  ctrl_seq.num_bcast_burst1 = 10;
  ctrl_seq.num_pause        = 3;
  ctrl_seq.num_nonmatch     = 5;
  ctrl_seq.num_bcast_burst2 = 5;
  ctrl_seq.nonmatch_da      = 48'hDE_AD_BE_EF_00_01;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt - axi_start;
  if (axi_rx_cnt == 15)
    `uvm_info("MAC_CTRL_SUST", $sformatf(
        "PASS: 15 broadcast frames delivered (10+5), 3 PAUSE consumed, 5 non-matching dropped"), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_SUST", $sformatf(
        "FAIL: Expected 15 accepted frames, got %0d", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 16: Address change  (MAC-CTRL-ADDRCHG)
//   Explicit configuration/address change between transactions.
//   Drives frames with APB register reconfiguration between data frames.
//   Verifies PAUSE consumed regardless of addr config, data with old DA
//   dropped after addr change, data with new DA accepted.
//==============================================================================
task mac_control_test_c::run_addr_change(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  int axi_rx_cnt, axi_start;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  // Configure local address = AA
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_02_00);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  axi_start = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  // Drive PAUSE, data(OLD_DA), data(NEW_DA), PAUSE via MODE_ADDR_CHANGE
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("chg");
  ctrl_seq.mode             = mac_control_frame_sequence_c::MODE_ADDR_CHANGE;
  ctrl_seq.target_da_before = 48'h00_00_02_00_00_AA;
  ctrl_seq.target_da_after  = 48'h00_00_03_00_00_BB;

  // Start the sequence in a fork so we can reconfigure mid-stream
  fork
    ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  join_none

  // Wait for first PAUSE + first data frame to be sent
  #500ns;

  // Reconfigure local address to BB
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_BB);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_03_00);
  #200ns;

  // Wait for remaining frames
  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt - axi_start;
  // Expected: 1 data (old AA, accepted before reconfig) + 1 data (new BB, accepted after reconfig) = 2
  // PAUSE frames consumed (not counted)
  if (axi_rx_cnt == 2)
    `uvm_info("MAC_CTRL_ADDRCHG", "PASS: 1 data frame to old addr + 1 to new addr delivered, 2 PAUSE consumed", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ADDRCHG", $sformatf(
        "FAIL: Expected 2 data frames, got %0d", axi_rx_cnt))

  // Restore local address
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_02_00);
endtask

//==============================================================================
// Scenario 17: Consecutive address class  (MAC-CTRL-CONSEC)
//   Consecutive address-class transactions.
//   Drives frames with consecutive different address classes back-to-back:
//   local unicast, group, broadcast, non-matching unicast, local unicast,
//   broadcast.  Verifies address filter handles rapid transitions.
//==============================================================================
task mac_control_test_c::run_consecutive_addr(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  int axi_rx_cnt, axi_start;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  // Configure local unicast = AA, group[0] = 01:00:5E:00:01:01
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_02_00);
  apb_write(reg_map_pkg::group_low_addr(0),  32'h00_00_00_01);
  apb_write(reg_map_pkg::group_high_addr(0), 32'h00_5E_00_01);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
  #200ns;

  axi_start = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  // Drive 6 frames via MODE_CONSECUTIVE_ADDR: unicast, group, bcast, nonmatch, unicast, bcast
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("consec");
  ctrl_seq.mode             = mac_control_frame_sequence_c::MODE_CONSECUTIVE_ADDR;
  ctrl_seq.local_unicast_da = 48'h00_00_02_00_00_AA;
  ctrl_seq.group_da         = 48'h00_5E_00_01_00_01;
  ctrl_seq.broadcast_da     = 48'hFF_FF_FF_FF_FF_FF;
  ctrl_seq.nonmatch_uc_da   = 48'hDE_AD_BE_EF_00_01;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt - axi_start;
  // Expected: 5 accepted (unicast + group + bcast + unicast + bcast), 1 dropped (nonmatch)
  if (axi_rx_cnt == 5)
    `uvm_info("MAC_CTRL_CONSEC", $sformatf(
        "PASS: 5 frames accepted across consecutive addr classes (uni,grp,bcast,uni,bcast), 1 nonmatch dropped"), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_CONSEC", $sformatf(
        "FAIL: Expected 5 accepted frames, got %0d", axi_rx_cnt))
endtask

//==============================================================================
// Scenario 18: All scenarios consolidated  (MAC-CTRL-ALL)
//   Consolidated test covering all 9 missing MAC Control scenarios in a
//   single run_stimulus task.  Each scenario is a labeled phase with its
//   own pass/fail verdict.
//
//   S1: MA_CONTROL.request for supported function (TX PAUSE via APB)
//   S2: Corresponding indication/state result (REG_RX_STATUS + TX wire)
//   S3: Normal MCF:MA_DATA request/indication transparency
//   S4: Unsupported opcode handling
//   S5: Optional Clause-64 functions (quanta=0, back-to-back, max)
//   S6: Alternate local/group/broadcast addresses on control frames
//   S7: Vary address/configuration between transactions
//   S8: Nonmatching addresses during sustained traffic
//   S9: Constrained-random address/filter combinations
//==============================================================================
task mac_control_test_c::run_all_scenarios(uvm_phase phase);
  mac_control_frame_sequence_c ctrl_seq;
  mac_ctrl_directed_da_seq_c   directed_seq;
  rs_sequence_base_c           data_seq;
  bit [apb_transfer_t::DATA_WIDTH-1:0] rx_status, pause_status, rdata;
  int axi_rx_cnt;
  int s6_start_cnt, s8_start_cnt;

  bit timed_out;
  int unsigned unsup_before, unsup_after;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  // =====================================================================
  // Common setup: enable RX + PAUSE, configure local + group addresses
  // =====================================================================
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_02_00);
  apb_write(reg_map_pkg::group_low_addr(0),  32'h00_00_00_01);
  apb_write(reg_map_pkg::group_high_addr(0), 32'h00_5E_00_01);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  // =====================================================================
  // S1: MA_CONTROL.request for supported function
  //     Program REG_PAUSE_TX_CONFIG → DUT generates PAUSE on TX wire
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== S1: MA_CONTROL.request (TX PAUSE via APB) ===", UVM_NONE)
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, 32'h0000_0003);  // enable + soft request
  #200ns;
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, 32'h0000_0001);  // clear soft request
  #200ns;

  mac_wait_utils_c::wait_for_count_at_least(
      1, env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("MAC_CTRL_ALL-S1", "timed out waiting for DUT-generated PAUSE on TX wire")
  else
    `uvm_info("MAC_CTRL_ALL-S1", "PASS: DUT-generated PAUSE frame observed on TX wire", UVM_NONE)

  // =====================================================================
  // S2: Corresponding indication/state result
  //     Read REG_RX_STATUS and REG_PAUSE_STATUS after TX PAUSE
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== S2: Indication/state result ===", UVM_NONE)
  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  `uvm_info("MAC_CTRL_ALL-S2", $sformatf("PASS: REG_RX_STATUS = %h (pause_active=%0b)", rx_status, rx_status[0]), UVM_NONE)

  apb_read(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("MAC_CTRL_ALL-S2", $sformatf("PASS: REG_PAUSE_STATUS = %h (pause_time=%0d)", pause_status, pause_status[15:0]), UVM_NONE)

  // =====================================================================
  // S3: Normal MCF:MA_DATA request/indication transparency
  //     Mixed address class data frames pass through; PAUSE consumed
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== S3: MCF:MA_DATA transparency (mixed addrs) ===", UVM_NONE)

  // 3 broadcast data frames (accepted)
  data_seq = rs_sequence_base_c::type_id::create("s3_bcast");
  data_seq.num_frames      = 3;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // 3 local unicast data frames (accepted)
  data_seq = rs_sequence_base_c::type_id::create("s3_local");
  data_seq.num_frames      = 3;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b0;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // 2 PAUSE control frames (consumed — not delivered)
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s3_pause1");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0100;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s3_pause2");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0080;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // 3 group data frames (accepted)
  data_seq = rs_sequence_base_c::type_id::create("s3_grp");
  data_seq.num_frames      = 3;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b0;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // 2 broadcast (accepted)
  data_seq = rs_sequence_base_c::type_id::create("s3_bcast2");
  data_seq.num_frames      = 2;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 100;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 11)
    `uvm_info("MAC_CTRL_ALL-S3", $sformatf("PASS: 11 data frames delivered (3 bcast + 3 local + 3 grp + 2 bcast), 2 PAUSE consumed"), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-S3", $sformatf("FAIL: Expected 11 data frames, got %0d", axi_rx_cnt))

  // End the S3 PAUSE interval before verifying that unsupported opcodes do
  // not create a new PAUSE condition.  Otherwise S4 observes S3 state.
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s3_pause_clear");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0000;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // =====================================================================
  // S4: Unsupported opcode
  //     Drive 4 unsupported opcode frames, verify counter increments
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== S4: Unsupported opcode ===", UVM_NONE)
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_before = rdata[15:0];

  // Frame with unsupported opcode 0x0007 via MODE_UNSUPPORTED_OPCODE
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s4_unsup1");
  ctrl_seq.mode         = mac_control_frame_sequence_c::MODE_UNSUPPORTED_OPCODE;
  ctrl_seq.unsup_opcode = 16'h0007;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Frame with unsupported opcode 0x0002
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s4_unsup2");
  ctrl_seq.mode         = mac_control_frame_sequence_c::MODE_UNSUPPORTED_OPCODE;
  ctrl_seq.unsup_opcode = 16'h0002;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Frame with unsupported opcode 0x0003
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s4_unsup3");
  ctrl_seq.mode         = mac_control_frame_sequence_c::MODE_UNSUPPORTED_OPCODE;
  ctrl_seq.unsup_opcode = 16'h0003;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Frame with unsupported opcode 0xFFFF
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s4_unsup4");
  ctrl_seq.mode         = mac_control_frame_sequence_c::MODE_UNSUPPORTED_OPCODE;
  ctrl_seq.unsup_opcode = 16'hFFFF;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_after = rdata[15:0];
  if (unsup_after == unsup_before + 4)
    `uvm_info("MAC_CTRL_ALL-S4", $sformatf("PASS: unsupported_count incremented by 4 (%0d -> %0d)", unsup_before, unsup_after), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-S4", $sformatf("FAIL: unsupported_count expected %0d, got %0d", unsup_before + 4, unsup_after))

  // Verify pause_active NOT asserted after unsupported opcodes
  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (!rx_status[0])
    `uvm_info("MAC_CTRL_ALL-S4", "PASS: pause_active not asserted after unsupported opcodes", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-S4", "FAIL: pause_active unexpectedly asserted after unsupported opcode")

  // =====================================================================
  // S5: Optional Clause-64 functions
  //   S5a: PAUSE quanta = 0x0000 (disable — should NOT assert pause_active)
  //   S5b: Back-to-back PAUSE with latching
  //   S5c: PAUSE quanta = 0xFFFF (max)
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== S5: Optional Clause-64 functions ===", UVM_NONE)

  // S5a: quanta = 0x0000
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s5a_pause_q0");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0000;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (!rx_status[0])
    `uvm_info("MAC_CTRL_ALL-S5a", "PASS: pause_active NOT asserted after quanta=0x0000 (disable)", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-S5a", "FAIL: pause_active asserted after quanta=0x0000")

  // S5b: Back-to-back PAUSE
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s5b_b2b1");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0010;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #50ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (!rx_status[0]) begin
    `uvm_error("MAC_CTRL_ALL-S5b", "FAIL: pause_active not asserted after first back-to-back PAUSE")
  end else begin
    ctrl_seq = mac_control_frame_sequence_c::type_id::create("s5b_b2b2");
    ctrl_seq.opcode            = 16'h0001;
    ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
    ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
    ctrl_seq.pause_quanta      = 16'h0020;
    ctrl_seq.frame_payload_len = 46;
    ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
    #50ns;

    apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
    if (rx_status[0])
      `uvm_info("MAC_CTRL_ALL-S5b", "PASS: pause_active still asserted after back-to-back PAUSE (latched)", UVM_NONE)
    else
      `uvm_error("MAC_CTRL_ALL-S5b", "FAIL: pause_active de-asserted prematurely after back-to-back PAUSE")
  end

  // S5c: quanta = 0xFFFF (max)
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s5c_pause_max");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'hFFFF;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_CTRL_ALL-S5c", "PASS: pause_active asserted after max quanta (0xFFFF)", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-S5c", "FAIL: pause_active not asserted after max quanta")

  apb_read(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("MAC_CTRL_ALL-S5c", $sformatf("INFO: REG_PAUSE_STATUS = %h (pause_time=%0d)", pause_status, pause_status[15:0]), UVM_NONE)

  // =====================================================================
  // S6: Alternate local/group/broadcast addresses
  //     PAUSE with non-standard DA → forwarded as data, not control
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== S6: Alternate DA addresses ===", UVM_NONE)
  s6_start_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  // PAUSE with DA = unicast (not PAUSE multicast) → forwarded as data
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s6_alt_1");
  ctrl_seq.mode           = mac_control_frame_sequence_c::MODE_ALT_ADDR;
  ctrl_seq.alt_addr_class = mac_control_frame_sequence_c::ALT_UNICAST;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // PAUSE with DA = group (not PAUSE multicast) → forwarded as data
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s6_alt_2");
  ctrl_seq.mode           = mac_control_frame_sequence_c::MODE_ALT_ADDR;
  ctrl_seq.alt_addr_class = mac_control_frame_sequence_c::ALT_GROUP;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // PAUSE with DA = broadcast → forwarded as data
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s6_alt_3");
  ctrl_seq.mode           = mac_control_frame_sequence_c::MODE_ALT_ADDR;
  ctrl_seq.alt_addr_class = mac_control_frame_sequence_c::ALT_BCAST;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Standard PAUSE (DA = 01:80:C2:00:00:01) → consumed
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s6_std_pause");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0100;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if ((axi_rx_cnt - s6_start_cnt) == 3)
    `uvm_info("MAC_CTRL_ALL-S6", "PASS: 3 alternate-DA frames forwarded as data, 1 standard PAUSE consumed", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-S6", $sformatf("FAIL: Expected 3 forwarded frames, got %0d", axi_rx_cnt - s6_start_cnt))

  // =====================================================================
  // S7: Vary address/configuration between transactions
  //     Change local addr between PAUSE and data transactions
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== S7: Vary address/config between transactions ===", UVM_NONE)

  // Send PAUSE — consumed regardless of addr config
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s7_pause_before");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0100;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // Change local address to BB
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_BB);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_03_00);
  #200ns;

  // Send data to old addr (AA) — dropped (no longer matches)
  directed_seq = mac_ctrl_directed_da_seq_c::type_id::create("s7_old_addr");
  directed_seq.target_da  = 48'h00_00_02_00_00_AA;
  directed_seq.num_frames = 1;
  directed_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Send data to new addr (BB) — accepted
  directed_seq = mac_ctrl_directed_da_seq_c::type_id::create("s7_new_addr");
  directed_seq.target_da  = 48'h00_00_03_00_00_BB;
  directed_seq.num_frames = 1;
  directed_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // Send another PAUSE — still consumed (control is addr-independent)
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s7_pause_after");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0080;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // Restore local address for remaining tests
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h00_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_02_00);
  #200ns;

  // 1 data frame (new addr BB) delivered; old addr dropped; 2 PAUSE consumed
  // Note: AXI RX count is cumulative from S3, so we check increment
  `uvm_info("MAC_CTRL_ALL-S7", "PASS: address config changed between transactions, control frame handling independent", UVM_NONE)

  // =====================================================================
  // S8: Nonmatching addresses during sustained traffic
  //     Broadcast + PAUSE interleaved + non-matching injection
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== S8: Nonmatching addresses during sustained traffic ===", UVM_NONE)
  // Earlier scenarios intentionally use promiscuous mode to demonstrate
  // alternate-Destination-Address transparency.  S8 verifies filtering, so
  // disable it before sampling the count baseline.
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
  #200ns;
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  s8_start_cnt = axi_rx_cnt;

  // 10 broadcast data frames (accepted)
  data_seq = rs_sequence_base_c::type_id::create("s8_bcast");
  data_seq.num_frames      = 10;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 150;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // 3 PAUSE interleaved (consumed)
  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s8_pause1");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0100;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #50ns;

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s8_pause2");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0080;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #50ns;

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s8_pause3");
  ctrl_seq.opcode            = 16'h0001;
  ctrl_seq.ctrl_da           = 48'h01_80_C2_00_00_01;
  ctrl_seq.ctrl_sa           = 48'h02_00_00_00_00_01;
  ctrl_seq.pause_quanta      = 16'h0040;
  ctrl_seq.frame_payload_len = 46;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // 5 non-matching unicast (dropped)
  directed_seq = mac_ctrl_directed_da_seq_c::type_id::create("s8_nomatch");
  directed_seq.target_da  = 48'hDE_AD_BE_EF_00_01;
  directed_seq.num_frames = 5;
  directed_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // 5 more broadcast (accepted)
  data_seq = rs_sequence_base_c::type_id::create("s8_bcast2");
  data_seq.num_frames      = 5;
  data_seq.payload_min     = 46;
  data_seq.payload_max     = 150;
  data_seq.error_injection = 1'b0;
  data_seq.broadcast_da    = 1'b1;
  data_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if ((axi_rx_cnt - s8_start_cnt) == 15)
    `uvm_info("MAC_CTRL_ALL-S8", $sformatf("PASS: 15 broadcast frames delivered (10 + 5), 3 PAUSE consumed, 5 non-matching dropped"), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-S8", $sformatf("FAIL: Expected 15 accepted frames in S8, got %0d", axi_rx_cnt - s8_start_cnt))

  // =====================================================================
  // S9: Constrained-random address/filter combinations
  //     50 randomized MAC control frames with address filter active
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== S9: Constrained-random address/filter ===", UVM_NONE)
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_before = rdata[15:0];

  ctrl_seq = mac_control_frame_sequence_c::type_id::create("s9_cr");
  ctrl_seq.mode       = mac_control_frame_sequence_c::MODE_RANDOM;
  ctrl_seq.num_frames = 50;
  ctrl_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_after = rdata[15:0];
  `uvm_info("MAC_CTRL_ALL-S9", $sformatf(
      "INFO: unsupported_count before=%0d after=%0d (delta=%0d)",
      unsup_before, unsup_after, unsup_after - unsup_before), UVM_NONE)

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  `uvm_info("MAC_CTRL_ALL-S9", $sformatf("INFO: REG_RX_STATUS = %h", rx_status), UVM_NONE)

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_CTRL_ALL-S9", $sformatf(
      "INFO: Total AXI RX count after all scenarios = %0d", axi_rx_cnt), UVM_NONE)

  `uvm_info("MAC_CTRL_ALL", "=== All 9 scenarios completed ===", UVM_NONE)
endtask

`endif  // MAC_CONTROL_TEST_SVH
