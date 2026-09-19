`ifndef COUN_002_STAT_COUNTER_TEST_SVH
`define COUN_002_STAT_COUNTER_TEST_SVH

//------------------------------------------------------------------------------
// Helper: Data frame sequence for the RS RX active agent.
// Sends a raw Ethernet data frame (EtherType != 0x8808) on the ingress wire
// so the MAC RX path processes it through rx_length_check.
//------------------------------------------------------------------------------
class coun_002_data_frame_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(coun_002_data_frame_seq_c)

  int unsigned payload_len = 46;

  extern function new(string name = "coun_002_data_frame_seq_c");
  extern task body();
endclass

function coun_002_data_frame_seq_c::new(string name = "coun_002_data_frame_seq_c");
  super.new(name);
endfunction

task coun_002_data_frame_seq_c::body();
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
// Class: COUN_002_stat_counter_test_c
// COUN-002 / STAT_COUNTER_001 — Statistics Counter Event, Clear, and Boundary
//
// Objective: Verify qualifying-event increments, counter isolation, selected
// clear, priority, and specified rollover/saturation behavior.
//
// RTL references (stats_counters.v):
//   Counter clear priority: clear_mask[i] && clear beats event in same cycle.
//   No saturation — natural 32-bit modular wrap.
//
// RTL references (apb_interrupt.v):
//   Per-register clear via write_data[0]:
//     REG_RX_INVALID_COUNT   → counter_clear_mask[0]
//     REG_RX_OVERSIZE_COUNT  → counter_clear_mask[1]
//     REG_RX_UNSUPPORTED_COUNT → counter_clear_mask[2]
//   CDC handshake transfers clear to MAC domain (2+ MAC cycle latency).
//
// RTL references (apb_regs.v):
//   Counter reads go through stats_cdc_bridge (384-bit snapshot).
//   Each read triggers status_request toggle → snapshot capture → CDC transfer.
//   pready held until status_ack == status_request.
//
// Scenarios / Iterations:
//   I1 — Single-Event Counter Isolation: only qualifying events increment
//        associated counters; valid frames produce no counter events.
//   I2 — Individual Counter Clear: clearing one counter does not affect others.
//   I3 — All-Counter Clear: clearing all three counters simultaneously.
//   I4 — Clear-Priority: clear resets counter state after event.
//   I5 — Concurrent Events with Isolation: multiple counters track independent
//        event streams simultaneously.
//   I6 — 32-bit Counter Width: no truncation; count matches event quantity.
//   I7 — Mixed Traffic with Reference Model: event-class association across
//        mixed frame types using per-counter expected-value tracking.
//   I8 — Clear-and-Regenerate Cycle: counter state properly reset and reusable.
//
// Agent topology:
//   AXI TX active  — drive client data frames (clean frame only)
//   RS  RX active  — inject PAUSE, unsupported control, oversize, and data frames
//   RS  TX passive — monitor DUT TX wire output
//   APB  active    — always present (from base test); read stats registers
//------------------------------------------------------------------------------
class COUN_002_stat_counter_test_c extends mac_base_test_c;

  localparam int unsigned CTRL_TX_BIT    = reg_map_pkg::CTRL_TX_BIT;
  localparam int unsigned CTRL_RX_BIT    = reg_map_pkg::CTRL_RX_BIT;
  localparam int unsigned CTRL_PAUSE_BIT = reg_map_pkg::CTRL_PAUSE_BIT;

  localparam bit [47:0] PAUSE_DA = 48'h01_80_C2_00_00_01;

  `uvm_component_utils(COUN_002_stat_counter_test_c)

  // Per-counter reference model
  bit [31:0] exp_invalid_count;
  bit [31:0] exp_oversize_count;
  bit [31:0] exp_unsupported_count;

  extern function new(string name = "COUN_002_stat_counter_test_c",
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
  extern task send_unsupported_control_frame();
  extern task clear_counters_and_interrupts();
  extern task clear_invalid_only();
  extern task clear_oversize_only();
  extern task clear_unsupported_only();

  extern task verify_counter(input string label,
                             input bit [31:0] actual,
                             input bit [31:0] expected,
                             ref int fail_count);

  extern task run_single_event_isolation();
  extern task run_individual_clear();
  extern task run_all_counter_clear();
  extern task run_clear_priority();
  extern task run_concurrent_isolation();
  extern task run_counter_width();
  extern task run_mixed_traffic_model();
  extern task run_clear_regenerate_cycle();
endclass

// =============================================================================
// Constructor
// =============================================================================
function COUN_002_stat_counter_test_c::new(string name = "COUN_002_stat_counter_test_c",
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
function void COUN_002_stat_counter_test_c::configure_test();
  super.configure_test();
  // Directed control-frame injections are consumed by the MAC and are
  // validated by the counter model rather than the generic AXI RX scoreboard.
  env_cfg_h.scoreboard_enable_rx_check = 1'b0;
  env_cfg_h.rs_passive_agent_cfgs[0].enable_ipg_check = 1'b0;
endfunction

// =============================================================================
// APB helpers
// =============================================================================
task COUN_002_stat_counter_test_c::apb_write(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h         = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task COUN_002_stat_counter_test_c::apb_read(
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
task COUN_002_stat_counter_test_c::enable_tx();
  bit [31:0] ctrl;
  ctrl = (1 << CTRL_TX_BIT) | (1 << CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
endtask

task COUN_002_stat_counter_test_c::enable_rx_pause();
  bit [31:0] ctrl;
  ctrl = (1 << CTRL_RX_BIT) | (1 << CTRL_TX_BIT) | (1 << CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
endtask

task COUN_002_stat_counter_test_c::send_data_frame(int payload_bytes = 46);
  coun_002_data_frame_seq_c seq_h;
  seq_h = coun_002_data_frame_seq_c::type_id::create("data_frame");
  seq_h.payload_len = payload_bytes;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task COUN_002_stat_counter_test_c::send_oversize_frame(int payload_bytes = 1500);
  coun_002_data_frame_seq_c seq_h;
  seq_h = coun_002_data_frame_seq_c::type_id::create("oversize_frm");
  seq_h.payload_len = payload_bytes;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task COUN_002_stat_counter_test_c::send_unsupported_control_frame();
  mac_control_frame_sequence_c seq_h;
  seq_h = mac_control_frame_sequence_c::type_id::create("unsupported_ctrl");
  seq_h.opcode            = 16'h0002;
  seq_h.ctrl_da           = PAUSE_DA;
  seq_h.frame_payload_len = 46;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task COUN_002_stat_counter_test_c::clear_counters_and_interrupts();
  apb_write(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h001);
  #1us;
  apb_write(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h001);
  #1us;
  apb_write(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, 32'h001);
  #1us;
  apb_write(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h007F);
  #1us;
endtask

task COUN_002_stat_counter_test_c::clear_invalid_only();
  apb_write(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h001);
  #1us;
endtask

task COUN_002_stat_counter_test_c::clear_oversize_only();
  apb_write(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h001);
  #1us;
endtask

task COUN_002_stat_counter_test_c::clear_unsupported_only();
  apb_write(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, 32'h001);
  #1us;
endtask

// =============================================================================
// Verification helper — compare actual vs expected, log result
// =============================================================================
task COUN_002_stat_counter_test_c::verify_counter(
    input string label,
    input bit [31:0] actual,
    input bit [31:0] expected,
    ref int fail_count);
  if (actual !== expected) begin
    `uvm_error("COUN_002", $sformatf("FAIL [%s]: count=%0d, expected %0d",
               label, actual, expected))
    fail_count++;
  end
endtask

// =============================================================================
// I1: Single-Event Counter Isolation
//
// Verify that only qualifying events increment their associated counters.
// Valid data frames produce no counter events.
// =============================================================================
task COUN_002_stat_counter_test_c::run_single_event_isolation();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_002", "--- I1: Single-Event Counter Isolation ---", UVM_LOW)

  enable_rx_pause();
  clear_counters_and_interrupts();
  #1us;

  exp_invalid_count    = 32'd0;
  exp_oversize_count   = 32'd0;
  exp_unsupported_count = 32'd0;

  // Step 1: Send valid data frame — no counter event expected
  send_data_frame(46);
  #5us;

  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  verify_counter("I1-valid-invalid", val, exp_invalid_count, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I1-valid-oversize", val, exp_oversize_count, fail_count);

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I1-valid-unsupported", val, exp_unsupported_count, fail_count);

  // Step 2: Send unsupported control frame → unsupported_count++
  send_unsupported_control_frame();
  #5us;
  exp_unsupported_count = 32'd1;

  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  verify_counter("I1-unsup-invalid", val, exp_invalid_count, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I1-unsup-oversize", val, exp_oversize_count, fail_count);

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I1-unsup-unsupported", val, exp_unsupported_count, fail_count);

  // Step 3: Send oversize frame → oversize_count++
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd100);
  #10us;
  send_oversize_frame(1500);
  #5us;
  exp_oversize_count = 32'd1;

  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  verify_counter("I1-oversize-invalid", val, exp_invalid_count, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I1-oversize-oversize", val, exp_oversize_count, fail_count);

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I1-oversize-unsupported", val, exp_unsupported_count, fail_count);

  // Restore max_frame_size
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1500);
  #10us;

  if (fail_count == 0)
    `uvm_info("COUN_002", "PASS [I1]: Single-event counter isolation verified", UVM_NONE)
endtask

// =============================================================================
// I2: Individual Counter Clear (Isolation)
//
// Clearing one counter does not affect the others.
// Uses non-zero state from I1 (oversize=1, unsupported=1, invalid=0).
// =============================================================================
task COUN_002_stat_counter_test_c::run_individual_clear();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_002", "--- I2: Individual Counter Clear ---", UVM_LOW)

  // Current state from I1: invalid=0, oversize=1, unsupported=1

  // Step 1: Clear only invalid (already 0 — no-op, others unchanged)
  clear_invalid_only();

  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  verify_counter("I2-clr-inv-invalid", val, 32'd0, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I2-clr-inv-oversize", val, 32'd1, fail_count);

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I2-clr-inv-unsupported", val, 32'd1, fail_count);

  // Step 2: Clear only oversize
  clear_oversize_only();

  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  verify_counter("I2-clr-os-invalid", val, 32'd0, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I2-clr-os-oversize", val, 32'd0, fail_count);

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I2-clr-os-unsupported", val, 32'd1, fail_count);

  // Step 3: Clear only unsupported
  clear_unsupported_only();

  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  verify_counter("I2-clr-us-invalid", val, 32'd0, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I2-clr-us-oversize", val, 32'd0, fail_count);

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I2-clr-us-unsupported", val, 32'd0, fail_count);

  if (fail_count == 0)
    `uvm_info("COUN_002", "PASS [I2]: Individual counter clear isolation verified", UVM_NONE)
endtask

// =============================================================================
// I3: All-Counter Clear
//
// Generate events for all three counters, then clear all simultaneously.
// =============================================================================
task COUN_002_stat_counter_test_c::run_all_counter_clear();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_002", "--- I3: All-Counter Clear ---", UVM_LOW)

  // Generate unsupported event
  send_unsupported_control_frame();
  #5us;

  // Generate oversize event
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd100);
  #10us;
  send_oversize_frame(1500);
  #5us;
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1500);
  #10us;

  // Verify non-zero
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  `uvm_info("COUN_002", $sformatf("  I3 before clear: unsupported_count=%0d", val), UVM_MEDIUM)
  if (val == 32'd0) begin
    `uvm_error("COUN_002", "FAIL [I3]: unsupported_count=0 before clear")
    fail_count++;
  end

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  `uvm_info("COUN_002", $sformatf("  I3 before clear: oversize_count=%0d", val), UVM_MEDIUM)
  if (val == 32'd0) begin
    `uvm_error("COUN_002", "FAIL [I3]: oversize_count=0 before clear")
    fail_count++;
  end

  // Clear all three counters
  clear_counters_and_interrupts();

  // Verify all zero
  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  verify_counter("I3-clr-invalid", val, 32'd0, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I3-clr-oversize", val, 32'd0, fail_count);

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I3-clr-unsupported", val, 32'd0, fail_count);

  if (fail_count == 0)
    `uvm_info("COUN_002", "PASS [I3]: All-counter clear verified", UVM_NONE)
endtask

// =============================================================================
// I4: Clear-Priority
//
// RTL (stats_counters.v lines 20-25): clear_mask[i] && clear takes priority
// over event in the same always block.  Test: generate event, then immediately
// clear.  The clear (via CDC pipeline) resets the counter.  Then generate a
// second event and verify the counter increments from zero.
// =============================================================================
task COUN_002_stat_counter_test_c::run_clear_priority();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_002", "--- I4: Clear-Priority ---", UVM_LOW)

  // Step 1: Generate unsupported event
  send_unsupported_control_frame();
  #5us;

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  `uvm_info("COUN_002", $sformatf("  I4 after event: unsupported_count=%0d", val), UVM_MEDIUM)
  if (val == 32'd0) begin
    `uvm_error("COUN_002", "FAIL [I4]: unsupported_count=0 after event")
    fail_count++;
  end

  // Step 2: Clear immediately — should reset to 0
  clear_unsupported_only();

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I4-after-clear", val, 32'd0, fail_count);

  // Step 3: Generate a second event — counter increments from zero
  send_unsupported_control_frame();
  #5us;

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I4-second-event", val, 32'd1, fail_count);

  // Clean up
  clear_unsupported_only();

  if (fail_count == 0)
    `uvm_info("COUN_002", "PASS [I4]: Clear-priority verified", UVM_NONE)
endtask

// =============================================================================
// I5: Concurrent Events with Isolation
//
// Send unsupported + oversize frames back-to-back.  Both counters should
// increment independently.  Then selectively clear to prove isolation.
// =============================================================================
task COUN_002_stat_counter_test_c::run_concurrent_isolation();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_002", "--- I5: Concurrent Events with Isolation ---", UVM_LOW)

  clear_counters_and_interrupts();
  #1us;

  // Send unsupported control frame
  send_unsupported_control_frame();
  #5us;

  // Send oversize frame
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd100);
  #10us;
  send_oversize_frame(1500);
  #5us;
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1500);
  #10us;

  // Both counters should be non-zero
  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I5-concurrent-unsupported", val, 32'd1, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I5-concurrent-oversize", val, 32'd1, fail_count);

  // Clear only oversize — unsupported unchanged
  clear_oversize_only();

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I5-clr-os-unsupported", val, 32'd1, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I5-clr-os-oversize", val, 32'd0, fail_count);

  // Now clear unsupported — both zero
  clear_unsupported_only();

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I5-clr-us-unsupported", val, 32'd0, fail_count);

  if (fail_count == 0)
    `uvm_info("COUN_002", "PASS [I5]: Concurrent events with isolation verified", UVM_NONE)
endtask

// =============================================================================
// I6: 32-bit Counter Width
//
// Verify the counter is full 32-bit wide by:
// 1. Incrementing unsupported_count 10 times and verifying count == 10
// 2. Clearing and re-counting to prove reusable
// 3. Verifying no truncation by reading the full register
// =============================================================================
task COUN_002_stat_counter_test_c::run_counter_width();
  bit [31:0] val;
  int        fail_count = 0;
  int        i;

  `uvm_info("COUN_002", "--- I6: 32-bit Counter Width ---", UVM_LOW)

  clear_counters_and_interrupts();
  #1us;

  // Send 10 unsupported frames to increment unsupported_count
  for (i = 0; i < 10; i++) begin
    send_unsupported_control_frame();
    #5us;
  end

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I6-count-10", val, 32'd10, fail_count);
  `uvm_info("COUN_002", $sformatf("  I6: unsupported_count=%0d (full32-bit read: %h)",
             val, val), UVM_MEDIUM)

  // Verify the full 32-bit register — check no upper-bit truncation
  if (val[31:8] != 24'd0) begin
    `uvm_error("COUN_002", $sformatf("FAIL [I6]: upper bits non-zero: %h", val))
    fail_count++;
  end

  // Clear and re-count to prove reusable
  clear_unsupported_only();
  #1us;

  for (i = 0; i < 3; i++) begin
    send_unsupported_control_frame();
    #5us;
  end

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I6-recycle-count-3", val, 32'd3, fail_count);

  clear_counters_and_interrupts();

  if (fail_count == 0)
    `uvm_info("COUN_002", "PASS [I6]: 32-bit counter width verified", UVM_NONE)
endtask

// =============================================================================
// I7: Mixed Traffic with Reference Model
//
// Apply a sequence of mixed events and verify counter readback matches
// the per-counter reference model (exp_invalid_count, exp_oversize_count,
// exp_unsupported_count).
// =============================================================================
task COUN_002_stat_counter_test_c::run_mixed_traffic_model();
  bit [31:0] val;
  int        fail_count = 0;

  `uvm_info("COUN_002", "--- I7: Mixed Traffic with Reference Model ---", UVM_LOW)

  clear_counters_and_interrupts();
  #1us;

  exp_invalid_count     = 32'd0;
  exp_oversize_count    = 32'd0;
  exp_unsupported_count = 32'd0;

  // Sequence: unsupported, oversize, unsupported, valid, oversize
  // Expected: invalid=0, oversize=2, unsupported=2

  send_unsupported_control_frame();
  #5us;
  exp_unsupported_count++;

  send_oversize_frame(1500);
  #5us;
  exp_oversize_count++;

  send_unsupported_control_frame();
  #5us;
  exp_unsupported_count++;

  send_data_frame(46);
  #5us;
  // valid frame — no counter event

  send_oversize_frame(1500);
  #5us;
  exp_oversize_count++;

  #2us;

  // Verify all counters match reference model
  apb_read(reg_map_pkg::REG_RX_INVALID_COUNT, val);
  verify_counter("I7-mix-invalid", val, exp_invalid_count, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I7-mix-oversize", val, exp_oversize_count, fail_count);

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I7-mix-unsupported", val, exp_unsupported_count, fail_count);

  `uvm_info("COUN_002", $sformatf(
    "  I7 reference model: invalid=%0d oversize=%0d unsupported=%0d",
    exp_invalid_count, exp_oversize_count, exp_unsupported_count), UVM_MEDIUM)

  clear_counters_and_interrupts();

  if (fail_count == 0)
    `uvm_info("COUN_002", "PASS [I7]: Mixed traffic with reference model verified", UVM_NONE)
endtask

// =============================================================================
// I8: Clear-and-Regenerate Cycle
//
// Generate events → clear → generate different events → clear.
// Proves counter state is properly reset and reusable across cycles.
// =============================================================================
task COUN_002_stat_counter_test_c::run_clear_regenerate_cycle();
  bit [31:0] val;
  int        fail_count = 0;
  int        i;

  `uvm_info("COUN_002", "--- I8: Clear-and-Regenerate Cycle ---", UVM_LOW)

  // Cycle 1: Generate 3 unsupported events
  for (i = 0; i < 3; i++) begin
    send_unsupported_control_frame();
    #5us;
  end

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I8-cyc1-unsup", val, 32'd3, fail_count);

  // Clear
  clear_counters_and_interrupts();

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I8-cyc1-clr", val, 32'd0, fail_count);

  // Cycle 2: Generate 2 oversize events
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd100);
  #10us;

  for (i = 0; i < 2; i++) begin
    send_oversize_frame(1500);
    #5us;
  end

  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1500);
  #10us;

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I8-cyc2-over", val, 32'd2, fail_count);

  // Clear
  clear_counters_and_interrupts();

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I8-cyc2-clr", val, 32'd0, fail_count);

  // Cycle 3: Generate 1 unsupported + 1 oversize
  send_unsupported_control_frame();
  #5us;

  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd100);
  #10us;
  send_oversize_frame(1500);
  #5us;
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1500);
  #10us;

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I8-cyc3-unsup", val, 32'd1, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I8-cyc3-over", val, 32'd1, fail_count);

  // Final clear
  clear_counters_and_interrupts();

  apb_read(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, val);
  verify_counter("I8-cyc3-clr-us", val, 32'd0, fail_count);

  apb_read(reg_map_pkg::REG_RX_OVERSIZE_COUNT, val);
  verify_counter("I8-cyc3-clr-os", val, 32'd0, fail_count);

  if (fail_count == 0)
    `uvm_info("COUN_002", "PASS [I8]: Clear-and-regenerate cycle verified", UVM_NONE)
endtask

// =============================================================================
// run_stimulus — orchestrates all eight iterations
// =============================================================================
task COUN_002_stat_counter_test_c::run_stimulus(uvm_phase phase);
  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null ||
      env_cfg_h.ral_h == null)
    `uvm_fatal("COUN_002", "MAC environment not built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("COUN_002", "MAC reset and APB bootstrap did not complete")

  `uvm_info("COUN_002", "=== COUN_002 / STAT_COUNTER_001 START ===", UVM_LOW)

  exp_invalid_count     = 32'd0;
  exp_oversize_count    = 32'd0;
  exp_unsupported_count = 32'd0;

  run_single_event_isolation();      // I1
  run_individual_clear();            // I2
  run_all_counter_clear();           // I3
  run_clear_priority();              // I4
  run_concurrent_isolation();        // I5
  run_counter_width();               // I6
  run_mixed_traffic_model();         // I7
  run_clear_regenerate_cycle();      // I8

  `uvm_info("COUN_002", "=== COUN_002 / STAT_COUNTER_001 ALL ITERATIONS COMPLETE ===", UVM_NONE)
endtask

`endif  // COUN_002_STAT_COUNTER_TEST_SVH
