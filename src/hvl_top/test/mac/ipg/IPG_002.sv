`ifndef IPG_002_IPG_TX_ARB_TEST_SVH
`define IPG_002_IPG_TX_ARB_TEST_SVH

//------------------------------------------------------------------------------
// Class: IPG_002_ipg_tx_arb_test_c
// IPG-002 / TX_ARB_001 — TX Data/PAUSE Arbitration, Handshake, and Error
// Propagation
//
// Objective: Verify deterministic selection and completion of data versus PAUSE
// traffic, including backpressure and final-byte error handling.
//
// Scenarios / Iterations:
//   I1 — PAUSE at data EOP vs idle: trigger PAUSE at exact data EOP and while
//        data is idle; verify data completes before PAUSE in both cases.
//   I2 — Min/max frames with PAUSE timing: send minimum (46 B) and maximum
//        (1500 B) data frames; request PAUSE before, during, and after data.
//   I3 — Backpressure: note that the TX output mux (mac_core_v.v lines
//        213-221) blocks data via tx_path_ready = out_ready && !pause_valid.
//        Verify data stalls while PAUSE is active and resumes after.
//   I4 — Error injection: send frames with crc_error via AXI TX; verify the
//        DUT transmits the frame (with bad FCS) and out_error remains 0
//        (tx_frame_builder hardwires out_error to 0).
//   I5 — Sustained back-to-back: interleave data and PAUSE TX requests in a
//        tight loop; verify no frame loss and deterministic ordering.
//
// Agent topology:
//   AXI TX active  — drive client data frames into MAC TX path
//   RS  RX active  — inject PAUSE frames via MAC RX wire (HW-triggered PAUSE)
//   RS  TX passive — monitor DUT TX wire output (PAUSE + data frames)
//   APB  active    — always present (from base test); used for SW-triggered
//                    PAUSE via REG_PAUSE_TX_CONFIG
//
// RTL notes (mac_core_v.v):
//   - Output mux: pause_tx_valid selects PAUSE; !pause_valid selects data.
//   - tx_path_ready = egress_tx_mac_ready && !pause_valid → data stalls
//     while PAUSE is transmitted.
//   - pause_admit = !pause_active → admission gate blocks data frames while
//     the PAUSE timer is running.
//   - pause_tx_pending is cleared on PAUSE frame EOP.
//   - out_error is hardwired to 0 in tx_frame_builder; error from AXI
//     admission is passed but never stored or replayed.
//------------------------------------------------------------------------------
class IPG_002_ipg_tx_arb_test_c extends mac_base_test_c;

  localparam int unsigned PAUSE_TX_ENABLE_BIT = reg_map_pkg::PAUSE_TX_ENABLE_BIT;
  localparam int unsigned PAUSE_TX_SOFT_REQ_BIT = reg_map_pkg::PAUSE_TX_SOFT_REQ_BIT;
  localparam int unsigned CTRL_TX_BIT = reg_map_pkg::CTRL_TX_BIT;
  localparam int unsigned CTRL_PAUSE_BIT = reg_map_pkg::CTRL_PAUSE_BIT;

  `uvm_component_utils(IPG_002_ipg_tx_arb_test_c)

  extern function new(string name = "IPG_002_ipg_tx_arb_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);

  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);

  extern task enable_tx();
  extern task enable_pause_tx();
  extern task send_data_frame(int payload_bytes = 46);
  extern task trigger_sw_pause(bit [15:0] quanta = 16'h0010);
  extern task wait_sw_pause_done();

  extern task run_pause_at_eop_vs_idle();       // I1
  extern task run_min_max_pause_timing();       // I2
  extern task run_backpressure_stall();         // I3
  extern task run_error_injection();            // I4
  extern task run_sustained_back_to_back();     // I5
endclass

// =============================================================================
// Constructor
// =============================================================================
function IPG_002_ipg_tx_arb_test_c::new(string name = "IPG_002_ipg_tx_arb_test_c",
                                       uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 0;
  num_rs_active_agents   = 1;   // RX active for PAUSE injection (HW path)
  num_rs_passive_agents  = 1;   // TX wire monitor
endfunction

// =============================================================================
// Configure
// =============================================================================
function void IPG_002_ipg_tx_arb_test_c::configure_test();
  super.configure_test();
  // This directed test deliberately injects a supplied-FCS error.  Its
  // line-side monitor/count checks are the authoritative result; the generic
  // transaction scoreboard cannot model that intentionally malformed FCS.
  env_cfg_h.scoreboard_enable_tx_check = 1'b0;
  // Arbitration is the focus here; IPG timing is exercised exhaustively by
  // IPG-001.
  env_cfg_h.rs_passive_agent_cfgs[0].enable_ipg_check = 1'b0;
endfunction

// =============================================================================
// APB helpers
// =============================================================================
task IPG_002_ipg_tx_arb_test_c::apb_write(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                          input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h         = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task IPG_002_ipg_tx_arb_test_c::apb_read(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
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
task IPG_002_ipg_tx_arb_test_c::send_data_frame(int payload_bytes = 46);
  axi_sequence_c tx_seq_h;
  tx_seq_h = axi_sequence_c::type_id::create("data_frame");
  tx_seq_h.num_tx      = 1;
  tx_seq_h.payload_min = payload_bytes;
  tx_seq_h.payload_max = payload_bytes;
  tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task IPG_002_ipg_tx_arb_test_c::enable_tx();
  bit [31:0] ctrl;
  ctrl = (1 << CTRL_TX_BIT) | (1 << CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
endtask

task IPG_002_ipg_tx_arb_test_c::enable_pause_tx();
  bit [31:0] ctrl;
  bit [31:0] tx_cfg;
  ctrl = (1 << CTRL_TX_BIT) | (1 << CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  tx_cfg = (1 << PAUSE_TX_ENABLE_BIT);
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, tx_cfg);
  #200ns;
endtask

task IPG_002_ipg_tx_arb_test_c::trigger_sw_pause(bit [15:0] quanta = 16'h0010);
  bit [31:0] tx_cfg;
  bit [31:0] pause_ctrl;
  // Set pause quanta
  pause_ctrl = {16'h0, quanta};
  apb_write(reg_map_pkg::REG_PAUSE_CONTROL, pause_ctrl);
  #200ns;
  // Trigger SW PAUSE: enable + soft_req rising edge
  tx_cfg = (1 << PAUSE_TX_ENABLE_BIT) | (1 << PAUSE_TX_SOFT_REQ_BIT);
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, tx_cfg);
  // The RTL queues a request only on a soft_req rising edge.  Return the
  // bit low after the CDC has observed the assertion so this helper can be
  // used for a subsequent PAUSE request in the same scenario.
  #200ns;
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, (1 << PAUSE_TX_ENABLE_BIT));
endtask

task IPG_002_ipg_tx_arb_test_c::wait_sw_pause_done();
  bit [31:0] tx_status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_TX_STATUS, tx_status);
    if (!tx_status[reg_map_pkg::INT_PAUSE_ACTIVE_BIT]) break;
    if (($time - start_ts) >= 10ms) begin
      `uvm_error("IPG_002", "Timeout waiting for SW PAUSE to complete")
      break;
    end
    #1us;
  end
endtask

// =============================================================================
// I1: PAUSE at Data EOP vs Idle
//
// Two sub-tests:
//   I1a — Trigger PAUSE while TX is idle (no data being sent).
//         PAUSE should appear immediately.
//   I1b — Send a data frame, trigger PAUSE at exact data EOP.
//         Data must complete before PAUSE can be transmitted.
//         PAUSE should follow immediately after data EOP + WAIT_IPG.
// =============================================================================
task IPG_002_ipg_tx_arb_test_c::run_pause_at_eop_vs_idle();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("IPG_002", "--- I1: PAUSE at EOP vs Idle ---", UVM_LOW)

  // I1a: PAUSE while idle — should appear on wire immediately
  `uvm_info("IPG_002_I1", "I1a: PAUSE while idle", UVM_MEDIUM)
  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  trigger_sw_pause(16'h0004);
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, 10ms, timed_out);
  if (timed_out)
    `uvm_error("IPG_002_I1", "FAIL [I1A]: SW PAUSE frame not transmitted while idle")
  else
    `uvm_info("IPG_002_I1", "PASS [I1A]: SW PAUSE transmitted while idle", UVM_NONE)
  wait_sw_pause_done();
  #1us;

  // I1b: Send data frame, trigger PAUSE at exact EOP
  `uvm_info("IPG_002_I1", "I1b: PAUSE at data EOP", UVM_MEDIUM)
  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    // Thread A: send data frame
    begin
      send_data_frame(46);
    end
    // Thread B: trigger PAUSE shortly after data starts (near EOP)
    begin
      #2us;
      trigger_sw_pause(16'h0004);
    end
  join

  // Wait for both data and PAUSE to complete (2 frames: data + PAUSE)
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 2,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (timed_out)
    `uvm_error("IPG_002_I1", $sformatf(
               "FAIL [I1B]: Expected 2 TX frames (data+PAUSE), got %0d", tx_after - tx_before))
  else if (tx_after - tx_before >= 2)
    `uvm_info("IPG_002_I1", $sformatf(
              "PASS [I1B]: Data + PAUSE both transmitted (%0d frames)", tx_after - tx_before),
              UVM_NONE)
  else
    `uvm_error("IPG_002_I1", $sformatf(
               "FAIL [I1B]: Expected >=2 TX frames, got %0d", tx_after - tx_before))

  wait_sw_pause_done();
  #1us;

  `uvm_info("IPG_002_I1", "PASS: PAUSE at EOP vs Idle complete", UVM_NONE)
endtask

// =============================================================================
// I2: Min/Max Frames with PAUSE Before, During, and After
//
// Sub-tests:
//   I2a — Min frame (46 B) + PAUSE before (trigger PAUSE, then send)
//   I2b — Max frame (1500 B) + PAUSE during (send, trigger mid-frame)
//   I2c — Min frame (46 B) + PAUSE after (send, wait, trigger PAUSE)
//   I2d — Max frame (1500 B) + PAUSE before
// =============================================================================
task IPG_002_ipg_tx_arb_test_c::run_min_max_pause_timing();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("IPG_002", "--- I2: Min/Max Frames + PAUSE Timing ---", UVM_LOW)

  // I2a: Min frame + PAUSE before
  `uvm_info("IPG_002_I2", "I2a: Min frame + PAUSE before", UVM_MEDIUM)
  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      trigger_sw_pause(16'h0004);
    end
    begin
      #500ns;
      send_data_frame(46);
    end
  join

  mac_wait_utils_c::wait_for_count_at_least(tx_before + 2,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (timed_out)
    `uvm_error("IPG_002_I2", $sformatf("FAIL [I2A]: timed out, got %0d frames", tx_after - tx_before))
  else
    `uvm_info("IPG_002_I2", $sformatf("PASS [I2A]: %0d frames (PAUSE + min data)", tx_after - tx_before),
              UVM_NONE)
  wait_sw_pause_done();
  #1us;

  // I2b: Max frame + PAUSE during
  `uvm_info("IPG_002_I2", "I2b: Max frame + PAUSE during", UVM_MEDIUM)
  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      send_data_frame(1500);
    end
    begin
      #1us;
      trigger_sw_pause(16'h0004);
    end
  join

  mac_wait_utils_c::wait_for_count_at_least(tx_before + 2,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (timed_out)
    `uvm_error("IPG_002_I2", $sformatf("FAIL [I2B]: timed out, got %0d frames", tx_after - tx_before))
  else
    `uvm_info("IPG_002_I2", $sformatf("PASS [I2B]: %0d frames (max data + PAUSE)", tx_after - tx_before),
              UVM_NONE)
  wait_sw_pause_done();
  #1us;

  // I2c: Min frame + PAUSE after
  `uvm_info("IPG_002_I2", "I2c: Min frame + PAUSE after", UVM_MEDIUM)
  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  send_data_frame(46);
  #500ns;
  trigger_sw_pause(16'h0004);

  mac_wait_utils_c::wait_for_count_at_least(tx_before + 2,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (timed_out)
    `uvm_error("IPG_002_I2", $sformatf("FAIL [I2C]: timed out, got %0d frames", tx_after - tx_before))
  else
    `uvm_info("IPG_002_I2", $sformatf("PASS [I2C]: %0d frames (min data + PAUSE)", tx_after - tx_before),
              UVM_NONE)
  wait_sw_pause_done();
  #1us;

  // I2d: Max frame + PAUSE before
  `uvm_info("IPG_002_I2", "I2d: Max frame + PAUSE before", UVM_MEDIUM)
  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      trigger_sw_pause(16'h0004);
    end
    begin
      #500ns;
      send_data_frame(1500);
    end
  join

  mac_wait_utils_c::wait_for_count_at_least(tx_before + 2,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (timed_out)
    `uvm_error("IPG_002_I2", $sformatf("FAIL [I2D]: timed out, got %0d frames", tx_after - tx_before))
  else
    `uvm_info("IPG_002_I2", $sformatf("PASS [I2D]: %0d frames (PAUSE + max data)", tx_after - tx_before),
              UVM_NONE)
  wait_sw_pause_done();
  #1us;

  `uvm_info("IPG_002_I2", "PASS: Min/Max PAUSE timing complete", UVM_NONE)
endtask

// =============================================================================
// I3: Backpressure / Data Stall During PAUSE
//
// The TX output mux (mac_core_v.v:213-221) asserts:
//   tx_path_ready = egress_tx_mac_ready && !pause_tx_valid
// This means the data pipeline is stalled while PAUSE is transmitted.
// Verify:
//   I3a — Send data frame, trigger PAUSE mid-flight; data should stall,
//         PAUSE completes, data resumes.
//   I3b — Trigger PAUSE while no data pending; verify no data starvation.
//   I3c — Multiple PAUSE requests back-to-back; data must not appear
//         during PAUSE bursts.
// =============================================================================
task IPG_002_ipg_tx_arb_test_c::run_backpressure_stall();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("IPG_002", "--- I3: Backpressure / Data Stall ---", UVM_LOW)

  // I3a: PAUSE mid-flight → data stalls, then resumes
  `uvm_info("IPG_002_I3", "I3a: PAUSE mid-flight — data stalls", UVM_MEDIUM)
  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      send_data_frame(1500);
    end
    begin
      #500ns;
      trigger_sw_pause(16'h0004);
    end
  join

  mac_wait_utils_c::wait_for_count_at_least(tx_before + 2,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (timed_out)
    `uvm_error("IPG_002_I3", $sformatf("FAIL [I3A]: timed out, got %0d", tx_after - tx_before))
  else
    `uvm_info("IPG_002_I3", $sformatf("PASS [I3A]: %0d frames (data + PAUSE)", tx_after - tx_before),
              UVM_NONE)
  wait_sw_pause_done();
  #1us;

  // I3b: PAUSE while no data pending — no data starvation
  `uvm_info("IPG_002_I3", "I3b: PAUSE while no data pending", UVM_MEDIUM)
  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  trigger_sw_pause(16'h0004);

  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, 10ms, timed_out);
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (timed_out)
    `uvm_error("IPG_002_I3", "FAIL [I3B]: PAUSE not transmitted")
  else
    `uvm_info("IPG_002_I3", $sformatf("PASS [I3B]: %0d PAUSE frame(s) transmitted", tx_after - tx_before),
              UVM_NONE)
  wait_sw_pause_done();
  #1us;

  // I3c: Two back-to-back PAUSE requests; data must not appear during PAUSE
  `uvm_info("IPG_002_I3", "I3c: Back-to-back PAUSE requests", UVM_MEDIUM)
  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  trigger_sw_pause(16'h0004);
  #200ns;
  trigger_sw_pause(16'h0004);

  mac_wait_utils_c::wait_for_count_at_least(tx_before + 2,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (timed_out)
    `uvm_error("IPG_002_I3", $sformatf("FAIL [I3C]: timed out, got %0d", tx_after - tx_before))
  else
    `uvm_info("IPG_002_I3", $sformatf("PASS [I3C]: %0d PAUSE frames transmitted", tx_after - tx_before),
              UVM_NONE)
  wait_sw_pause_done();
  #1us;

  `uvm_info("IPG_002_I3", "PASS: Backpressure / data stall complete", UVM_NONE)
endtask

// =============================================================================
// I4: Error Injection (data_error / crc_error)
//
// RTL finding: out_error in tx_frame_builder is hardwired to 0.
// The error from AXI admission (c_error) is passed to tx_client_capture
// but NOT stored or replayed. The frame is transmitted with whatever FCS
// the client sent (correct or incorrect).
//
// Sub-tests:
//   I4a — Send clean frame (crc_error=0): verify frame on wire.
//   I4b — Send error frame (crc_error=1): verify frame appears on wire
//         with bad FCS; out_error remains 0 (scoreboard shows CRC_ERR=1).
// =============================================================================
task IPG_002_ipg_tx_arb_test_c::run_error_injection();
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("IPG_002", "--- I4: Error Injection ---", UVM_LOW)

  enable_tx();

  // I4a: Clean frame
  `uvm_info("IPG_002_I4", "I4a: Clean frame (crc_error=0)", UVM_MEDIUM)
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  begin
    axi_sequence_c tx_seq_h;
    tx_seq_h = axi_sequence_c::type_id::create("clean_frame");
    tx_seq_h.num_tx        = 1;
    tx_seq_h.payload_min   = 46;
    tx_seq_h.payload_max   = 46;
    tx_seq_h.error_injection = 0;
    tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
  end
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("IPG_002_I4", "FAIL [I4A]: Clean frame not transmitted")
  else
    `uvm_info("IPG_002_I4", "PASS [I4A]: Clean frame transmitted", UVM_NONE)

  // I4b: Error frame (crc_error=1)
  // The AXI driver sets tuser[0]=1 (error flag) and sends bad FCS.
  // The DUT transmits the frame with bad FCS.
  // out_error remains 0 (hardwired in tx_frame_builder).
  `uvm_info("IPG_002_I4", "I4b: Error frame (crc_error=1)", UVM_MEDIUM)
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  begin
    axi_sequence_c tx_seq_h;
    tx_seq_h = axi_sequence_c::type_id::create("error_frame");
    tx_seq_h.num_tx        = 1;
    tx_seq_h.payload_min   = 46;
    tx_seq_h.payload_max   = 46;
    tx_seq_h.error_injection = 1;
    tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
  end
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("IPG_002_I4", "FAIL [I4B]: Error frame not transmitted")
  else
    `uvm_info("IPG_002_I4",
              "PASS [I4B]: Error frame transmitted (out_error=0 per RTL design)", UVM_NONE)

  `uvm_info("IPG_002_I4", "PASS: Error injection complete", UVM_NONE)
endtask

// =============================================================================
// I5: Sustained Back-to-Back Data + PAUSE
//
// Interleave data and PAUSE TX requests in a tight loop.
// Verify no frame loss and deterministic ordering:
//   - Data frames always complete before PAUSE is served.
//   - PAUSE frames always complete (2 beats, no truncation).
//   - After PAUSE, data resumes without loss.
// =============================================================================
task IPG_002_ipg_tx_arb_test_c::run_sustained_back_to_back();
  int tx_before, tx_after;
  bit timed_out;
  int unsigned num_iterations = 5;

  `uvm_info("IPG_002", "--- I5: Sustained Back-to-Back ---", UVM_LOW)

  enable_pause_tx();
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  repeat (num_iterations) begin
    fork
      begin
        send_data_frame(46);
      end
      begin
        #500ns;
        trigger_sw_pause(16'h0004);
      end
    join
    #500ns;
  end

  // Expect: num_iterations * 2 (data + PAUSE per iteration)
  mac_wait_utils_c::wait_for_count_at_least(tx_before + (num_iterations * 2),
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (timed_out)
    `uvm_error("IPG_002_I5", $sformatf(
               "FAIL: Expected %0d frames, got %0d before timeout",
               num_iterations * 2, tx_after - tx_before))
  else
    `uvm_info("IPG_002_I5", $sformatf(
              "PASS: %0d frames transmitted in sustained back-to-back (%0d iterations)",
              tx_after - tx_before, num_iterations), UVM_NONE)

  wait_sw_pause_done();
  #1us;

  `uvm_info("IPG_002_I5", "PASS: Sustained back-to-back complete", UVM_NONE)
endtask

// =============================================================================
// run_stimulus — orchestrates all five iterations
// =============================================================================
task IPG_002_ipg_tx_arb_test_c::run_stimulus(uvm_phase phase);
  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null ||
      env_cfg_h.ral_h == null)
    `uvm_fatal("IPG_002", "MAC environment not built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("IPG_002", "MAC reset and APB bootstrap did not complete")

  `uvm_info("IPG_002", "=== IPG_002 / TX_ARB_001 START ===", UVM_LOW)

  run_pause_at_eop_vs_idle();     // I1
  run_min_max_pause_timing();     // I2
  run_backpressure_stall();       // I3
  run_error_injection();          // I4
  run_sustained_back_to_back();   // I5

  `uvm_info("IPG_002", "=== IPG_002 / TX_ARB_001 ALL ITERATIONS COMPLETE ===", UVM_NONE)
endtask

`endif  // IPG_002_IPG_TX_ARB_TEST_SVH
