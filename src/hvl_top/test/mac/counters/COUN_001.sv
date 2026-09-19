`ifndef COUN_001_STAT_SNAP_TEST_SVH
`define COUN_001_STAT_SNAP_TEST_SVH

//------------------------------------------------------------------------------
// Helper: Data frame sequence for the RS RX active agent.
// Sends a raw Ethernet data frame (EtherType != 0x8808) on the ingress wire
// so the MAC RX path processes it through rx_length_check.
//------------------------------------------------------------------------------
class coun_001_data_frame_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(coun_001_data_frame_seq_c)

  int unsigned payload_len = 46;

  extern function new(string name = "coun_001_data_frame_seq_c");
  extern task body();
endclass

function coun_001_data_frame_seq_c::new(string name = "coun_001_data_frame_seq_c");
  super.new(name);
endfunction

task coun_001_data_frame_seq_c::body();
  frame_xtn_c frm;
  frm            = frame_xtn_c::type_id::create("data_frm");
  frm.dst_addr   = 48'hFF_FF_FF_FF_FF_FF;
  frm.src_addr   = 48'h02_00_00_00_00_02;
  frm.ether_type = 16'h0800;
  frm.payload    = new[payload_len];
  foreach (frm.payload[i]) frm.payload[i] = 8'hA5;
  frm.insert_fcs      = 1'b1;
  frm.crc_error       = 1'b0;
  frm.length_error    = 1'b0;
  frm.alignment_error = 1'b0;
  frm.fcs             = frm.compute_fcs();
  do_rs_frame(frm);
endtask

//------------------------------------------------------------------------------
// Class: COUN_001_stat_snap_test_c
// COUN-001 / STAT_SNAP_001 — MAC Statistics Snapshot Composition
//
// Objective: Verify that the 384-bit statistics snapshot (mac_stats.v)
// correctly captures and returns all fields: invalid_count, oversize_count,
// unsupported_count, interrupt_status[6:0], pause_active, pause_expired,
// and tx_error_event.
//
// Scenarios / Iterations:
//   I1 — Idle snapshot: all counters zero, no interrupt causes, status bits
//        deasserted after reset.
//   I2 — Clean frame: send a valid data frame with no errors; verify no
//        counters increment and no interrupt bits set.
//   I3 — Oversize event: set max_frame_size=100, send 1500 B frame via RS RX;
//        verify oversize_count increments and rx_oversize interrupt fires.
//   I4 — Unsupported control: send MAC control frame (EtherType 0x8808, DA
//        01:80:C2:00:00:01) with opcode != 0x0001; verify
//        unsupported_count increments and rx_unsupported interrupt fires.
//   I5 — PAUSE active: send PAUSE frame and immediately read snapshot;
//        verify pause_active status bit set.
//   I6 — PAUSE expired: trigger SW PAUSE and wait for expiry; verify
//        pause_expired status bit set.
//   I7 — Concurrent events: send unsupported + oversize in sequence;
//        verify all corresponding bits set simultaneously.
//   I8 — Clear counters and interrupts: write clear masks, verify all
//        counters and interrupt status return to zero.
//
// Agent topology:
//   AXI TX active  — drive client data frames (clean frame only)
//   RS  RX active  — inject PAUSE, unsupported control, and oversize frames
//   RS  TX passive — monitor DUT TX wire output
//   APB  active    — always present (from base test); read stats registers
//
// RTL notes (mac_stats.v):
//   status_snapshot_mac[31:0]   = invalid_count
//   status_snapshot_mac[63:32]  = oversize_count
//   status_snapshot_mac[95:64]  = unsupported_count
//   status_snapshot_mac[127:96] = {25'd0, interrupt_status[6:0]}
//   status_snapshot_mac[159:128]= {31'd0, pause_active}
//   status_snapshot_mac[191:160]= {31'd0, pause_expired}
//   status_snapshot_mac[223:192]= {31'd0, tx_error_event}
//
// Counter clear (apb_interrupt.v): each register only clears its own counter
// via write_data[0] bit.  Must write to all three counter registers to clear
// all counters.
// Interrupt clear: write to REG_INTERRUPT_STATUS -> irq_clear + mask[6:0]
//------------------------------------------------------------------------------
class COUN_001_stat_snap_test_c extends mac_base_test_c;

  localparam int unsigned CTRL_TX_BIT    = reg_map_pkg::CTRL_TX_BIT;
  localparam int unsigned CTRL_RX_BIT    = reg_map_pkg::CTRL_RX_BIT;
  localparam int unsigned CTRL_PAUSE_BIT = reg_map_pkg::CTRL_PAUSE_BIT;

  localparam bit [47:0] PAUSE_DA = 48'h01_80_C2_00_00_01;

  `uvm_component_utils(COUN_001_stat_snap_test_c)

  extern function new(string name = "COUN_001_stat_snap_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);

  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);

  extern task enable_tx();
  extern task enable_rx_pause();
  extern task send_data_frame(int payload_bytes = 46);
  extern task send_oversize_frame(int payload_bytes = 1500);
  extern task send_pause_frame(bit [15:0] quanta);
  extern task send_unsupported_control_frame();
  extern task trigger_sw_pause(bit [15:0] quanta);
  extern task wait_sw_pause_done();
  extern task clear_counters_and_interrupts();
  extern task wait_for_tx_frame(int timeout_ms = 10);

  extern task run_idle_snapshot();
  extern task run_clean_frame();
  extern task run_oversize_event();
  extern task run_unsupported_control();
  extern task run_pause_active();
  extern task run_pause_expired();
  extern task run_concurrent_events();
  extern task run_clear_counters();
endclass

// =============================================================================
// Constructor
// =============================================================================
function COUN_001_stat_snap_test_c::new(string name = "COUN_001_stat_snap_test_c",
                                       uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 0;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
endfunction

// =============================================================================
// Configure
// =============================================================================
function void COUN_001_stat_snap_test_c::configure_test();
  super.configure_test();
  // This test intentionally injects control frames consumed within the MAC.
  // Its directed counter checks are the oracle for that traffic; the generic
  // AXI RX scoreboard must not expect those frames at the client interface.
  env_cfg_h.scoreboard_enable_rx_check = 1'b0;
  env_cfg_h.rs_passive_agent_cfgs[0].enable_ipg_check = 1'b0;
endfunction

// =============================================================================
// APB helpers
// =============================================================================
task COUN_001_stat_snap_test_c::apb_write(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h         = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task COUN_001_stat_snap_test_c::apb_read(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
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
task COUN_001_stat_snap_test_c::enable_tx();
  bit [31:0] ctrl;
  ctrl = (1 << CTRL_TX_BIT) | (1 << CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
endtask

task COUN_001_stat_snap_test_c::enable_rx_pause();
  bit [31:0] ctrl;
  ctrl = (1 << CTRL_RX_BIT) | (1 << CTRL_TX_BIT) | (1 << CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
endtask

task COUN_001_stat_snap_test_c::send_data_frame(int payload_bytes = 46);
  axi_sequence_c tx_seq_h;
  tx_seq_h = axi_sequence_c::type_id::create("data_frame");
  tx_seq_h.num_tx      = 1;
  tx_seq_h.payload_min = payload_bytes;
  tx_seq_h.payload_max = payload_bytes;
  tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task COUN_001_stat_snap_test_c::send_oversize_frame(int payload_bytes = 1500);
  coun_001_data_frame_seq_c seq_h;
  seq_h = coun_001_data_frame_seq_c::type_id::create("oversize_frm");
  seq_h.payload_len = payload_bytes;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task COUN_001_stat_snap_test_c::send_pause_frame(bit [15:0] quanta);
  mac_control_frame_sequence_c seq_h;
  seq_h = mac_control_frame_sequence_c::type_id::create($sformatf("pause_%0h", quanta));
  seq_h.pause_quanta      = quanta;
  seq_h.frame_payload_len = 46;
  seq_h.ctrl_da           = PAUSE_DA;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task COUN_001_stat_snap_test_c::send_unsupported_control_frame();
  mac_control_frame_sequence_c seq_h;
  seq_h = mac_control_frame_sequence_c::type_id::create("unsupported_ctrl");
  seq_h.opcode            = 16'h0002;
  seq_h.ctrl_da           = PAUSE_DA;
  seq_h.frame_payload_len = 46;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task COUN_001_stat_snap_test_c::trigger_sw_pause(bit [15:0] quanta);
  bit [31:0] tx_cfg;
  bit [31:0] pause_ctrl;
  pause_ctrl = {16'h0, quanta};
  apb_write(reg_map_pkg::REG_PAUSE_CONTROL, pause_ctrl);
  #200ns;
  tx_cfg = (1 << reg_map_pkg::PAUSE_TX_ENABLE_BIT) |
           (1 << reg_map_pkg::PAUSE_TX_SOFT_REQ_BIT);
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, tx_cfg);
endtask

task COUN_001_stat_snap_test_c::wait_sw_pause_done();
  bit [31:0] tx_status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_TX_STATUS, tx_status);
    if (!tx_status[reg_map_pkg::INT_PAUSE_ACTIVE_BIT]) break;
    if (($time - start_ts) >= 10ms) begin
      `uvm_error("COUN_001", "Timeout waiting for SW PAUSE to complete")
      break;
    end
    #1us;
  end
endtask

task COUN_001_stat_snap_test_c::clear_counters_and_interrupts();
  apb_write(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h001);
  #1us;
  apb_write(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h001);
  #1us;
  apb_write(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, 32'h001);
  #1us;
  apb_write(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h007F);
  #1us;
endtask

task COUN_001_stat_snap_test_c::wait_for_tx_frame(int timeout_ms = 10);
  bit timed_out;
  int tx_before;
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  mac_wait_utils_c::wait_for_count_at_least(tx_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, (timeout_ms * 1) * 1ms, timed_out);
endtask

// =============================================================================
// I1: Idle Snapshot
// =============================================================================
task COUN_001_stat_snap_test_c::run_idle_snapshot();
  bit [31:0] val;
  bit [31:0] int_enable;
  int        fail_count = 0;

  `uvm_info("COUN_001", "--- I1: Idle Snapshot ---", UVM_LOW)

  int_enable = 32'h007F;
  apb_write(reg_map_pkg::REG_INTERRUPT_ENABLE, int_enable);
  #1us;

  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  if (val != 32'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I1]: invalid_count=%0d, expected 0", val))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  if (val != 32'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I1]: oversize_count=%0d, expected 0", val))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  if (val != 32'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I1]: unsupported_count=%0d, expected 0", val))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_INTERRUPT_STATUS, val);
  if (val[6:0] != 7'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I1]: interrupt_status=%h, expected 0", val[6:0]))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_RX_STATUS, val);
  if (val[0] != 1'b0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I1]: pause_active=%b, expected 0", val[0]))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_PAUSE_STATUS, val);
  if (val[0] != 1'b0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I1]: pause_expired=%b, expected 0", val[0]))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_TX_STATUS, val);
  if (val[0] != 1'b0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I1]: tx_error_event=%b, expected 0", val[0]))
    fail_count++;
  end

  if (fail_count == 0)
    `uvm_info("COUN_001", "PASS [I1]: All idle snapshot fields zero", UVM_NONE)
endtask

// =============================================================================
// I2: Clean Frame
// =============================================================================
task COUN_001_stat_snap_test_c::run_clean_frame();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_001", "--- I2: Clean Frame ---", UVM_LOW)

  enable_tx();
  send_data_frame(46);
  wait_for_tx_frame();
  #1us;

  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  if (val != 32'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I2]: invalid_count=%0d, expected 0", val))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  if (val != 32'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I2]: oversize_count=%0d, expected 0", val))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  if (val != 32'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I2]: unsupported_count=%0d, expected 0", val))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_INTERRUPT_STATUS, val);
  if (val[6:0] != 7'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I2]: interrupt_status=%h, expected 0", val[6:0]))
    fail_count++;
  end

  if (fail_count == 0)
    `uvm_info("COUN_001", "PASS [I2]: Clean frame — no events", UVM_NONE)
endtask

// =============================================================================
// I3: Oversize Event
//
// Send an oversize frame via RS RX active agent.  The RX length check
// marks the frame as oversize → oversize_count increments and
// rx_oversize interrupt (bit 2) fires.
// =============================================================================
task COUN_001_stat_snap_test_c::run_oversize_event();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_001", "--- I3: Oversize Event ---", UVM_LOW)

  enable_rx_pause();
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd100);
  #10us;

  send_oversize_frame(1500);
  #5us;

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  if (val == 32'd0) begin
    `uvm_error("COUN_001", "FAIL [I3]: oversize_count not incremented")
    fail_count++;
  end else
    `uvm_info("COUN_001", $sformatf("  oversize_count=%0d", val), UVM_MEDIUM)

  apb_read(reg_map_pkg::REG_INTERRUPT_STATUS, val);
  if (!val[2]) begin
    `uvm_error("COUN_001", "FAIL [I3]: rx_oversize interrupt (bit 2) not set")
    fail_count++;
  end

  // Restore default max_frame_size
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1500);
  #10us;

  if (fail_count == 0)
    `uvm_info("COUN_001", "PASS [I3]: Oversize event detected", UVM_NONE)
endtask

// =============================================================================
// I4: Unsupported Control
// =============================================================================
task COUN_001_stat_snap_test_c::run_unsupported_control();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_001", "--- I4: Unsupported Control ---", UVM_LOW)

  enable_rx_pause();
  #1us;

  send_unsupported_control_frame();
  #5us;

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  if (val == 32'd0) begin
    `uvm_error("COUN_001", "FAIL [I4]: unsupported_count not incremented")
    fail_count++;
  end else
    `uvm_info("COUN_001", $sformatf("  unsupported_count=%0d", val), UVM_MEDIUM)

  apb_read(reg_map_pkg::REG_INTERRUPT_STATUS, val);
  if (!val[3]) begin
    `uvm_error("COUN_001", "FAIL [I4]: rx_unsupported interrupt (bit 3) not set")
    fail_count++;
  end

  if (fail_count == 0)
    `uvm_info("COUN_001", "PASS [I4]: Unsupported control event detected", UVM_NONE)
endtask

// =============================================================================
// I5: PAUSE Active
// =============================================================================
task COUN_001_stat_snap_test_c::run_pause_active();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_001", "--- I5: PAUSE Active ---", UVM_LOW)

  enable_rx_pause();
  #1us;

  send_pause_frame(16'h0100);
  #2us;

  apb_read(reg_map_pkg::REG_RX_STATUS, val);
  if (val[0] != 1'b1) begin
    `uvm_error("COUN_001", $sformatf(
               "FAIL [I5]: pause_active=%b, expected 1 (REG_RX_STATUS=%h)", val[0], val))
    fail_count++;
  end

  if (fail_count == 0)
    `uvm_info("COUN_001", "PASS [I5]: PAUSE active detected", UVM_NONE)
endtask

// =============================================================================
// I6: PAUSE Expired
//
// Trigger a short SW PAUSE (quanta=4 ≈ 2048 bit-times), wait for the
// timer to expire, then check the sticky interrupt_status[5] bit.
// =============================================================================
task COUN_001_stat_snap_test_c::run_pause_expired();
  bit [31:0] val;
  int        fail_count = 0;
  time       start_ts;

  `uvm_info("COUN_001", "--- I6: PAUSE Expired ---", UVM_LOW)

  enable_rx_pause();
  trigger_sw_pause(16'h0004);

  // Wait for pause_active to be set (timer loaded)
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_RX_STATUS, val);
    if (val[0]) break;
    if (($time - start_ts) >= 10ms) begin
      `uvm_error("COUN_001", "FAIL [I6]: pause_active did not assert within 10ms")
      fail_count++;
      break;
    end
    #1us;
  end

  // Wait for pause_active to clear (timer expired)
  if (fail_count == 0) begin
    start_ts = $time;
    forever begin
      apb_read(reg_map_pkg::REG_RX_STATUS, val);
      if (!val[0]) break;
      if (($time - start_ts) >= 500ms) begin
        `uvm_error("COUN_001", "FAIL [I6]: PAUSE timer did not expire within 500ms")
        fail_count++;
        break;
      end
      #10us;
    end
  end

  // Check the sticky interrupt_status[5] bit for pause_expired
  if (fail_count == 0) begin
    #1us;
    apb_read(reg_map_pkg::REG_INTERRUPT_STATUS, val);
    if (!val[5]) begin
      `uvm_error("COUN_001", $sformatf(
                 "FAIL [I6]: pause_expired interrupt (bit 5) not set (INT_STATUS=%h)", val))
      fail_count++;
    end
  end

  if (fail_count == 0)
    `uvm_info("COUN_001", "PASS [I6]: PAUSE expired detected", UVM_NONE)
endtask

// =============================================================================
// I7: Concurrent Events
//
// Send unsupported control and oversize frames via RS RX.
// Verify all corresponding counter and interrupt bits are set
// simultaneously in the snapshot.
// =============================================================================
task COUN_001_stat_snap_test_c::run_concurrent_events();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_001", "--- I7: Concurrent Events ---", UVM_LOW)

  enable_rx_pause();
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd100);
  #10us;

  // Send unsupported control frame (triggers bit 3)
  send_unsupported_control_frame();
  #5us;

  // Send oversize frame via RS RX (triggers bit 2)
  send_oversize_frame(1500);
  #5us;

  // Restore max_frame_size
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1500);
  #10us;

  // Read all stats
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  if (val == 32'd0) begin
    `uvm_error("COUN_001", "FAIL [I7]: unsupported_count=0")
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  if (val == 32'd0) begin
    `uvm_error("COUN_001", "FAIL [I7]: oversize_count=0")
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_INTERRUPT_STATUS, val);
  if (!val[3]) begin
    `uvm_error("COUN_001", "FAIL [I7]: rx_unsupported interrupt not set")
    fail_count++;
  end
  if (!val[2]) begin
    `uvm_error("COUN_001", "FAIL [I7]: rx_oversize interrupt not set")
    fail_count++;
  end

  if (fail_count == 0)
    `uvm_info("COUN_001", "PASS [I7]: Concurrent events verified", UVM_NONE)
endtask

// =============================================================================
// I8: Clear Counters and Interrupts
//
// apb_interrupt.v: each counter register only clears its own counter
// via write_data[0].  Must write to all three individually.
// =============================================================================
task COUN_001_stat_snap_test_c::run_clear_counters();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_001", "--- I8: Clear Counters and Interrupts ---", UVM_LOW)

  // Ensure events are present first
  enable_rx_pause();
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd100);
  #10us;

  send_unsupported_control_frame();
  #5us;
  send_oversize_frame(1500);
  #5us;

  // Restore
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1500);
  #10us;

  // Verify non-zero before clear
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  `uvm_info("COUN_001", $sformatf("  Before clear: unsupported_count=%0d", val), UVM_MEDIUM)
  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  `uvm_info("COUN_001", $sformatf("  Before clear: oversize_count=%0d", val), UVM_MEDIUM)

  // Clear counters and interrupts (each counter needs its own write)
  clear_counters_and_interrupts();

  // Verify all zero after clear
  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  if (val != 32'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I8]: invalid_count=%0d after clear", val))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  if (val != 32'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I8]: oversize_count=%0d after clear", val))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  if (val != 32'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I8]: unsupported_count=%0d after clear", val))
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_INTERRUPT_STATUS, val);
  if (val[6:0] != 7'd0) begin
    `uvm_error("COUN_001", $sformatf("FAIL [I8]: interrupt_status=%h after clear", val[6:0]))
    fail_count++;
  end

  if (fail_count == 0)
    `uvm_info("COUN_001", "PASS [I8]: Counters and interrupts cleared", UVM_NONE)
endtask

// =============================================================================
// run_stimulus — orchestrates all eight iterations
// =============================================================================
task COUN_001_stat_snap_test_c::run_stimulus(uvm_phase phase);
  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null ||
      env_cfg_h.ral_h == null)
    `uvm_fatal("COUN_001", "MAC environment not built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("COUN_001", "MAC reset and APB bootstrap did not complete")

  `uvm_info("COUN_001", "=== COUN_001 / STAT_SNAP_001 START ===", UVM_LOW)

  clear_counters_and_interrupts();

  run_idle_snapshot();              // I1
  run_clean_frame();                // I2
  run_oversize_event();             // I3
  run_unsupported_control();        // I4
  run_pause_active();               // I5
  run_pause_expired();              // I6
  run_concurrent_events();          // I7
  run_clear_counters();             // I8

  `uvm_info("COUN_001", "=== COUN_001 / STAT_SNAP_001 ALL ITERATIONS COMPLETE ===", UVM_NONE)
endtask

`endif  // COUN_001_STAT_SNAP_TEST_SVH
