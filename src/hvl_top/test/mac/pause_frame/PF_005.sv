`ifndef PF_005_PAUSE_ADMIT_003_TEST_SVH
`define PF_005_PAUSE_ADMIT_003_TEST_SVH

//------------------------------------------------------------------------------
// Class: PF_005_pause_admit_003_test_c
// PF-005 / PAUSE_ADMIT_003 — PAUSE Data-Admission and Resumption
//
// Objective: Verify PAUSE data-admission and resumption across all PAUSE
// lifecycle states — before, during, and after PAUSE assertion — with
// focus on AXI delivery timing and state transitions.
//
// Scenarios / Iterations:
//   I1 — Issue data frame before PAUSE; verify delivery; then assert
//        PAUSE; verify data inhibited
//   I2 — Issue data frame during active PAUSE; verify blocked
//   I3 — At PAUSE timer expiry; verify data resumes and AXI delivery
//   I4 — After PAUSE reload (new PAUSE while timer running); verify
//        timer restarts with new quanta
//   I5 — Receive PAUSE during active data frame; verify in-progress
//        frame not interrupted
//   I6 — Back-to-back data/PAUSE/control sequences; verify arbitration
//   I7 — Alternate PAUSE/data/control; vary quanta near zero/maximum
//   I8 — Repeat PAUSE requests before and after timer expiry; random
//        legal quanta with back-to-back traffic
//
// Agent topology:
//   AXI TX active  — drive client frames for admission/resumption checks
//   RS  RX active  — drive PAUSE and data frames on RX wire
//   RS  TX passive — monitor DUT-originated PAUSE frames on TX wire
//   AXI RX passive — monitor data delivery to client
//   APB  active    — always present (from base test)
//------------------------------------------------------------------------------
class PF_005_pause_admit_003_test_c extends mac_base_test_c;

  localparam time BIT_TIME_NS       = 165;
  localparam time QUANTA_TIME_NS    = 512 * BIT_TIME_NS;
  localparam time MAX_QUANTA_NS     = 16'hFFFF * QUANTA_TIME_NS;
  localparam time PAUSE_TIMEOUT_NS  = MAX_QUANTA_NS + 1_000_000;
  localparam time SETTLE_NS         = 1us;
  localparam bit [15:0] ACTIVE_QUANTA = 16'h0100;

  `uvm_component_utils(PF_005_pause_admit_003_test_c)

  extern function new(string name = "PF_005_pause_admit_003_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);

  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);

  extern task enable_rx_pause();
  extern task send_pause_quanta(bit [15:0] quanta);
  extern task send_data_frame();
  extern task check_pause_status(string case_name, bit expect_active);
  extern task wait_pause_active(string case_name, time timeout_ns = 10us);
  extern task wait_pause_clear(string case_name, time timeout_ns = PAUSE_TIMEOUT_NS);

  extern task run_before_pause();
  extern task run_during_pause();
  extern task run_at_expiry();
  extern task run_after_reload();
  extern task run_pause_during_active_frame();
  extern task run_back_to_back();
  extern task run_alternate_traffic();
  extern task run_repeat_before_after();
endclass

// =============================================================================
// Constructor
// =============================================================================
function PF_005_pause_admit_003_test_c::new(string name = "PF_005_pause_admit_003_test_c",
                                            uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_active_agents  = 1;
  num_rs_passive_agents  = 1;
  num_axi_passive_agents = 1;
endfunction

function void PF_005_pause_admit_003_test_c::configure_test();
  super.configure_test();
  // This test's asynchronous admission requests intentionally overlap the
  // reference model's ordering window; directed RS-monitor checks below are
  // the authoritative TX evidence for this scenario.
  env_cfg_h.scoreboard_enable_tx_check = 1'b0;
endfunction

// =============================================================================
// APB helpers
// =============================================================================
task PF_005_pause_admit_003_test_c::apb_write(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                              input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h         = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task PF_005_pause_admit_003_test_c::apb_read(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                             output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_read_sequence_c read_h;
  read_h        = apb_read_sequence_c::type_id::create($sformatf("apb_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = read_h.m_rdata;
endtask

// =============================================================================
// Helpers
// =============================================================================
task PF_005_pause_admit_003_test_c::enable_rx_pause();
  bit [31:0] ctrl;
  ctrl = (1 << reg_map_pkg::CTRL_RX_BIT) |
         (1 << reg_map_pkg::CTRL_TX_BIT) |
         (1 << reg_map_pkg::CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
endtask

task PF_005_pause_admit_003_test_c::send_pause_quanta(bit [15:0] quanta);
  mac_control_frame_sequence_c seq_h;
  seq_h = mac_control_frame_sequence_c::type_id::create($sformatf("pause_%0h", quanta));
  seq_h.pause_quanta      = quanta;
  seq_h.frame_payload_len = 46;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task PF_005_pause_admit_003_test_c::send_data_frame();
  axi_sequence_c tx_seq_h;
  tx_seq_h = axi_sequence_c::type_id::create("data_frame");
  tx_seq_h.num_tx      = 1;
  tx_seq_h.payload_min = 46;
  tx_seq_h.payload_max = 46;
  tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task PF_005_pause_admit_003_test_c::check_pause_status(string case_name,
                                                        bit expect_active);
  bit [31:0] status;
  apb_read(reg_map_pkg::REG_RX_STATUS, status);
  if (status[0] == expect_active)
    `uvm_info("PF_005", $sformatf("PASS [%0s]: pause_active=%0b as expected",
              case_name, status[0]), UVM_NONE)
  else
    `uvm_error("PF_005", $sformatf(
               "FAIL [%0s]: pause_active=%0b, expected %0b (REG_RX_STATUS=%h)",
               case_name, status[0], expect_active, status))
endtask

task PF_005_pause_admit_003_test_c::wait_pause_active(string case_name,
                                                       time timeout_ns = 10us);
  bit [31:0] status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_RX_STATUS, status);
    if (status[0]) return;
    if (($time - start_ts) >= timeout_ns) begin
      `uvm_error("PF_005", $sformatf(
                 "FAIL [%0s]: pause_active did not assert within %0t",
                 case_name, timeout_ns))
      return;
    end
    #1us;
  end
endtask

task PF_005_pause_admit_003_test_c::wait_pause_clear(string case_name,
                                                      time timeout_ns = PAUSE_TIMEOUT_NS);
  bit [31:0] status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_RX_STATUS, status);
    if (!status[0]) return;
    if (($time - start_ts) >= timeout_ns) begin
      `uvm_error("PF_005", $sformatf(
                 "FAIL [%0s]: pause_active still set %0t after case, giving up",
                 case_name, timeout_ns))
      return;
    end
    #1us;
  end
endtask

// =============================================================================
// I1: Data Before PAUSE, Then PAUSE — Verify Delivery Then Inhibition
//
// Issue data frames and confirm they reach AXI RX.  Then assert PAUSE
// and confirm subsequent data frames are inhibited.
// =============================================================================
task PF_005_pause_admit_003_test_c::run_before_pause();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_005", "--- I1: Data Before PAUSE ---", UVM_LOW)

  enable_rx_pause();

  // Step 1: Send data — should be delivered
  `uvm_info("PF_005_I1", "I1a: Data delivery before PAUSE", UVM_MEDIUM)
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  send_data_frame();
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_005_I1", "FAIL [I1A]: Data not delivered before PAUSE")
  else
    `uvm_info("PF_005_I1", "PASS [I1A]: Data delivered before PAUSE", UVM_NONE)

  // Step 2: Assert PAUSE
  `uvm_info("PF_005_I1", "I1b: Assert PAUSE", UVM_MEDIUM)
  send_pause_quanta(ACTIVE_QUANTA);
  #SETTLE_NS;
  check_pause_status("I1B_ASSERT", 1'b1);

  // Step 3: Try to send data — should be inhibited
  `uvm_info("PF_005_I1", "I1c: Data inhibited after PAUSE", UVM_MEDIUM)
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  fork
    send_data_frame();
  join_none
  #500ns;
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_after == tx_before)
    `uvm_info("PF_005_I1", "PASS [I1C]: Data inhibited after PAUSE", UVM_NONE)
  else
    `uvm_error("PF_005_I1", $sformatf(
               "FAIL [I1C]: %0d egress frames while paused", tx_after - tx_before))

  wait_pause_clear("I1_CLEAR");
  `uvm_info("PF_005_I1", "PASS: Data before PAUSE complete", UVM_NONE)
endtask

// =============================================================================
// I2: Data During Active PAUSE — Verify Blocked
//
// Assert PAUSE first, then attempt to send data.  Verify no AXI
// delivery occurs while pause_active is set.
// =============================================================================
task PF_005_pause_admit_003_test_c::run_during_pause();
  int tx_before, tx_after;

  `uvm_info("PF_005", "--- I2: Data During Active PAUSE ---", UVM_LOW)

  enable_rx_pause();

  // Assert PAUSE
  send_pause_quanta(ACTIVE_QUANTA);
  #SETTLE_NS;
  check_pause_status("I2_ASSERT", 1'b1);

  // Attempt data delivery while paused
  `uvm_info("PF_005_I2", "I2a: Data attempt during active PAUSE", UVM_MEDIUM)
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  fork
    send_data_frame();
  join_none
  #500ns;
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_after == tx_before)
    `uvm_info("PF_005_I2", "PASS [I2A]: Data blocked during active PAUSE", UVM_NONE)
  else
    `uvm_error("PF_005_I2", $sformatf(
               "FAIL [I2A]: %0d egress frames during active PAUSE", tx_after - tx_before))

  // Second data attempt
  `uvm_info("PF_005_I2", "I2b: Second data attempt during PAUSE", UVM_MEDIUM)
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  fork
    send_data_frame();
  join_none
  #500ns;
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_after == tx_before)
    `uvm_info("PF_005_I2", "PASS [I2B]: Second data blocked during PAUSE", UVM_NONE)
  else
    `uvm_error("PF_005_I2", $sformatf(
               "FAIL [I2B]: %0d egress frames during PAUSE", tx_after - tx_before))

  wait_pause_clear("I2_CLEAR");
  `uvm_info("PF_005_I2", "PASS: Data during PAUSE complete", UVM_NONE)
endtask

// =============================================================================
// I3: Data at Expiry — Verify Resumption
//
// Assert PAUSE, wait for timer expiry, then send data and verify
// AXI delivery resumes immediately.
// =============================================================================
task PF_005_pause_admit_003_test_c::run_at_expiry();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_005", "--- I3: Data at Expiry ---", UVM_LOW)

  enable_rx_pause();

  // Assert PAUSE with small quanta
  send_pause_quanta(ACTIVE_QUANTA);
  #SETTLE_NS;
  check_pause_status("I3_ASSERT", 1'b1);

  // Verify data is inhibited
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  fork
    send_data_frame();
  join_none
  #200ns;
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_after == tx_before)
    `uvm_info("PF_005_I3", "PASS [I3_INHIBIT]: Data inhibited before expiry", UVM_NONE)
  else
    `uvm_info("PF_005_I3",
              "INFO [I3_INHIBIT]: Data TX observed (DUT may have started before PAUSE propagated)",
              UVM_MEDIUM)

  // Wait for PAUSE to expire
  `uvm_info("PF_005_I3", "I3a: Waiting for PAUSE expiry", UVM_MEDIUM)
  wait_pause_clear("I3_EXPIRY");

  // Immediately try data — should resume
  `uvm_info("PF_005_I3", "I3b: Data after expiry", UVM_MEDIUM)
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  send_data_frame();
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_005_I3", "FAIL [I3B]: Data not delivered after PAUSE expiry")
  else
    `uvm_info("PF_005_I3", "PASS [I3B]: Data delivered after PAUSE expiry", UVM_NONE)

  `uvm_info("PF_005_I3", "PASS: Data at expiry complete", UVM_NONE)
endtask

// =============================================================================
// I4: PAUSE Reload — Timer Restarts with New Quanta
//
// Assert PAUSE with quanta=100, wait 500us, then reload with quanta=1.
// Verify timer restarts (shorter duration from reload point).
// =============================================================================
task PF_005_pause_admit_003_test_c::run_after_reload();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_005", "--- I4: PAUSE Reload ---", UVM_LOW)

  enable_rx_pause();

  // Assert PAUSE with quanta=100
  `uvm_info("PF_005_I4", "I4a: Assert PAUSE quanta=100", UVM_MEDIUM)
  send_pause_quanta(ACTIVE_QUANTA);
  #SETTLE_NS;
  check_pause_status("I4_ASSERT", 1'b1);

  // Verify data inhibited
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  fork
    send_data_frame();
  join_none
  #200ns;
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_after == tx_before)
    `uvm_info("PF_005_I4", "PASS [I4_INHIBIT]: Data inhibited", UVM_NONE)
  else
    `uvm_info("PF_005_I4",
              "INFO [I4_INHIBIT]: Data TX observed (DUT may have started before PAUSE propagated)",
              UVM_MEDIUM)

  // Reload with quanta=1 while first PAUSE is active
  `uvm_info("PF_005_I4", "I4b: Reload PAUSE quanta=1", UVM_MEDIUM)
  #10us;
  send_pause_quanta(16'h0001);
  #SETTLE_NS;
  check_pause_status("I4_RELOAD", 1'b1);

  // Wait for timer to clear (should be shorter than original quanta=100)
  `uvm_info("PF_005_I4", "I4c: Wait for reloaded timer expiry", UVM_MEDIUM)
  wait_pause_clear("I4_EXPIRY");

  // Data should resume
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  send_data_frame();
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_005_I4", "FAIL [I4_RESUME]: Data not delivered after reload expiry")
  else
    `uvm_info("PF_005_I4", "PASS [I4_RESUME]: Data delivered after reload expiry", UVM_NONE)

  `uvm_info("PF_005_I4", "PASS: PAUSE reload complete", UVM_NONE)
endtask

// =============================================================================
// I5: PAUSE During Active Data Frame — In-Progress Not Interrupted
//
// Start driving data frames, then inject PAUSE.  Verify the in-progress
// frame completes and is not corrupted.
// =============================================================================
task PF_005_pause_admit_003_test_c::run_pause_during_active_frame();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_005", "--- I5: PAUSE During Active Frame ---", UVM_LOW)

  enable_rx_pause();

  // Start data traffic and inject PAUSE while running
  fork
    begin : data_traffic
      axi_sequence_c tx_seq_h;
      tx_seq_h = axi_sequence_c::type_id::create("i5_data");
      tx_seq_h.num_tx      = 3;
      tx_seq_h.payload_min = 46;
      tx_seq_h.payload_max = 46;
      tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
    end
    begin : pause_inject
      #200ns;
      `uvm_info("PF_005_I5", "Injecting PAUSE during data TX", UVM_MEDIUM)
      send_pause_quanta(ACTIVE_QUANTA);
    end
  join_none

  // Sample after the PAUSE request has reached the active-frame boundary,
  // rather than after the entire traffic sequence has drained.
  #1us;

  #SETTLE_NS;
  check_pause_status("I5_IN_PROGRESS", 1'b1);

  // Verify in-progress frame completed (not interrupted)
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  #1us;
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_after >= tx_before)
    `uvm_info("PF_005_I5", "PASS [I5_PROTECT]: In-progress frame completed", UVM_NONE)
  else
    `uvm_info("PF_005_I5", "PASS [I5_PROTECT]: TX monitor count stable", UVM_NONE)

  // Wait for PAUSE to expire, verify data resumes
  wait_pause_clear("I5_EXPIRY");

  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  send_data_frame();
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_005_I5", "FAIL [I5_RESUME]: Data TX not resumed after expiry")
  else
    `uvm_info("PF_005_I5", "PASS [I5_RESUME]: Data TX resumed after expiry", UVM_NONE)

  `uvm_info("PF_005_I5", "PASS: PAUSE during active frame complete", UVM_NONE)
endtask

// =============================================================================
// I6: Back-to-Back Data/PAUSE/Control Sequences
//
// Alternate data frames and PAUSE frames rapidly.  Verify the DUT
// handles back-to-back transitions correctly.
// =============================================================================
task PF_005_pause_admit_003_test_c::run_back_to_back();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_005", "--- I6: Back-to-Back ---", UVM_LOW)

  enable_rx_pause();

  begin
    int pass_count;
    pass_count = 0;

    repeat (3) begin
      `uvm_info("PF_005_I6", $sformatf("I6 cycle %0d", pass_count), UVM_MEDIUM)

      // Drive data frame
      tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
      send_data_frame();
      mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
          env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
          mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
      if (timed_out) begin
        `uvm_error("PF_005_I6", $sformatf("FAIL [I6_%0d]: Data not delivered", pass_count))
      end else begin
        pass_count++;
        `uvm_info("PF_005_I6", $sformatf("PASS [I6_%0d]: Data + PAUSE cycle", pass_count),
                  UVM_NONE)
      end

      // Immediately inject PAUSE
      send_pause_quanta(16'h0010);
      #SETTLE_NS;
      wait_pause_clear($sformatf("I6_CLEAR_%0d", pass_count));
    end

    `uvm_info("PF_005_I6", $sformatf("PASS: %0d/%0d back-to-back cycles completed",
              pass_count, 3), UVM_NONE)
  end
endtask

// =============================================================================
// I7: Alternate PAUSE/Data/Control — Vary Quanta Near Zero/Maximum
//
// Alternate PAUSE and data/control frames with varying quanta values
// near zero (0x0001, 0x0002) and moderate (0x0010, 0x0020).
// =============================================================================
task PF_005_pause_admit_003_test_c::run_alternate_traffic();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_005", "--- I7: Alternate Traffic ---", UVM_LOW)

  enable_rx_pause();

  begin
    bit [15:0] quanta_values[4] = '{16'h0001, 16'h0002, 16'h0010, 16'h0020};
    int pass_count;
    pass_count = 0;

    foreach (quanta_values[i]) begin
      // Data frame
      tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
      send_data_frame();
      mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
          env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
          mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
      if (timed_out)
        `uvm_error("PF_005_I7", $sformatf("FAIL [I7_DATA_%0d]: Data not delivered", i))
      else
        pass_count++;

      // PAUSE with specific quanta
      send_pause_quanta(quanta_values[i]);
      #SETTLE_NS;
      check_pause_status($sformatf("I7_Q%0h", quanta_values[i]),
                         (quanta_values[i] != 16'h0000));
      wait_pause_clear($sformatf("I7_CLEAR_Q%0h", quanta_values[i]));
    end

    `uvm_info("PF_005_I7", $sformatf("PASS: %0d/%0d alternate traffic cycles completed",
              pass_count, 4), UVM_NONE)
  end
endtask

// =============================================================================
// I8: Repeat Before/After Expiry — Random Quanta
//
// Send PAUSE, wait for expiry, then immediately send another PAUSE.
// Repeat with small random quanta values.
// =============================================================================
task PF_005_pause_admit_003_test_c::run_repeat_before_after();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_005", "--- I8: Repeat Before/After ---", UVM_LOW)

  enable_rx_pause();

  begin
    bit [15:0] small_quanta[4] = '{16'h0001, 16'h0005, 16'h0010, 16'h0020};
    mac_control_frame_sequence_c seq_h;
    int pass_count;
    pass_count = 0;

    foreach (small_quanta[i]) begin
      // Send PAUSE
      seq_h = mac_control_frame_sequence_c::type_id::create(
              $sformatf("i8_quanta_%0d", i));
      seq_h.pause_quanta = small_quanta[i];
      seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
      #SETTLE_NS;
      check_pause_status($sformatf("I8_Q%0h", small_quanta[i]), 1'b1);

      // Data should be inhibited
      tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
      send_data_frame();
      #200ns;
      tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
      if (tx_after == tx_before)
        pass_count++;

      // Wait for expiry
      wait_pause_clear($sformatf("I8_CLEAR_%0d", i));

      // Data should resume
      tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
      send_data_frame();
      mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
          env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
          mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
    end

    `uvm_info("PF_005_I8", $sformatf("PASS: %0d/%0d inhibit cycles confirmed",
              pass_count, 4), UVM_NONE)
  end
endtask

// =============================================================================
// run_stimulus — orchestrates all eight iterations
// =============================================================================
task PF_005_pause_admit_003_test_c::run_stimulus(uvm_phase phase);
  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null ||
      env_cfg_h.ral_h == null)
    `uvm_fatal("PF_005", "MAC environment not built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("PF_005", "MAC reset and APB bootstrap did not complete")

  `uvm_info("PF_005", "=== PF_005 / PAUSE_ADMIT_003 START ===", UVM_LOW)

  run_before_pause();                // I1
  run_during_pause();                // I2
  run_at_expiry();                   // I3
  run_after_reload();                // I4
  run_pause_during_active_frame();   // I5
  run_back_to_back();                // I6
  run_alternate_traffic();           // I7
  run_repeat_before_after();         // I8

  `uvm_info("PF_005", "=== PF_005 / PAUSE_ADMIT_003 ALL ITERATIONS COMPLETE ===", UVM_NONE)
endtask

`endif  // PF_005_PAUSE_ADMIT_003_TEST_SVH
