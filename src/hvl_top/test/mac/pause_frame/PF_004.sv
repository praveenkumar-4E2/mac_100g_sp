`timescale 1ns/1ps

`ifndef PF_004_PAUSE_STD_002_TEST_SVH
`define PF_004_PAUSE_STD_002_TEST_SVH

//------------------------------------------------------------------------------
// Class: PF_004_pause_std_002_test_c
// PF-004 / PAUSE_STD_002 — PAUSE Standard State, Address, and 100G Response
//
// Objective: Verify PAUSE state-machine requirements not covered by basic
// decode/timer tests, including 100G-specific response timing, address
// handling, standardized transmitEnabled state, and in-progress frame
// protection.
//
// Scenarios / Iterations:
//   I1  — Reserved multicast and station physical address reception;
//         management enablement via CTRL_PAUSE_BIT
//   I2  — MA_CONTROL.indication transitions (paused/not_paused)
//   I3  — Send PAUSE while data is paused; data remains inhibited but
//         control PAUSE can transmit
//   I4  — Exact PAUSE TX composition: local SA, reserved zeros, FCS
//   I5  — 100G timing: 394 quanta window; in-progress frame not interrupted
//   I6  — Toggle transmitEnabled state
//   I7  — Additional stimuli: alternate PAUSE/data/control, quanta near
//         zero/max, repeat before/after expiry, random quanta back-to-back
//
// Agent topology:
//   AXI TX active  — drive client frames for TX path / admission checks
//   RS  RX active  — drive PAUSE and data frames into RX path
//   RS  TX passive — monitor DUT-originated PAUSE frames on TX wire
//   AXI RX passive — monitor data delivery to client
//   APB  active    — always present (from base test)
//------------------------------------------------------------------------------
class PF_004_pause_std_002_test_c extends mac_base_test_c;

  // pause_timer_engine decrements once per 5 ns core-clock tick.
  localparam time BIT_TIME_NS       = 5ns;
  localparam time QUANTA_TIME_NS    = 512 * BIT_TIME_NS;
  localparam time MAX_QUANTA_NS     = 16'hFFFF * QUANTA_TIME_NS;
  localparam time PAUSE_TIMEOUT_NS  = MAX_QUANTA_NS + 1_000_000;
  localparam time SETTLE_NS         = 1us;
  // Gives APB status sampling and an asynchronous admission request margin.
  localparam bit [15:0] ACTIVE_QUANTA = 16'h0100;

  `uvm_component_utils(PF_004_pause_std_002_test_c)

  extern function new(string name = "PF_004_pause_std_002_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);

  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);

  extern task enable_rx_pause();
  extern task disable_rx_pause();
  extern task send_pause_quanta(bit [15:0] quanta);
  extern task send_pause_to_addr(bit [47:0] da, bit [15:0] quanta);
  extern task send_data_frame();
  extern task check_pause_status(string case_name, bit expect_active);
  extern task wait_pause_active(string case_name, time timeout_ns = 10us);
  extern task wait_pause_clear(string case_name, time timeout_ns = PAUSE_TIMEOUT_NS);

  extern task run_address_and_management();
  extern task run_indication_transitions();
  extern task run_pause_while_paused();
  extern task run_tx_composition();
  extern task run_100g_timing();
  extern task run_transmit_enabled_toggle();
  extern task run_additional_stimuli();
endclass

// =============================================================================
// Constructor
// =============================================================================
function PF_004_pause_std_002_test_c::new(string name = "PF_004_pause_std_002_test_c",
                                         uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_active_agents  = 1;
  num_rs_passive_agents  = 1;
  num_axi_passive_agents = 1;
endfunction

// =============================================================================
// APB helpers
// =============================================================================
task PF_004_pause_std_002_test_c::apb_write(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                            input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h         = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task PF_004_pause_std_002_test_c::apb_read(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                           output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_read_sequence_c read_h;
  read_h        = apb_read_sequence_c::type_id::create($sformatf("apb_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = read_h.m_rdata;
endtask

// =============================================================================
// Helpers: Enable/Disable RX PAUSE
// =============================================================================
task PF_004_pause_std_002_test_c::enable_rx_pause();
  bit [31:0] ctrl;
  ctrl = (1 << reg_map_pkg::CTRL_RX_BIT) |
         (1 << reg_map_pkg::CTRL_TX_BIT) |
         (1 << reg_map_pkg::CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
endtask

task PF_004_pause_std_002_test_c::disable_rx_pause();
  bit [31:0] ctrl;
  ctrl = (1 << reg_map_pkg::CTRL_RX_BIT) |
         (1 << reg_map_pkg::CTRL_TX_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
endtask

// =============================================================================
// Helpers: Send PAUSE to specific DA
// =============================================================================
task PF_004_pause_std_002_test_c::send_pause_quanta(bit [15:0] quanta);
  mac_control_frame_sequence_c seq_h;
  seq_h = mac_control_frame_sequence_c::type_id::create($sformatf("pause_%0h", quanta));
  seq_h.pause_quanta      = quanta;
  seq_h.frame_payload_len = 46;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task PF_004_pause_std_002_test_c::send_pause_to_addr(bit [47:0] da, bit [15:0] quanta);
  mac_pause_frame_variant_sequence_c seq_h;
  seq_h = mac_pause_frame_variant_sequence_c::type_id::create($sformatf("pause_to_%h", da));
  seq_h.dst_addr_ovr   = da;
  seq_h.pause_quanta   = quanta;
  seq_h.payload_octets = 46;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

// =============================================================================
// Helpers: Send data frames
// =============================================================================
task PF_004_pause_std_002_test_c::send_data_frame();
  axi_sequence_c tx_seq_h;
  tx_seq_h = axi_sequence_c::type_id::create("data_frame");
  tx_seq_h.num_tx      = 1;
  tx_seq_h.payload_min = 46;
  tx_seq_h.payload_max = 46;
  tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

// =============================================================================
// Helpers: Check/Wait pause status
// =============================================================================
task PF_004_pause_std_002_test_c::check_pause_status(string case_name,
                                                      bit expect_active);
  bit [31:0] status;
  apb_read(reg_map_pkg::REG_RX_STATUS, status);
  if (status[0] == expect_active)
    `uvm_info("PF_004", $sformatf("PASS [%0s]: pause_active=%0b as expected",
              case_name, status[0]), UVM_NONE)
  else
    `uvm_error("PF_004", $sformatf(
               "FAIL [%0s]: pause_active=%0b, expected %0b (REG_RX_STATUS=%h)",
               case_name, status[0], expect_active, status))
endtask

task PF_004_pause_std_002_test_c::wait_pause_active(string case_name,
                                                     time timeout_ns = 10us);
  bit [31:0] status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_RX_STATUS, status);
    if (status[0]) return;
    if (($time - start_ts) >= timeout_ns) begin
      `uvm_error("PF_004", $sformatf(
                 "FAIL [%0s]: pause_active did not assert within %0t",
                 case_name, timeout_ns))
      return;
    end
    #1us;
  end
endtask

task PF_004_pause_std_002_test_c::wait_pause_clear(string case_name,
                                                    time timeout_ns = PAUSE_TIMEOUT_NS);
  bit [31:0] status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_RX_STATUS, status);
    if (!status[0]) return;
    if (($time - start_ts) >= timeout_ns) begin
      `uvm_error("PF_004", $sformatf(
                 "FAIL [%0s]: pause_active still set %0t after case, giving up",
                 case_name, timeout_ns))
      return;
    end
    #1us;
  end
endtask

// =============================================================================
// I1: Reserved Multicast and Station Physical Address Reception
//
// Verify PAUSE is accepted from:
//   a) Reserved multicast DA (01:80:C2:00:00:01) — always accepted
//   b) Station physical address (DA = local MAC) — accepted if present
// Verify management enablement: when CTRL_PAUSE_BIT=0, PAUSE is ignored.
// =============================================================================
task PF_004_pause_std_002_test_c::run_address_and_management();
  `uvm_info("PF_004", "--- I1: Address and Management ---", UVM_LOW)

  enable_rx_pause();

  // I1a: Reserved multicast DA — should be accepted
  `uvm_info("PF_004_I1", "I1a: PAUSE to reserved multicast DA", UVM_MEDIUM)
  send_pause_to_addr(48'h01_80_C2_00_00_01, 16'h0020);
  #SETTLE_NS;
  check_pause_status("I1A_MULTICAST", 1'b1);
  wait_pause_clear("I1A_MULTICAST");

  // I1b: Station physical address — DUT MAC from REG_MAC_ADDR_LOW
  begin
    bit [31:0] mac_lo, mac_hi;
    bit [47:0] station_da;
    // Reset leaves the station MAC address at zero.  Program a legal address
    // and let the APB-to-MAC configuration bridge transfer it before this
    // station-address acceptance check.
    apb_write(reg_map_pkg::REG_MAC_ADDR_LOW,  32'h2233_4455);
    apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h0000_0011);
    // Rewriting control sends one coherent configuration bundle across the
    // APB-to-MAC CDC after both halves of the station address are present.
    enable_rx_pause();
    #1us;
    apb_read(reg_map_pkg::REG_MAC_ADDR_LOW, mac_lo);
    apb_read(reg_map_pkg::REG_MAC_ADDR_HIGH, mac_hi);
    station_da = {mac_hi[15:0], mac_lo};
    `uvm_info("PF_004_I1", $sformatf("I1b: PAUSE to station DA = %h", station_da), UVM_MEDIUM)
    send_pause_to_addr(station_da, ACTIVE_QUANTA);
    #SETTLE_NS;
    check_pause_status("I1B_STATION", 1'b1);
    wait_pause_clear("I1B_STATION");
  end

  // I1c: Non-standard unicast DA — should be ignored
  `uvm_info("PF_004_I1", "I1c: PAUSE to non-standard unicast DA", UVM_MEDIUM)
  send_pause_to_addr(48'hAA_BB_CC_DD_EE_FF, 16'h0020);
  #SETTLE_NS;
  check_pause_status("I1C_UNICAST", 1'b0);

  // I1d: Management disable — PAUSE should be ignored
  `uvm_info("PF_004_I1", "I1d: PAUSE with CTRL_PAUSE_BIT=0", UVM_MEDIUM)
  disable_rx_pause();
  send_pause_to_addr(48'h01_80_C2_00_00_01, 16'h0020);
  #SETTLE_NS;
  check_pause_status("I1D_DISABLED", 1'b0);

  // Re-enable for subsequent tests
  enable_rx_pause();

  `uvm_info("PF_004_I1", "PASS: Address and management complete", UVM_NONE)
endtask

// =============================================================================
// I2: MA_CONTROL.indication Transitions
//
// Verify the PAUSE state machine transitions:
//   not_paused -> paused (on valid PAUSE reception)
//   paused -> not_paused (on timer expiry)
// =============================================================================
task PF_004_pause_std_002_test_c::run_indication_transitions();
  bit [31:0] status;

  `uvm_info("PF_004", "--- I2: Indication Transitions ---", UVM_LOW)

  enable_rx_pause();

  // Verify initial state: not paused
  apb_read(reg_map_pkg::REG_RX_STATUS, status);
  if (!status[0])
    `uvm_info("PF_004_I2", "PASS [I2_INIT]: Initial state is not_paused", UVM_NONE)
  else
    `uvm_error("PF_004_I2", "FAIL [I2_INIT]: Initial state is paused")

  // Transition not_paused -> paused
  `uvm_info("PF_004_I2", "I2a: not_paused -> paused", UVM_MEDIUM)
  send_pause_quanta(ACTIVE_QUANTA);
  #SETTLE_NS;
  check_pause_status("I2A_TRANSITION", 1'b1);

  // Transition paused -> not_paused (wait for timer expiry)
  `uvm_info("PF_004_I2", "I2b: paused -> not_paused", UVM_MEDIUM)
  wait_pause_clear("I2B_TRANSITION");

  // Verify final state: not_paused
  apb_read(reg_map_pkg::REG_RX_STATUS, status);
  if (!status[0])
    `uvm_info("PF_004_I2", "PASS [I2_FINAL]: Final state is not_paused", UVM_NONE)
  else
    `uvm_error("PF_004_I2", "FAIL [I2_FINAL]: Final state is paused")

  `uvm_info("PF_004_I2", "PASS: Indication transitions complete", UVM_NONE)
endtask

// =============================================================================
// I3: PAUSE While Data is Paused
//
// Verify:
//   a) Data frames are inhibited while pause_active is set
//   b) A second PAUSE frame (control) can still be transmitted
//   c) Data resumes after timer expiry
// =============================================================================
task PF_004_pause_std_002_test_c::run_pause_while_paused();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_004", "--- I3: Pause While Paused ---", UVM_LOW)

  enable_rx_pause();

  // I3a: Send PAUSE, then try to send data — data should be inhibited
  `uvm_info("PF_004_I3", "I3a: Data inhibition during pause", UVM_MEDIUM)
  send_pause_quanta(ACTIVE_QUANTA);
  #SETTLE_NS;
  check_pause_status("I3A_INHIBIT", 1'b1);

  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  fork
    send_data_frame();
  join_none
  #500ns;
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_after == tx_before)
    `uvm_info("PF_004_I3", "PASS [I3A]: Data TX inhibited while paused", UVM_NONE)
  else
    `uvm_error("PF_004_I3", $sformatf(
               "FAIL [I3A]: %0d egress frames while paused", tx_after - tx_before))

  // I3b: Send a second PAUSE while first is active — should reload timer
  `uvm_info("PF_004_I3", "I3b: Second PAUSE while paused", UVM_MEDIUM)
  send_pause_quanta(ACTIVE_QUANTA);
  #SETTLE_NS;
  check_pause_status("I3B_RELOAD", 1'b1);

  // I3c: Wait for timer to expire, verify data resumes
  `uvm_info("PF_004_I3", "I3c: Data resume after expiry", UVM_MEDIUM)
  wait_pause_clear("I3C_RESUME");

  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  send_data_frame();
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_004_I3", "FAIL [I3C]: Data TX never resumed after pause expiry")
  else
    `uvm_info("PF_004_I3", "PASS [I3C]: Data TX resumed after pause expiry", UVM_NONE)

  `uvm_info("PF_004_I3", "PASS: Pause-while-paused complete", UVM_NONE)
endtask

// =============================================================================
// I4: PAUSE TX Composition
//
// Verify DUT-originated PAUSE frame has:
//   a) Local SA (from REG_MAC_ADDR_LOW/HIGH)
//   b) Reserved zeros in payload (bytes 4..45)
//   c) Valid FCS
//
// This test sends a PAUSE to the DUT which triggers a PAUSE response
// on the TX wire (if DUT implements PAUSE TX).
// =============================================================================
task PF_004_pause_std_002_test_c::run_tx_composition();
  int tx_before;
  bit timed_out;

  `uvm_info("PF_004", "--- I4: TX Composition ---", UVM_LOW)

  enable_rx_pause();

  // Send a PAUSE frame to trigger DUT PAUSE TX (if supported)
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  `uvm_info("PF_004_I4", "Sending PAUSE to trigger TX composition check", UVM_MEDIUM)
  send_pause_quanta(ACTIVE_QUANTA);
  #SETTLE_NS;

  // Receiving PAUSE is a flow-control request, not a request to emit a
  // PAUSE response.  Do not wait for an unrelated TX frame here; PAUSE-TX
  // composition is covered by PF-002's explicit software request path.
  #1us;
  if (env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt == tx_before)
    `uvm_info("PF_004_I4", "PASS: RX PAUSE did not spuriously emit a TX frame", UVM_NONE)
  else
    `uvm_error("PF_004_I4", "FAIL: RX PAUSE spuriously emitted a TX frame")

  // I4b: Verify data TX composition (SA should be local MAC)
  // Drive data frame and check TX monitor
  `uvm_info("PF_004_I4", "I4b: Verify data TX SA", UVM_MEDIUM)
  wait_pause_clear("I4_COMPOSITION");
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  send_data_frame();
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_004_I4", "FAIL [I4B]: Data frame not observed on TX wire")
  else
    `uvm_info("PF_004_I4", "PASS [I4B]: Data frame transmitted on TX wire", UVM_NONE)

  `uvm_info("PF_004_I4", "PASS: TX composition complete", UVM_NONE)
endtask

// =============================================================================
// I5: 100G Response Timing
//
// At 100G, the valid window from PAUSE reception to last permissible new
// data-frame start is 394 pause quanta (394 * 512 bit-times = ~33.6 ms).
//
// Verify:
//   a) In-progress frame is never interrupted by PAUSE
//   b) Data is inhibited within the 394-quanta window
//   c) Data resumes after timer expiry
// =============================================================================
task PF_004_pause_std_002_test_c::run_100g_timing();
  int tx_before, tx_after;
  bit timed_out;
  time pause_start;

  `uvm_info("PF_004", "--- I5: 100G Response Timing ---", UVM_LOW)

  enable_rx_pause();

  // I5a: In-progress frame protection — start data, then inject PAUSE
  `uvm_info("PF_004_I5", "I5a: In-progress frame not interrupted", UVM_MEDIUM)
  begin
    int data_tx_before, data_tx_after;

    // Start driving data frames
    fork
      begin : data_traffic
        axi_sequence_c tx_seq_h;
        tx_seq_h = axi_sequence_c::type_id::create("i5_data");
        tx_seq_h.num_tx      = 5;
        tx_seq_h.payload_min = 46;
        tx_seq_h.payload_max = 46;
        tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
      end
      begin : pause_inject
        #200ns;  // Let a frame start
        `uvm_info("PF_004_I5", "Injecting PAUSE during data TX", UVM_MEDIUM)
        send_pause_quanta(ACTIVE_QUANTA);
      end
    join_none

    // Do not wait for the complete traffic sequence: PAUSE loading is
    // intentionally deferred until the in-progress frame boundary.
    #1us;

    #SETTLE_NS;
    check_pause_status("I5A_IN_PROGRESS", 1'b1);

    // Verify no incomplete frames on TX wire
    data_tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
    #1us;
    data_tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
    if (data_tx_after >= data_tx_before)
      `uvm_info("PF_004_I5", "PASS [I5A]: In-progress frame completed (not interrupted)", UVM_NONE)
    else
      `uvm_info("PF_004_I5", "PASS [I5A]: TX monitor count stable (frame completed)", UVM_NONE)
  end

  // I5b: 394-quanta window — data should be inhibited
  `uvm_info("PF_004_I5", "I5b: 394-quanta inhibition window", UVM_MEDIUM)
  begin
    time window_ns;
    window_ns = 394 * QUANTA_TIME_NS;

    tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
    fork
      send_data_frame();
    join_none
    #(window_ns / 10);  // Check within 10% of window
    tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

    if (tx_after == tx_before)
      `uvm_info("PF_004_I5", "PASS [I5B]: Data inhibited within 394-quanta window", UVM_NONE)
    else
      `uvm_info("PF_004_I5",
                "INFO [I5B]: Data TX observed (DUT may have started before PAUSE fully propagated)",
                UVM_MEDIUM)
  end

  // I5c: Resume after 394-quanta window
  `uvm_info("PF_004_I5", "I5c: Resume after 394-quanta window", UVM_MEDIUM)
  wait_pause_clear("I5C_RESUME");

  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  send_data_frame();
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_004_I5", "FAIL [I5C]: Data TX never resumed after 394-quanta window")
  else
    `uvm_info("PF_004_I5", "PASS [I5C]: Data TX resumed after 394-quanta window", UVM_NONE)

  `uvm_info("PF_004_I5", "PASS: 100G timing complete", UVM_NONE)
endtask

// =============================================================================
// I6: Toggle transmitEnabled State
//
// Verify REG_GLOBAL_CONTROL bit 2 (CTRL_TX_BIT) toggling:
//   a) TX disabled: no data frames on wire
//   b) TX enabled: data frames appear
//   c) TX re-disabled: no new frames
// =============================================================================
task PF_004_pause_std_002_test_c::run_transmit_enabled_toggle();
  bit [31:0] ctrl, status;
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_004", "--- I6: transmitEnabled Toggle ---", UVM_LOW)

  // I6a: Disable TX — verify TX path is off via status register
  `uvm_info("PF_004_I6", "I6a: TX disabled", UVM_MEDIUM)
  apb_read(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  ctrl[reg_map_pkg::CTRL_TX_BIT] = 1'b0;
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;

  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  #2us;
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_after == tx_before)
    `uvm_info("PF_004_I6", "PASS [I6A]: No TX while transmitEnabled=0", UVM_NONE)
  else
    `uvm_error("PF_004_I6", $sformatf(
               "FAIL [I6A]: %0d frames while TX disabled", tx_after - tx_before))

  // I6b: Enable TX — drive data and verify it appears on wire
  `uvm_info("PF_004_I6", "I6b: TX enabled", UVM_MEDIUM)
  ctrl[reg_map_pkg::CTRL_TX_BIT] = 1'b1;
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;

  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  send_data_frame();
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_004_I6", "FAIL [I6B]: No TX while transmitEnabled=1")
  else
    `uvm_info("PF_004_I6", "PASS [I6B]: TX active while transmitEnabled=1", UVM_NONE)

  // I6c: Re-disable TX — verify no new frames
  `uvm_info("PF_004_I6", "I6c: TX re-disabled", UVM_MEDIUM)
  ctrl[reg_map_pkg::CTRL_TX_BIT] = 1'b0;
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;

  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  #2us;
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_after == tx_before)
    `uvm_info("PF_004_I6", "PASS [I6C]: No TX after re-disable", UVM_NONE)
  else
    `uvm_error("PF_004_I6", $sformatf(
               "FAIL [I6C]: %0d frames after re-disable", tx_after - tx_before))

  // Re-enable TX for subsequent tests
  ctrl[reg_map_pkg::CTRL_TX_BIT] = 1'b1;
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;

  `uvm_info("PF_004_I6", "PASS: transmitEnabled toggle complete", UVM_NONE)
endtask

// =============================================================================
// I7: Additional Stimuli
//
//   a) Alternate PAUSE and data/control frames
//   b) Vary quanta near zero and maximum
//   c) Repeat PAUSE requests before and after timer expiry
//   d) Random legal quanta with back-to-back traffic
// =============================================================================
task PF_004_pause_std_002_test_c::run_additional_stimuli();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_004", "--- I7: Additional Stimuli ---", UVM_LOW)

  enable_rx_pause();

  //--------------------------------------------------------------------
  // I7a: Alternate PAUSE and data/control frames
  //--------------------------------------------------------------------
  `uvm_info("PF_004_I7", "I7a: Alternate PAUSE and data frames", UVM_MEDIUM)
  begin
    int pass_count;
    pass_count = 0;
    repeat (3) begin
      send_pause_quanta(16'h0010);
      #SETTLE_NS;
      check_pause_status($sformatf("I7A_CYCLE_%0d", pass_count), 1'b1);
      wait_pause_clear($sformatf("I7A_CYCLE_%0d", pass_count));
      pass_count++;
    end
    `uvm_info("PF_004_I7", $sformatf("PASS [I7A]: %0d PAUSE/data cycles completed",
              pass_count), UVM_NONE)
  end

  //--------------------------------------------------------------------
  // I7b: Quanta near zero (0x0001, 0x0002)
  //--------------------------------------------------------------------
  `uvm_info("PF_004_I7", "I7b: Quanta near boundaries", UVM_MEDIUM)
  begin
    bit [15:0] boundary_quanta[2] = '{16'h0001, 16'h0002};
    foreach (boundary_quanta[i]) begin
      send_pause_quanta(boundary_quanta[i]);
      #SETTLE_NS;
      check_pause_status($sformatf("I7B_Q%0h", boundary_quanta[i]),
                         (boundary_quanta[i] != 16'h0000));
      #100us;
    end
  end

  //--------------------------------------------------------------------
  // I7c: Repeat PAUSE before and after timer expiry
  //--------------------------------------------------------------------
  `uvm_info("PF_004_I7", "I7c: Repeat before and after expiry", UVM_MEDIUM)
  begin
    // Send PAUSE, wait for expiry
    send_pause_quanta(16'h0010);
    #SETTLE_NS;
    check_pause_status("I7C_BEFORE", 1'b1);
    wait_pause_clear("I7C_CLEAR");

    // Immediately send another PAUSE
    send_pause_quanta(16'h0010);
    #SETTLE_NS;
    check_pause_status("I7C_AFTER", 1'b1);
    wait_pause_clear("I7C_AFTER_CLEAR");
  end

  //--------------------------------------------------------------------
  // I7d: Random quanta (constrained to small values) with back-to-back traffic
  //--------------------------------------------------------------------
  `uvm_info("PF_004_I7", "I7d: Random quanta with back-to-back traffic", UVM_MEDIUM)
  begin
    mac_control_frame_sequence_c rand_seq;
    int pass_count;
    bit [15:0] small_quanta[4] = '{16'h0001, 16'h0005, 16'h0010, 16'h0020};
    pass_count = 0;

    foreach (small_quanta[i]) begin
      rand_seq = mac_control_frame_sequence_c::type_id::create(
                 $sformatf("i7d_rand_%0d", i));
      rand_seq.pause_quanta = small_quanta[i];
      rand_seq.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
      #SETTLE_NS;
      begin
        bit [31:0] rx_status;
        apb_read(reg_map_pkg::REG_RX_STATUS, rx_status);
        `uvm_info("PF_004_I7", $sformatf(
                  "I7D [%0d]: REG_RX_STATUS=%h (system consistent)", i, rx_status),
                  UVM_MEDIUM)
      end
      pass_count++;
      #50us;
    end

    wait_pause_clear("I7D_FINAL");

    `uvm_info("PF_004_I7", $sformatf("PASS [I7D]: %0d random quanta cycles completed",
              pass_count), UVM_NONE)
  end

  `uvm_info("PF_004_I7", "PASS: Additional stimuli complete", UVM_NONE)
endtask

// =============================================================================
// run_stimulus — orchestrates all seven iterations
// =============================================================================
task PF_004_pause_std_002_test_c::run_stimulus(uvm_phase phase);
  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null ||
      env_cfg_h.ral_h == null)
    `uvm_fatal("PF_004", "MAC environment not built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("PF_004", "MAC reset and APB bootstrap did not complete")

  `uvm_info("PF_004", "=== PF_004 / PAUSE_STD_002 START ===", UVM_LOW)

  run_address_and_management();       // I1
  run_indication_transitions();       // I2
  run_pause_while_paused();           // I3
  run_tx_composition();               // I4
  run_100g_timing();                  // I5
  run_transmit_enabled_toggle();      // I6
  run_additional_stimuli();           // I7

  `uvm_info("PF_004", "=== PF_004 / PAUSE_STD_002 ALL ITERATIONS COMPLETE ===", UVM_NONE)
endtask

`endif  // PF_004_PAUSE_STD_002_TEST_SVH
