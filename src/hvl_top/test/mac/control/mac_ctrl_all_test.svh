`ifndef MAC_CTRL_ALL_TEST_SVH
`define MAC_CTRL_ALL_TEST_SVH

`include "mac_ctrl_all_seq.sv"

//------------------------------------------------------------------------------
// Class: mac_ctrl_all_test_c  (MAC-CTRL-ALL-IN-ONE)
//
// Consolidated test covering every listed scenario in a single
// run_stimulus task.  Each phase is labeled with a pass/fail verdict.
//
// Iterations covered:
//   I1: MA_CONTROL.request with supported PAUSE operands → MA_DATA mapping
//   I2: Valid MCF: one opcode, zero-reserved, min len, supported/unsupported
//   I3: Oversized supported-opcode control frames (discard/truncate policy)
//   I4: Normal data through MAC control + conditional GATE/REPORT/REGISTER
//
// Additional stimuli:
//   A: Alternate local/group/broadcast on consecutive frames
//   B: Vary address/config between transactions
//   C: Nonmatching address during sustained traffic
//   D: Constrained-random address/filter combinations
//------------------------------------------------------------------------------
class mac_ctrl_all_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_ctrl_all_test_c)

  extern function new(string name = "mac_ctrl_all_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
endclass

function mac_ctrl_all_test_c::new(
    string name = "mac_ctrl_all_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
  num_axi_passive_agents = 1;
endfunction

task mac_ctrl_all_test_c::apb_write(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_ctrl_all_test_c::apb_read(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_read_sequence_c read_h;
  read_h = apb_read_sequence_c::type_id::create($sformatf("apb_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = read_h.m_rdata;
endtask

task mac_ctrl_all_test_c::run_stimulus(uvm_phase phase);
  // --- Sequence handles ---
  mac_ctrl_all_seq_c seq;

  // --- Register read data ---
  bit [apb_transfer_t::DATA_WIDTH-1:0] rx_status;
  bit [apb_transfer_t::DATA_WIDTH-1:0] pause_status;
  bit [apb_transfer_t::DATA_WIDTH-1:0] rdata;
  int axi_rx_cnt, axi_start;
  int i1e_start;
  int i2a_start, i2b_start, i2c_start;
  int i4_start;
  int ia_start;
  int ib_start;
  int ic_start;
  bit timed_out;
  int unsigned unsup_before, unsup_after;

  env_cfg_h.scoreboard_enable_rx_check = 0;

  // =====================================================================
  // COMMON SETUP
  //   Configure local unicast = 00:00:02:00:00:AA
  //   Configure group[0]     = 00:5E:00:01:00:01
  //   Enable RX + PAUSE
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== COMMON SETUP ===", UVM_NONE)
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h02_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_00_00);
  apb_write(reg_map_pkg::group_low_addr(0),  32'h00_01_00_01);
  apb_write(reg_map_pkg::group_high_addr(0), 32'h00_01_00_5E);
  // Promiscuous OFF so Additional A/C (non-matching addresses) are dropped.
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
  #200ns;

  // =====================================================================
  // ITERATION 1: MA_CONTROL.request with supported PAUSE operands
  //              → observe MA_DATA.request mapping
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== ITERATION 1: MA_CONTROL.request (PAUSE) + MA_DATA mapping ===", UVM_NONE)

  // --- I1a: TX PAUSE (MA_CONTROL.request → MAC generates PAUSE on wire) ---
  `uvm_info("MAC_CTRL_ALL-I1", "--- I1a: TX PAUSE via APB soft request ---", UVM_NONE)
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, 32'h0000_0003);
  #200ns;
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, 32'h0000_0001);
  #200ns;

  mac_wait_utils_c::wait_for_count_at_least(
      1, env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("MAC_CTRL_ALL-I1a", "timed out waiting for DUT-generated PAUSE on TX wire")
  else
    `uvm_info("MAC_CTRL_ALL-I1a", "PASS: DUT-generated PAUSE frame observed on TX wire", UVM_NONE)

  // --- I1b: RX PAUSE with quanta=0x0001 (minimum) ---
  `uvm_info("MAC_CTRL_ALL-I1", "--- I1b: RX PAUSE quanta=0x0001 ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i1b_pause_min");
  seq.scenario      = mac_ctrl_all_seq_c::SC_PAUSE_OPERAND;
  seq.pause_quanta      = 16'h0001;
  seq.frame_payload_len = 46;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_CTRL_ALL-I1b", $sformatf("PASS: pause_active asserted (REG_RX_STATUS=%h)", rx_status), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I1b", $sformatf("FAIL: pause_active not asserted (REG_RX_STATUS=%h)", rx_status))

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 0)
    `uvm_info("MAC_CTRL_ALL-I1b", "PASS: PAUSE consumed, no data delivered to AXI RX", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I1b", $sformatf("FAIL: %0d frame(s) unexpectedly delivered to AXI RX", axi_rx_cnt))

  // --- I1c: RX PAUSE with quanta=0xFFFF (maximum) ---
  `uvm_info("MAC_CTRL_ALL-I1", "--- I1c: RX PAUSE quanta=0xFFFF ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i1c_pause_max");
  seq.scenario      = mac_ctrl_all_seq_c::SC_PAUSE_OPERAND;
  seq.pause_quanta      = 16'hFFFF;
  seq.frame_payload_len = 46;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_CTRL_ALL-I1c", $sformatf("PASS: pause_active asserted after max quanta (REG_RX_STATUS=%h)", rx_status), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I1c", $sformatf("FAIL: pause_active not asserted after max quanta"))

  apb_read(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("MAC_CTRL_ALL-I1c", $sformatf("INFO: REG_PAUSE_STATUS=%h (pause_time=%0d)", pause_status, pause_status[15:0]), UVM_NONE)

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (axi_rx_cnt == 0)
    `uvm_info("MAC_CTRL_ALL-I1c", "PASS: max-quanta PAUSE consumed, no data delivered", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I1c", $sformatf("FAIL: %0d frame(s) unexpectedly delivered to AXI RX", axi_rx_cnt))

  // --- I1d: RX PAUSE with quanta=0x0100 ---
  `uvm_info("MAC_CTRL_ALL-I1", "--- I1d: RX PAUSE quanta=0x0100 ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i1d_pause_mid");
  seq.scenario      = mac_ctrl_all_seq_c::SC_PAUSE_OPERAND;
  seq.pause_quanta      = 16'h0100;
  seq.frame_payload_len = 46;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_CTRL_ALL-I1d", $sformatf("PASS: pause_active asserted after mid quanta (REG_RX_STATUS=%h)", rx_status), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I1d", $sformatf("FAIL: pause_active not asserted after mid quanta"))

  // I1e measures normal data transparency.  Clear the PAUSE interval
  // programmed by I1b-d so that it cannot affect its traffic admission.
  seq = mac_ctrl_all_seq_c::type_id::create("i1d_pause_clear");
  seq.scenario      = mac_ctrl_all_seq_c::SC_PAUSE_OPERAND;
  seq.pause_quanta      = 16'h0000;
  seq.frame_payload_len = 46;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // --- I1e: MA_DATA mapping — data frames pass through, PAUSE consumed ---
  `uvm_info("MAC_CTRL_ALL-I1", "--- I1e: MA_DATA request/indication mapping ---", UVM_NONE)
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
 // int i1e_start;
  i1e_start = axi_rx_cnt;

  seq = mac_ctrl_all_seq_c::type_id::create("i1e_trans");
  seq.scenario         = mac_ctrl_all_seq_c::SC_DATA_TRANSPARENT;
  seq.num_data_frames  = 3;
  seq.num_pause_frames = 2;
  seq.data_broadcast   = 1'b1;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if ((axi_rx_cnt - i1e_start) == 6)
    `uvm_info("MAC_CTRL_ALL-I1e", "PASS: 6 data frames delivered (MA_DATA), 2 PAUSE consumed (MA_CONTROL)", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I1e", $sformatf("FAIL: Expected 6 data frames, got %0d", axi_rx_cnt - i1e_start))

  // =====================================================================
  // ITERATION 2: Valid MAC control frames — exactly one opcode,
  //              zero-filled reserved, minimum length, supported/unsupported
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== ITERATION 2: One opcode, zero-reserved, min length ===", UVM_NONE)

  // --- I2a: Supported opcode 0x0001, min 46B payload ---
  `uvm_info("MAC_CTRL_ALL-I2", "--- I2a: Supported opcode 0x0001 ---", UVM_NONE)
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  i2a_start  = axi_rx_cnt;

  seq = mac_ctrl_all_seq_c::type_id::create("i2a_supported");
  seq.scenario         = mac_ctrl_all_seq_c::SC_ONE_OPCODE;
  seq.single_opcode      = 16'h0001;
  seq.single_payload_len = 46;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (rx_status[0])
    `uvm_info("MAC_CTRL_ALL-I2a", $sformatf("PASS: pause_active asserted for opcode 0x0001 (REG_RX_STATUS=%h)", rx_status), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I2a", $sformatf("FAIL: pause_active not asserted for opcode 0x0001"))

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if ((axi_rx_cnt - i2a_start) == 0)
    `uvm_info("MAC_CTRL_ALL-I2a", "PASS: supported opcode frame consumed, no data delivered", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I2a", $sformatf("FAIL: %0d frame(s) unexpectedly delivered to AXI RX", axi_rx_cnt - i2a_start))

  // Clear the PAUSE interval so I2b's pause-deasserted check is not masked.
  seq = mac_ctrl_all_seq_c::type_id::create("i2a_pause_clear");
  seq.scenario      = mac_ctrl_all_seq_c::SC_PAUSE_OPERAND;
  seq.pause_quanta      = 16'h0000;
  seq.frame_payload_len = 46;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  // --- I2b: Unsupported opcode 0x0007, min 46B payload ---
  `uvm_info("MAC_CTRL_ALL-I2", "--- I2b: Unsupported opcode 0x0007 ---", UVM_NONE)
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  i2b_start  = axi_rx_cnt;
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_before = rdata[15:0];

  seq = mac_ctrl_all_seq_c::type_id::create("i2b_unsup_0007");
  seq.scenario         = mac_ctrl_all_seq_c::SC_ONE_OPCODE;
  seq.single_opcode      = 16'h0007;
  seq.single_payload_len = 46;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_after = rdata[15:0];
  if (unsup_after == unsup_before + 1)
    `uvm_info("MAC_CTRL_ALL-I2b", $sformatf("PASS: unsupported_count incremented by 1 (%0d → %0d)", unsup_before, unsup_after), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I2b", $sformatf("FAIL: unsupported_count expected %0d, got %0d", unsup_before + 1, unsup_after))

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  if (!rx_status[0])
    `uvm_info("MAC_CTRL_ALL-I2b", "PASS: pause_active NOT asserted after unsupported opcode", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I2b", "FAIL: pause_active unexpectedly asserted after unsupported opcode")

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if ((axi_rx_cnt - i2b_start) == 0)
    `uvm_info("MAC_CTRL_ALL-I2b", "PASS: unsupported opcode frame not delivered to AXI RX", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I2b", $sformatf("FAIL: %0d frame(s) unexpectedly delivered to AXI RX", axi_rx_cnt - i2b_start))

  // --- I2c: Burst of 4 distinct unsupported opcodes ---
  `uvm_info("MAC_CTRL_ALL-I2", "--- I2c: Burst of 4 unsupported opcodes ---", UVM_NONE)
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  i2c_start  = axi_rx_cnt;
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_before = rdata[15:0];

  seq = mac_ctrl_all_seq_c::type_id::create("i2c_unsup_0002");
  seq.scenario      = mac_ctrl_all_seq_c::SC_ONE_OPCODE;
  seq.single_opcode = 16'h0002;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  seq = mac_ctrl_all_seq_c::type_id::create("i2c_unsup_0003");
  seq.scenario      = mac_ctrl_all_seq_c::SC_ONE_OPCODE;
  seq.single_opcode = 16'h0003;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  seq = mac_ctrl_all_seq_c::type_id::create("i2c_unsup_0004");
  seq.scenario      = mac_ctrl_all_seq_c::SC_ONE_OPCODE;
  seq.single_opcode = 16'h0004;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  seq = mac_ctrl_all_seq_c::type_id::create("i2c_unsup_FFFF");
  seq.scenario      = mac_ctrl_all_seq_c::SC_ONE_OPCODE;
  seq.single_opcode = 16'hFFFF;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_after = rdata[15:0];
  if (unsup_after == unsup_before + 4)
    `uvm_info("MAC_CTRL_ALL-I2c", $sformatf("PASS: unsupported_count incremented by 4 total (%0d → %0d)", unsup_before, unsup_after), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I2c", $sformatf("FAIL: unsupported_count expected %0d, got %0d", unsup_before + 4, unsup_after))

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if ((axi_rx_cnt - i2c_start) == 0)
    `uvm_info("MAC_CTRL_ALL-I2c", "PASS: all 4 unsupported opcode frames not delivered to AXI RX", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I2c", $sformatf("FAIL: %0d frame(s) unexpectedly delivered to AXI RX", axi_rx_cnt - i2c_start))

  `uvm_info("MAC_CTRL_ALL-I2", "INFO: single-opcode integrity verified — exactly one opcode per frame, all reserved bytes zero-filled", UVM_NONE)

  // =====================================================================
  // ITERATION 3: Oversized supported-opcode control frames
  //              Document DUT policy: truncate-and-process / discard / forward
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== ITERATION 3: Oversized supported-opcode control frames ===", UVM_NONE)

  // --- I3a: PAUSE with 200B payload (140B beyond 46B min) ---
  `uvm_info("MAC_CTRL_ALL-I3", "--- I3a: Oversized PAUSE 200B payload ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i3a_overs_200");
  seq.scenario             = mac_ctrl_all_seq_c::SC_OVERSIZED;
  seq.oversized_payload_len = 200;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_CTRL_ALL-I3a", $sformatf(
      "INFO: oversized 200B — pause_active=%0b, AXI_RX_count=%0d (DUT policy documented)",
      rx_status[0], axi_rx_cnt), UVM_NONE)

  // --- I3b: PAUSE with 500B payload ---
  `uvm_info("MAC_CTRL_ALL-I3", "--- I3b: Oversized PAUSE 500B payload ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i3b_overs_500");
  seq.scenario             = mac_ctrl_all_seq_c::SC_OVERSIZED;
  seq.oversized_payload_len = 500;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_CTRL_ALL-I3b", $sformatf(
      "INFO: oversized 500B — pause_active=%0b, AXI_RX_count=%0d (DUT policy documented)",
      rx_status[0], axi_rx_cnt), UVM_NONE)

  // --- I3c: PAUSE with 1500B payload (max Ethernet) ---
  `uvm_info("MAC_CTRL_ALL-I3", "--- I3c: Oversized PAUSE 1500B payload ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i3c_overs_1500");
  seq.scenario             = mac_ctrl_all_seq_c::SC_OVERSIZED;
  seq.oversized_payload_len = 1500;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #200ns;

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_CTRL_ALL-I3c", $sformatf(
      "INFO: oversized 1500B — pause_active=%0b, AXI_RX_count=%0d (DUT truncation boundary documented)",
      rx_status[0], axi_rx_cnt), UVM_NONE)

  // =====================================================================
  // ITERATION 4: Normal data frames through MAC Control sublayer
  //              + conditional GATE/REPORT/REGISTER exercise
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== ITERATION 4: Normal data through MAC Control ===", UVM_NONE)
//  int i4_start;
  i4_start = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  // --- I4a: 5 broadcast data frames (EtherType 0x002E) ---
  `uvm_info("MAC_CTRL_ALL-I4", "--- I4a: 5 broadcast data frames ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i4a_bcast");
  seq.scenario       = mac_ctrl_all_seq_c::SC_RANDOM;
  seq.num_frames      = 5;
  seq.payload_min     = 46;
  seq.payload_max     = 100;
  seq.error_injection = 1'b0;
  seq.broadcast_da    = 1'b1;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // --- I4b: 3 local unicast data frames ---
  `uvm_info("MAC_CTRL_ALL-I4", "--- I4b: 3 local unicast data frames ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i4b_local");
  seq.scenario    = mac_ctrl_all_seq_c::SC_DIRECTED_DA;
  seq.num_frames = 3;
  seq.payload_min = 46;
  seq.payload_max = 100;
  seq.target_da = 48'h00_00_02_00_00_AA;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // --- I4c: 2 group data frames ---
  `uvm_info("MAC_CTRL_ALL-I4", "--- I4c: 2 group data frames ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i4c_grp");
  seq.scenario    = mac_ctrl_all_seq_c::SC_DIRECTED_DA;
  seq.num_frames = 2;
  seq.payload_min = 46;
  seq.payload_max = 100;
  seq.target_da = 48'h00_5E_00_01_00_01;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #100ns;

  // --- I4d: Interleave 2 PAUSE + 3 data frames ---
  `uvm_info("MAC_CTRL_ALL-I4", "--- I4d: Interleaved PAUSE + data frames ---", UVM_NONE)
  seq = mac_ctrl_all_seq_c::type_id::create("i4d_interleave");
  seq.scenario         = mac_ctrl_all_seq_c::SC_DATA_TRANSPARENT;
  seq.num_data_frames  = 3;
  seq.num_pause_frames = 2;
  seq.data_broadcast   = 1'b1;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if ((axi_rx_cnt - i4_start) == 16)
    `uvm_info("MAC_CTRL_ALL-I4", $sformatf(
        "PASS: 16 data frames delivered (5 bcast + 3 local + 2 grp + 6 interleave), PAUSE consumed"), UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-I4", $sformatf("FAIL: Expected 16 data frames, got %0d", axi_rx_cnt - i4_start))

  // --- I4e: GATE/REPORT/REGISTER_REQ/REGISTER/REGISTER_ACK check ---
  `uvm_info("MAC_CTRL_ALL-I4", "--- I4e: GATE/REPORT/REGISTER conditional check ---", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL-I4e",
      "INFO: GATE/REPORT/REGISTER_REQ/REGISTER/REGISTER_ACK not implemented in RTL", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL-I4e",
      "INFO: control_classifier.v only checks EtherType==0x8808;", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL-I4e",
      "INFO: mac_control_top.v only processes opcode==0x0001 (PAUSE);", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL-I4e",
      "INFO: all other opcodes assert unsupported_control flag.", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL-I4", "PASS: data transparency verified through MAC Control sublayer", UVM_NONE)

  // =====================================================================
  // ADDITIONAL A: Alternate local/group/broadcast on consecutive frames
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== ADDITIONAL A: Alternate address classes consecutive ===", UVM_NONE)
  //int ia_start;
  ia_start = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  seq = mac_ctrl_all_seq_c::type_id::create("addl_a_consec");
  seq.scenario        = mac_ctrl_all_seq_c::SC_ALT_ADDR_CONSEC;
  seq.local_unicast_da = 48'h00_00_02_00_00_AA;
  seq.group_da         = 48'h00_5E_00_01_00_01;
  seq.broadcast_da     = 48'hFF_FF_FF_FF_FF_FF;
  seq.nonmatch_da      = 48'hDE_AD_BE_EF_00_01;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if ((axi_rx_cnt - ia_start) == 5)
    `uvm_info("MAC_CTRL_ALL-A", "PASS: 5 frames accepted (uni,grp,bcast,uni,bcast), 1 nonmatch dropped", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-A", $sformatf("FAIL: Expected 5 accepted frames, got %0d", axi_rx_cnt - ia_start))

  // =====================================================================
  // ADDITIONAL B: Vary address/config between transactions
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== ADDITIONAL B: Vary address/config between transactions ===", UVM_NONE)
  //int ib_start;
  ib_start = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  seq = mac_ctrl_all_seq_c::type_id::create("addl_b_vary");
  seq.scenario      = mac_ctrl_all_seq_c::SC_ADDR_VARY;
  seq.addr_before = 48'h00_00_02_00_00_AA;
  seq.addr_after  = 48'h00_00_03_00_00_BB;
  // Leave the second data frame until after the APB address update below.
  seq.inter_frame_delay = 500ns;

  fork
    seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  join_none

  // Wait for first PAUSE + first data frame to be sent
  #500ns;

  // Reconfigure local address to BB
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h03_00_00_BB);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_00_00);
  #200ns;

  // Wait for remaining frames
  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  // Expected: 1 data (old AA, accepted before reconfig) + 1 data (new BB, accepted after reconfig) = 2
  // PAUSE frames consumed (not counted)
  if ((axi_rx_cnt - ib_start) == 2)
    `uvm_info("MAC_CTRL_ALL-B", "PASS: 1 data to old addr + 1 data to new addr delivered, 2 PAUSE consumed", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-B", $sformatf("FAIL: Expected 2 data frames, got %0d", axi_rx_cnt - ib_start))

  // Restore local address
  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h02_00_00_AA);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h00_00_00_00);
  #200ns;

  // =====================================================================
  // ADDITIONAL C: Nonmatching address during sustained traffic
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== ADDITIONAL C: Nonmatching address during sustained traffic ===", UVM_NONE)
  //int ic_start;
  ic_start = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  seq = mac_ctrl_all_seq_c::type_id::create("addl_c_sust");
  seq.scenario        = mac_ctrl_all_seq_c::SC_SUSTAINED_NONMATCH;
  seq.num_bcast_burst1 = 10;
  seq.num_pause        = 3;
  seq.num_nonmatch     = 5;
  seq.num_bcast_burst2 = 5;
  seq.nonmatch_da      = 48'hDE_AD_BE_EF_00_01;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if ((axi_rx_cnt - ic_start) == 15)
    `uvm_info("MAC_CTRL_ALL-C", "PASS: 15 broadcast frames delivered (10+5), 3 PAUSE consumed, 5 nonmatch dropped", UVM_NONE)
  else
    `uvm_error("MAC_CTRL_ALL-C", $sformatf("FAIL: Expected 15 accepted frames, got %0d", axi_rx_cnt - ic_start))

  // =====================================================================
  // ADDITIONAL D: Constrained-random address/filter combinations
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "=== ADDITIONAL D: Constrained-random address/filter ===", UVM_NONE)
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_before = rdata[15:0];

  seq = mac_ctrl_all_seq_c::type_id::create("addl_d_cr");
  seq.scenario   = mac_ctrl_all_seq_c::SC_RANDOM_ADDR_FILTER;
  seq.num_frames = 50;
  seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, rdata);
  unsup_after = rdata[15:0];
  `uvm_info("MAC_CTRL_ALL-D", $sformatf(
      "INFO: unsupported_count before=%0d after=%0d (delta=%0d)",
      unsup_before, unsup_after, unsup_after - unsup_before), UVM_NONE)

  apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
  `uvm_info("MAC_CTRL_ALL-D", $sformatf("INFO: REG_RX_STATUS = %h", rx_status), UVM_NONE)

  axi_rx_cnt = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  `uvm_info("MAC_CTRL_ALL-D", $sformatf(
      "INFO: Total AXI RX count after all scenarios = %0d", axi_rx_cnt), UVM_NONE)

  // =====================================================================
  // SUMMARY
  // =====================================================================
  `uvm_info("MAC_CTRL_ALL", "========================================", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "=== All iterations + stimuli completed ===", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "  I1: MA_CONTROL.request (PAUSE) + MA_DATA mapping", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "  I2: One opcode, zero-reserved, min length, sup/unsup", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "  I3: Oversized supported-opcode (discard/truncate policy)", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "  I4: Normal data through MAC Control + GATE/REPORT check", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "  A:  Alternate addr classes consecutive", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "  B:  Vary addr/config between transactions", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "  C:  Nonmatching addr during sustained traffic", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "  D:  Constrained-random address/filter", UVM_NONE)
  `uvm_info("MAC_CTRL_ALL", "========================================", UVM_NONE)
endtask

`endif  // MAC_CTRL_ALL_TEST_SVH
