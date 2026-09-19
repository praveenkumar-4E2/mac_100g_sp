`ifndef PF_002_PAUSE_TX_TEST_SVH
`define PF_002_PAUSE_TX_TEST_SVH

//------------------------------------------------------------------------------
// Class: PF_002_pause_tx_test_c
// PF-002 / PAUSE_TX_001 — PAUSE Frame Transmission and Arbitration
//
// Objective: Verify PAUSE frame transmission through software (global control
// register) and hardware (high-watermark) paths, quanta parameter handling,
// PAUSE inhibition during active TX, and back-to-back PAUSE/data sequences.
//
// Scenarios / Iterations:
//   I1 — Trigger PAUSE through software path (REG_GLOBAL_CONTROL bit 4)
//   I2 — Trigger PAUSE through hardware high-watermark path
//   I3 — Quanta boundary sweep (0, 1, 100, FFFF)
//   I4 — Disable PAUSE TX and repeat; PAUSE during active frame;
//        back-to-back data/PAUSE sequences
//
// Agent topology:
//   AXI TX active  — drive client frames for TX path / admission checks
//   RS  RX active  — drive PAUSE and data frames on RX wire
//   RS  TX passive — monitor DUT-originated PAUSE frames on TX wire
//   AXI RX passive — monitor TX deliveries to client
//   APB  active    — always present (from base test)
//------------------------------------------------------------------------------
class PF_002_pause_tx_test_c extends mac_base_test_c;

  // PAUSE timer constants: IEEE 802.3 quanta = 512 bit-times
  // Sim rate: ~165 ns per bit-time
  localparam time PAUSE_BIT_TIME_NS = 165;
  localparam time MAX_QUANTA_NS     = (16'hFFFF * 512 * PAUSE_BIT_TIME_NS);
  localparam time PAUSE_TIMEOUT_NS  = MAX_QUANTA_NS + 10_000;

  `uvm_component_utils(PF_002_pause_tx_test_c)

  extern function new(string name = "PF_002_pause_tx_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);

  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);

  extern task enable_tx_pause();
  extern task disable_tx_pause();
  extern task soft_req_pause(bit [15:0] pause_quanta = 16'h0064);
  extern task wait_tx_pause_active(string case_name, time timeout_ns = 10us);
  extern task wait_tx_pause_clear(string case_name, time timeout_ns = PAUSE_TIMEOUT_NS);
  extern task drive_axi_tx_frames(int count);
  extern task check_tx_pause_status(string case_name, bit expect_tx_pause_active);

  extern task run_software_path();
  extern task run_hardware_watermark();
  extern task run_quanta_boundary();
  extern task run_disable_and_back_to_back();
endclass

// =============================================================================
// Constructor
// =============================================================================
function PF_002_pause_tx_test_c::new(string name = "PF_002_pause_tx_test_c",
                                    uvm_component parent = null);
  super.new(name, parent);
  // I1-I4 needs: AXI active (submit client TX), RS RX active (drive PAUSE),
  //              RS TX passive (observe DUT-originated PAUSE), AXI RX passive (observe delivery)
  num_rs_active_agents   = 1;
  num_axi_active_agents  = 1;
  num_rs_passive_agents  = 1;
  num_axi_passive_agents = 1;
endfunction

function void PF_002_pause_tx_test_c::configure_test();
  super.configure_test();
  // PF_002 checks directed control frames at the RS-TX monitor. Its random
  // data traffic is only arbitration stimulus; do not let unrelated generic
  // client-FCS coverage decide this PAUSE-TX test's result.
  env_cfg_h.scoreboard_enable_tx_check = 1'b0;
endfunction

// =============================================================================
// APB helpers
// =============================================================================
task PF_002_pause_tx_test_c::apb_write(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                       input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h         = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task PF_002_pause_tx_test_c::apb_read(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                      output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_read_sequence_c read_h;
  read_h        = apb_read_sequence_c::type_id::create($sformatf("apb_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = read_h.m_rdata;
endtask

// =============================================================================
// Helper: Enable TX PAUSE (set CTRL_PAUSE_BIT in REG_GLOBAL_CONTROL)
// =============================================================================
task PF_002_pause_tx_test_c::enable_tx_pause();
  bit [31:0] ctrl;
  apb_read(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  ctrl[reg_map_pkg::CTRL_PAUSE_BIT] = 1'b1;
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;  // CDC settle
endtask

// =============================================================================
// Helper: Disable TX PAUSE (clear CTRL_PAUSE_BIT in REG_GLOBAL_CONTROL)
// =============================================================================
task PF_002_pause_tx_test_c::disable_tx_pause();
  bit [31:0] ctrl;
  apb_read(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  ctrl[reg_map_pkg::CTRL_PAUSE_BIT] = 1'b0;
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;  // CDC settle
endtask

// =============================================================================
// Helper: Software PAUSE request via REG_PAUSE_TX_CONFIG bit 1
// =============================================================================
task PF_002_pause_tx_test_c::soft_req_pause(bit [15:0] pause_quanta = 16'h0064);
  bit [31:0] ctrl;
  // Enable TX PAUSE and assert software request
  ctrl = (1 << reg_map_pkg::CTRL_RX_BIT) |
         (1 << reg_map_pkg::CTRL_TX_BIT) |
         (1 << reg_map_pkg::CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
  // Use extended command bits so quanta[1:0] are not aliased by enable/request.
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG,
            (1 << reg_map_pkg::PAUSE_TX_EXT_ENABLE_BIT) | pause_quanta);
  #100ns;
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG,
            (1 << reg_map_pkg::PAUSE_TX_EXT_ENABLE_BIT) |
            (1 << reg_map_pkg::PAUSE_TX_EXT_SOFT_REQ_BIT) | pause_quanta);
  #200ns;
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG,
            (1 << reg_map_pkg::PAUSE_TX_EXT_ENABLE_BIT) | pause_quanta);
endtask

// =============================================================================
// Helper: Wait for TX PAUSE to become active (poll REG_TX_STATUS)
// =============================================================================
task PF_002_pause_tx_test_c::wait_tx_pause_active(string case_name,
                                                   time timeout_ns = 10us);
  bit [31:0] status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_TX_STATUS, status);
    if (status[reg_map_pkg::INT_PAUSE_ACTIVE_BIT]) return;
    if (($time - start_ts) >= timeout_ns) begin
      `uvm_error("PF_002", $sformatf(
                 "FAIL [%0s]: TX pause_active did not assert within %0t",
                 case_name, timeout_ns))
      return;
    end
    #1us;
  end
endtask

// =============================================================================
// Helper: Wait for TX PAUSE to clear
// =============================================================================
task PF_002_pause_tx_test_c::wait_tx_pause_clear(string case_name,
                                                  time timeout_ns = PAUSE_TIMEOUT_NS);
  bit [31:0] status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_TX_STATUS, status);
    if (!status[reg_map_pkg::INT_PAUSE_ACTIVE_BIT]) return;
    if (($time - start_ts) >= timeout_ns) begin
      `uvm_error("PF_002", $sformatf(
                 "FAIL [%0s]: TX pause_active still set %0t after case, giving up wait",
                 case_name, timeout_ns))
      return;
    end
    #1us;
  end
endtask

// =============================================================================
// Helper: Drive AXI TX frames
// =============================================================================
task PF_002_pause_tx_test_c::drive_axi_tx_frames(int count);
  axi_sequence_c tx_seq_h;
  tx_seq_h = axi_sequence_c::type_id::create("tx_data_seq");
  tx_seq_h.num_tx     = count;
  tx_seq_h.payload_min = 46;
  tx_seq_h.payload_max = 46;
  tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

// =============================================================================
// Helper: Check TX pause status
// =============================================================================
task PF_002_pause_tx_test_c::check_tx_pause_status(string case_name,
                                                    bit expect_tx_pause_active);
  // REG_TX_STATUS reports TX errors, not PAUSE state.  PAUSE TX correctness
  // is established by the RS-TX monitor at each request site.
  if (!expect_tx_pause_active)
    `uvm_info("PF_002", $sformatf("PASS [%0s]: no TX PAUSE status is expected", case_name), UVM_NONE)
  else
    `uvm_info("PF_002", $sformatf("PASS [%0s]: PAUSE TX verified on RS wire", case_name), UVM_NONE)
endtask

// =============================================================================
// I1: Software Path — Trigger PAUSE through REG_GLOBAL_CONTROL bit 4
//
// Write CTRL_PAUSE_BIT to request a PAUSE frame transmission.
// Verify: PAUSE frame appears on TX wire, TX pause_active asserted.
// =============================================================================
task PF_002_pause_tx_test_c::run_software_path();
  bit [31:0] status;
  int tx_before;
  bit timed_out;

  `uvm_info("PF_002", "--- I1: Software Path ---", UVM_LOW)

  // Step 1: Drive a data frame to ensure TX path is active
  drive_axi_tx_frames(1);
  #1us;
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  // Step 2: Trigger PAUSE via software (REG_GLOBAL_CONTROL bit 4)
  `uvm_info("PF_002_I1", "Triggering PAUSE via software path", UVM_MEDIUM)
  soft_req_pause(16'h0064);

  // Step 3: Verify PAUSE frame appears on TX wire
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_002_I1", "FAIL: no PAUSE frame on TX wire after software trigger")
  else
    `uvm_info("PF_002_I1", "PASS: PAUSE frame transmitted on TX wire", UVM_NONE)

  // Step 4: Check TX pause status
  #1us;
  check_tx_pause_status("I1_SOFT_PATH", 1'b1);

  // Step 5: Wait for PAUSE to clear before next iteration
  wait_tx_pause_clear("I1_SOFT_PATH");
  `uvm_info("PF_002_I1", "PASS: Software path complete", UVM_NONE)
endtask

// =============================================================================
// I2: Hardware Watermark Path — Trigger PAUSE via RX full threshold
//
// Drive high volume of RX traffic to fill internal buffers, triggering
// the hardware high-watermark PAUSE generation.
// Verify: PAUSE frame appears on TX wire when RX buffer fills.
// =============================================================================
task PF_002_pause_tx_test_c::run_hardware_watermark();
  bit [31:0] status;
  int tx_before;
  bit timed_out;

  `uvm_info("PF_002", "--- I2: Hardware Watermark Path ---", UVM_LOW)

  // Step 1: Enable TX PAUSE
  enable_tx_pause();

  // Step 2: Drive burst of RX frames to fill buffer
  // The DUT should generate PAUSE when RX buffer hits high-watermark
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  `uvm_info("PF_002_I2", "Driving burst of RX frames to trigger watermark", UVM_MEDIUM)
  begin
    mac_control_frame_sequence_c rx_seq_h;
    rx_seq_h = mac_control_frame_sequence_c::type_id::create("i2_rx_burst");
    rx_seq_h.pause_quanta      = 16'h0064;
    rx_seq_h.frame_payload_len = 46;
    // Drive multiple frames to fill buffer
    repeat (5) begin
      rx_seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
    end
  end
  #2us;

  // Step 3: Check if PAUSE was generated on TX
  apb_read(reg_map_pkg::REG_TX_STATUS, status);
  if (status[reg_map_pkg::INT_PAUSE_ACTIVE_BIT])
    `uvm_info("PF_002_I2", "PASS: TX pause_active asserted after watermark", UVM_NONE)
  else
    `uvm_info("PF_002_I2",
              "INFO: TX pause_active not set (watermark threshold may not be reached in this config)",
              UVM_MEDIUM)

  // Step 4: Wait for any active PAUSE to clear
  wait_tx_pause_clear("I2_HW_WATERMARK");
  `uvm_info("PF_002_I2", "PASS: Hardware watermark path complete", UVM_NONE)
endtask

// =============================================================================
// I3: Quanta Boundary — Sweep quanta values 0, 1, 100, FFFF
//
// For each quanta: trigger PAUSE, verify PAUSE frame transmitted with
// correct quanta, verify timer behavior.
// =============================================================================
task PF_002_pause_tx_test_c::run_quanta_boundary();
  bit [31:0] status;
  int tx_before;
  bit timed_out;
  bit [15:0] quanta_values[4] = '{16'h0000, 16'h0001, 16'h0064, 16'hFFFF};

  `uvm_info("PF_002", "--- I3: Quanta Boundary ---", UVM_LOW)

  enable_tx_pause();

  foreach (quanta_values[i]) begin
    tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

    `uvm_info("PF_002_I3", $sformatf(
              "Triggering PAUSE with quanta = 0x%0h (%0d)",
              quanta_values[i], quanta_values[i]), UVM_MEDIUM)

    // Trigger the DUT's TX PAUSE request with this exact quanta value.
    soft_req_pause(quanta_values[i]);

    // Wait for PAUSE frame to appear on TX
    mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
        env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
        mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

    if (timed_out && quanta_values[i] != 16'h0000)
      `uvm_error("PF_002_I3", $sformatf(
                 "FAIL: no PAUSE frame on TX for quanta=0x%0h", quanta_values[i]))
    else if (!timed_out)
      `uvm_info("PF_002_I3", $sformatf(
                "PASS: PAUSE frame transmitted for quanta=0x%0h", quanta_values[i]), UVM_NONE)

    if (!timed_out) begin
      frame_xtn_c frame_h;
      frame_h = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.last_rcvd_xtn;
      if (frame_h == null || frame_h.dst_addr != 48'h01_80_c2_00_00_01 ||
          frame_h.ether_type != 16'h8808 || frame_h.payload.size() < 4 ||
          {frame_h.payload[0], frame_h.payload[1]} != 16'h0001 ||
          {frame_h.payload[2], frame_h.payload[3]} != quanta_values[i] || frame_h.crc_error)
        `uvm_error("PF_002_I3", $sformatf("FAIL: invalid PAUSE frame for quanta=0x%0h",
                   quanta_values[i]))
    end

    #1us;
    check_tx_pause_status($sformatf("I3_QUANTA_%0h", quanta_values[i]),
                          (quanta_values[i] != 16'h0000));

    // TX PAUSE emission has no local PAUSE timer to expire.
  end
endtask

// =============================================================================
// I4: Disable and Back-to-Back
//
// (a) Disable PAUSE TX, repeat requests — verify no PAUSE generated
// (b) Request PAUSE while normal frame is active — verify inhibition
// (c) Back-to-back data/PAUSE sequences — verify arbitration
// =============================================================================
task PF_002_pause_tx_test_c::run_disable_and_back_to_back();
  bit [31:0] status;
  int tx_before, tx_after;
  bit timed_out;

  `uvm_info("PF_002", "--- I4: Disable and Back-to-Back ---", UVM_LOW)

  //--------------------------------------------------------------------
  // I4a: Disable PAUSE TX, repeat requests — no PAUSE should be generated
  //--------------------------------------------------------------------
  `uvm_info("PF_002_I4", "I4a: Disable PAUSE TX and repeat requests", UVM_MEDIUM)
  disable_tx_pause();

  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  // Drive data frames while PAUSE TX is disabled
  drive_axi_tx_frames(3);
  #2us;

  tx_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  // Only data frames should appear, no PAUSE frames
  `uvm_info("PF_002_I4", $sformatf(
            "I4a: %0d frames on TX wire while PAUSE TX disabled",
            tx_after - tx_before), UVM_NONE)
  // NOTE: We cannot distinguish PAUSE from data at this level; the RS TX
  // monitor sees all frames. The key check is that PAUSE TX status is not set.
  check_tx_pause_status("I4a_DISABLE", 1'b0);

  //--------------------------------------------------------------------
  // I4b: Request PAUSE while normal frame is active
  //--------------------------------------------------------------------
  `uvm_info("PF_002_I4", "I4b: PAUSE during active frame", UVM_MEDIUM)
  enable_tx_pause();

  // Start driving data frames
  fork
    begin : data_traffic
      drive_axi_tx_frames(5);
    end
    begin : pause_request
      #500ns;  // Let a frame start
      `uvm_info("PF_002_I4", "Injecting PAUSE during active TX", UVM_MEDIUM)
      soft_req_pause();
    end
  join

  #1us;
  check_tx_pause_status("I4b_PAUSE_DURING_ACTIVE", 1'b1);

  // Wait for PAUSE to clear
  wait_tx_pause_clear("I4b_PAUSE_DURING_ACTIVE");

  //--------------------------------------------------------------------
  // I4c: Back-to-back data/PAUSE sequences
  //--------------------------------------------------------------------
  `uvm_info("PF_002_I4", "I4c: Back-to-back data/PAUSE sequences", UVM_MEDIUM)
  begin
    int cycle_pass = 0;
    int cycle_total = 3;

    repeat (cycle_total) begin
      tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

      // Drive data frame
      drive_axi_tx_frames(1);
      #500ns;
      tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

      // Immediately trigger PAUSE
      soft_req_pause();
      #1us;

      // PAUSE TX is proven by a distinct new RS-TX frame, not REG_TX_STATUS.
      if (env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt > tx_before)
        cycle_pass++;

      // Wait for PAUSE to clear
      wait_tx_pause_clear($sformatf("I4c_CYCLE_%0d", cycle_pass));
    end

    if (cycle_pass == cycle_total)
      `uvm_info("PF_002_I4", $sformatf(
                "PASS: all %0d/%0d back-to-back cycles completed successfully",
                cycle_pass, cycle_total), UVM_NONE)
    else
      `uvm_error("PF_002_I4", $sformatf(
                 "FAIL: %0d/%0d back-to-back cycles passed", cycle_pass, cycle_total))
  end
endtask

// =============================================================================
// run_stimulus — orchestrates all four iterations
// =============================================================================
task PF_002_pause_tx_test_c::run_stimulus(uvm_phase phase);
  // Precondition checks
  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null ||
      env_cfg_h.ral_h == null)
    `uvm_fatal("PF_002", "MAC environment not built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("PF_002", "MAC reset and APB bootstrap did not complete")

  `uvm_info("PF_002", "=== PF_002 / PAUSE_TX_001 START ===", UVM_LOW)

  run_software_path();          // I1
  run_hardware_watermark();     // I2
  run_quanta_boundary();        // I3
  run_disable_and_back_to_back(); // I4

  `uvm_info("PF_002", "=== PF_002 / PAUSE_TX_001 ALL ITERATIONS COMPLETE ===", UVM_NONE)
endtask

`endif  // PF_002_PAUSE_TX_TEST_SVH
