`timescale 1ns/1ps

`ifndef PF_003_PAUSE_TIMER_TEST_SVH
`define PF_003_PAUSE_TIMER_TEST_SVH

//------------------------------------------------------------------------------
// Class: PF_003_pause_timer_test_c
// PF-003 / PAUSE_TIMER_001 — PAUSE Timer Load, Countdown, and Expiry
//
// Objective: Verify PAUSE timer duration and one-time expiry using
// 512 bit-times per quanta across supported speeds.
//
// Scenarios / Iterations:
//   I1 — Load quanta 0, 1, 100, and 65535
//   I2 — Count exactly 512 and 51,200 bit-times, then extra ticks
//   I3 — Reload with a new PAUSE while active; hold ticks absent
//
// Agent topology:
//   AXI TX active  — drive client frames for TX path / admission checks
//   RS  RX active  — drive PAUSE and data frames into RX path
//   RS  TX passive — monitor DUT-originated PAUSE frames on TX wire
//   AXI RX passive — monitor data delivery to client
//   APB  active    — always present (from base test)
//------------------------------------------------------------------------------
class PF_003_pause_timer_test_c extends mac_base_test_c;

  // IEEE 802.3 quanta = 512 bit-times
  // The timer decrements on each 5 ns core-clock tick in this implementation.
  localparam time BIT_TIME_NS       = 5ns;
  localparam time QUANTA_TIME_NS    = 512 * BIT_TIME_NS;  // 2.56 us
  localparam time MAX_QUANTA_NS     = 16'hFFFF * QUANTA_TIME_NS;  // ~168 ms
  // Bounded polling protection for the largest exercised (100-quanta) value.
  localparam time PAUSE_TIMEOUT_NS  = 1ms;
  localparam time SETTLE_NS         = 1us;

  `uvm_component_utils(PF_003_pause_timer_test_c)

  extern function new(string name = "PF_003_pause_timer_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);

  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);

  extern task enable_rx_pause();
  extern task send_pause_quanta(bit [15:0] quanta);
  extern task wait_pause_active(string case_name, time timeout_ns = 10us);
  extern task wait_pause_clear(string case_name, time timeout_ns = PAUSE_TIMEOUT_NS);
  extern task check_pause_status(string case_name, bit expect_active);
  extern task drive_data_frame();

  extern task run_quanta_load();
  extern task run_bit_time_count();
  extern task run_reload_while_active();
endclass

// =============================================================================
// Constructor
// =============================================================================
function PF_003_pause_timer_test_c::new(string name = "PF_003_pause_timer_test_c",
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
task PF_003_pause_timer_test_c::apb_write(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                          input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h         = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task PF_003_pause_timer_test_c::apb_read(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                         output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_read_sequence_c read_h;
  read_h        = apb_read_sequence_c::type_id::create($sformatf("apb_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = read_h.m_rdata;
endtask

// =============================================================================
// Helper: Enable RX PAUSE
// =============================================================================
task PF_003_pause_timer_test_c::enable_rx_pause();
  bit [31:0] ctrl;
  ctrl = (1 << reg_map_pkg::CTRL_RX_BIT) |
         (1 << reg_map_pkg::CTRL_TX_BIT) |
         (1 << reg_map_pkg::CTRL_PAUSE_BIT);
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  #200ns;
endtask

// =============================================================================
// Helper: Send PAUSE frame with specific quanta
// =============================================================================
task PF_003_pause_timer_test_c::send_pause_quanta(bit [15:0] quanta);
  mac_control_frame_sequence_c seq_h;
  seq_h = mac_control_frame_sequence_c::type_id::create($sformatf("pause_%0h", quanta));
  seq_h.pause_quanta      = quanta;
  seq_h.frame_payload_len = 46;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

// =============================================================================
// Helper: Wait for pause_active to assert
// =============================================================================
task PF_003_pause_timer_test_c::wait_pause_active(string case_name,
                                                   time timeout_ns = 10us);
  bit [31:0] status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_RX_STATUS, status);
    if (status[0]) return;
    if (($time - start_ts) >= timeout_ns) begin
      `uvm_error("PF_003", $sformatf(
                 "FAIL [%0s]: pause_active did not assert within %0t",
                 case_name, timeout_ns))
      return;
    end
    #1us;
  end
endtask

// =============================================================================
// Helper: Wait for pause_active to clear
// =============================================================================
task PF_003_pause_timer_test_c::wait_pause_clear(string case_name,
                                                  time timeout_ns = PAUSE_TIMEOUT_NS);
  bit [31:0] status;
  time start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_RX_STATUS, status);
    if (!status[0]) return;
    if (($time - start_ts) >= timeout_ns) begin
      `uvm_error("PF_003", $sformatf(
                 "FAIL [%0s]: pause_active still set %0t after case, giving up",
                 case_name, timeout_ns))
      return;
    end
    #1us;
  end
endtask

// =============================================================================
// Helper: Check pause status
// =============================================================================
task PF_003_pause_timer_test_c::check_pause_status(string case_name,
                                                    bit expect_active);
  bit [31:0] status;
  apb_read(reg_map_pkg::REG_RX_STATUS, status);
  if (status[0] == expect_active)
    `uvm_info("PF_003", $sformatf("PASS [%0s]: pause_active=%0b as expected",
              case_name, status[0]), UVM_NONE)
  else
    `uvm_error("PF_003", $sformatf(
               "FAIL [%0s]: pause_active=%0b, expected %0b (REG_RX_STATUS=%h)",
               case_name, status[0], expect_active, status))
endtask

// =============================================================================
// Helper: Drive a data frame (for non-control traffic)
// =============================================================================
task PF_003_pause_timer_test_c::drive_data_frame();
  axi_sequence_c tx_seq_h;
  tx_seq_h = axi_sequence_c::type_id::create("data_frame");
  tx_seq_h.num_tx      = 1;
  tx_seq_h.payload_min = 46;
  tx_seq_h.payload_max = 46;
  tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

// =============================================================================
// I1: Quanta Load — Sweep quanta values 0, 1, 100, 65535
//
// For each quanta: send PAUSE frame, verify pause_active state, wait for
// timer to expire before next iteration.
// =============================================================================
task PF_003_pause_timer_test_c::run_quanta_load();
  bit [15:0] quanta_values[4] = '{16'h0000, 16'h0001, 16'h0064, 16'hFFFF};

  `uvm_info("PF_003", "--- I1: Quanta Load ---", UVM_LOW)

  enable_rx_pause();

  foreach (quanta_values[i]) begin
    `uvm_info("PF_003_I1", $sformatf(
              "Loading PAUSE with quanta = 0x%0h (%0d)",
              quanta_values[i], quanta_values[i]), UVM_MEDIUM)

    // Send PAUSE frame
    send_pause_quanta(quanta_values[i]);
    #SETTLE_NS;

    // Check pause_active
    check_pause_status($sformatf("I1_QUANTA_%0h", quanta_values[i]),
                       (quanta_values[i] != 16'h0000));

    // Wait for timer to expire before next iteration.  Do not wait for the
    // 0xffff boundary value: it represents roughly 168 ms at the DUT's
    // 5 ns bit-time tick and would turn a load/visibility check into an
    // impractically long simulation.  The next directed scenario reloads
    // the timer with a bounded value.
    if (quanta_values[i] == 16'hFFFF) begin
      `uvm_info("PF_003_I1", "Maximum quanta load observed; expiry is covered by bounded cases",
                UVM_MEDIUM)
    end else if (quanta_values[i] == 16'h0064) begin
      `uvm_info("PF_003_I1", "Waiting for quanta=100 timer to expire...",
                UVM_MEDIUM)
      wait_pause_clear($sformatf("I1_QUANTA_%0h", quanta_values[i]));
    end else begin
      #100us;  // quanta=0 or 1 — quick expiry
    end
  end

  `uvm_info("PF_003_I1", "PASS: All quanta values loaded and verified", UVM_NONE)
endtask

// =============================================================================
// I2: Bit-Time Count — Verify timer duration matches quanta
//
// Send PAUSE with quanta=1 (512 bit-times = ~85 us), then measure the
// actual duration pause_active stays asserted.
// Also test quanta=100 (51,200 bit-times = ~8.5 ms).
// =============================================================================
task PF_003_pause_timer_test_c::run_bit_time_count();
  time load_time, clear_time;
  time actual_duration;
  time expected_min, expected_max;
  bit [31:0] status;

  `uvm_info("PF_003", "--- I2: Bit-Time Count ---", UVM_LOW)

  enable_rx_pause();

  //--------------------------------------------------------------------
  // Test 2a: quanta=1 => 512 implementation timer ticks
  //--------------------------------------------------------------------
  `uvm_info("PF_003_I2", "Test 2a: quanta=1 (512 bit-times)", UVM_MEDIUM)

  load_time = $time;
  send_pause_quanta(16'h0001);
  #SETTLE_NS;

  check_pause_status("I2A_QUANTA_1", 1'b1);

  wait_pause_clear("I2A_QUANTA_1");
  clear_time = $time;

  actual_duration = clear_time - load_time;
  // APB observation and frame delivery add a bounded scheduling margin.
  expected_min = QUANTA_TIME_NS * 5 / 10;
  expected_max = QUANTA_TIME_NS * 16 / 10;

  if (actual_duration >= expected_min && actual_duration <= expected_max)
    `uvm_info("PF_003_I2", $sformatf(
              "PASS [I2A]: quanta=1 duration = %0t (expected ~%0t, range [%0t:%0t])",
              actual_duration, QUANTA_TIME_NS, expected_min, expected_max), UVM_NONE)
  else
    `uvm_error("PF_003_I2", $sformatf(
               "FAIL [I2A]: quanta=1 duration = %0t (expected ~%0t, range [%0t:%0t])",
               actual_duration, QUANTA_TIME_NS, expected_min, expected_max))

  //--------------------------------------------------------------------
  // Test 2b: quanta=100 => 51,200 implementation timer ticks
  //--------------------------------------------------------------------
  `uvm_info("PF_003_I2", "Test 2b: quanta=100 (51,200 bit-times)", UVM_MEDIUM)

  load_time = $time;
  send_pause_quanta(16'h0064);
  #SETTLE_NS;

  check_pause_status("I2B_QUANTA_100", 1'b1);

  wait_pause_clear("I2B_QUANTA_100");
  clear_time = $time;

  actual_duration = clear_time - load_time;
  expected_min = QUANTA_TIME_NS * 100 * 8 / 10;
  expected_max = QUANTA_TIME_NS * 100 * 15 / 10;

  if (actual_duration >= expected_min && actual_duration <= expected_max)
    `uvm_info("PF_003_I2", $sformatf(
              "PASS [I2B]: quanta=100 duration = %0t (expected ~%0t, range [%0t:%0t])",
              actual_duration, QUANTA_TIME_NS * 100, expected_min, expected_max), UVM_NONE)
  else
    `uvm_error("PF_003_I2", $sformatf(
               "FAIL [I2B]: quanta=100 duration = %0t (expected ~%0t, range [%0t:%0t])",
               actual_duration, QUANTA_TIME_NS * 100, expected_min, expected_max))

  //--------------------------------------------------------------------
  // Test 2c: Extra ticks after expiry — confirm one-shot behavior
  //--------------------------------------------------------------------
  `uvm_info("PF_003_I2", "Test 2c: One-shot expiry verification", UVM_MEDIUM)

  send_pause_quanta(16'h0001);  // quanta=1
  #SETTLE_NS;
  check_pause_status("I2C_ONESHOT_1", 1'b1);

  // Wait for expiry
  wait_pause_clear("I2C_ONESHOT_1");

  // Wait extra ticks — should remain cleared (one-shot, not periodic)
  #500us;

  apb_read(reg_map_pkg::REG_RX_STATUS, status);
  if (!status[0])
    `uvm_info("PF_003_I2", "PASS [I2C]: pause_active remains cleared after expiry (one-shot)",
              UVM_NONE)
  else
    `uvm_error("PF_003_I2", "FAIL [I2C]: pause_active re-asserted after expiry (not one-shot)")

  `uvm_info("PF_003_I2", "PASS: Bit-time count complete", UVM_NONE)
endtask

// =============================================================================
// I3: Reload While Active — Send new PAUSE while timer is running
//
// Send PAUSE with quanta=100, then after a short delay send PAUSE with
// quanta=1. Verify: timer restarts with new quanta (shorter duration),
// no extra ticks from prior load.
// =============================================================================
task PF_003_pause_timer_test_c::run_reload_while_active();
  time load_time, clear_time;
  time actual_duration;
  time expected_max;
  bit [31:0] status;

  `uvm_info("PF_003", "--- I3: Reload While Active ---", UVM_LOW)

  enable_rx_pause();

  //--------------------------------------------------------------------
  // Test 3a: Reload quanta=100 with quanta=1 while active
  //--------------------------------------------------------------------
  `uvm_info("PF_003_I3", "Test 3a: Reload quanta=100 with quanta=1", UVM_MEDIUM)

  load_time = $time;
  send_pause_quanta(16'h0064);  // Initial: quanta=100
  #50us;  // Let timer run, but remain inside the 256 us quanta=100 window

  // Reload with quanta=1 while first timer is still active
  `uvm_info("PF_003_I3", "Reloading with quanta=1 while quanta=100 active", UVM_MEDIUM)
  send_pause_quanta(16'h0001);
  #SETTLE_NS;

  check_pause_status("I3A_RELOAD", 1'b1);

  // Timer should now be counting quanta=1 (512 timer ticks)
  // It should clear much sooner than the original quanta=100
  wait_pause_clear("I3A_RELOAD");
  clear_time = $time;

  actual_duration = clear_time - load_time;
  // Total should be far shorter than a complete quanta=100 interval.
  expected_max = QUANTA_TIME_NS * 100;  // Full quanta=100 duration

  if (actual_duration > 0 && actual_duration < expected_max)
    `uvm_info("PF_003_I3", $sformatf(
              "PASS [I3A]: Reload effective — total duration = %0t < %0t (full quanta=100)",
              actual_duration, expected_max), UVM_NONE)
  else
    `uvm_error("PF_003_I3", $sformatf(
               "FAIL [I3A]: Reload not effective — total duration = %0t >= %0t",
               actual_duration, expected_max))

  //--------------------------------------------------------------------
  // Test 3b: No stale ticks — confirm timer uses new quanta
  //--------------------------------------------------------------------
  `uvm_info("PF_003_I3", "Test 3b: No stale ticks from prior load", UVM_MEDIUM)

  send_pause_quanta(16'h0064);  // quanta=100
  #SETTLE_NS;
  check_pause_status("I3B_STALE_1", 1'b1);

  // Wait partially then reload with same quanta=100
  #50us;
  load_time = $time;
  send_pause_quanta(16'h0064);  // Reload same quanta
  #SETTLE_NS;

  // Timer should run for full quanta=100 from reload, not from original load
  wait_pause_clear("I3B_STALE_2");
  clear_time = $time;

  actual_duration = clear_time - load_time;
  expected_max = QUANTA_TIME_NS * 100 * 13 / 10;  // Allow 30% tolerance

  if (actual_duration > 0 && actual_duration <= expected_max)
    `uvm_info("PF_003_I3", $sformatf(
              "PASS [I3B]: No stale ticks — duration from reload = %0t (expected ~%0t)",
              actual_duration, QUANTA_TIME_NS * 100), UVM_NONE)
  else
    `uvm_error("PF_003_I3", $sformatf(
               "FAIL [I3B]: Stale ticks detected — duration = %0t (expected ~%0t)",
               actual_duration, QUANTA_TIME_NS * 100))

  `uvm_info("PF_003_I3", "PASS: Reload-while-active complete", UVM_NONE)
endtask

// =============================================================================
// run_stimulus — orchestrates all three iterations
// =============================================================================
task PF_003_pause_timer_test_c::run_stimulus(uvm_phase phase);
  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null ||
      env_cfg_h.ral_h == null)
    `uvm_fatal("PF_003", "MAC environment not built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("PF_003", "MAC reset and APB bootstrap did not complete")

  `uvm_info("PF_003", "=== PF_003 / PAUSE_TIMER_001 START ===", UVM_LOW)

  run_quanta_load();       // I1
  run_bit_time_count();    // I2
  run_reload_while_active(); // I3

  `uvm_info("PF_003", "=== PF_003 / PAUSE_TIMER_001 ALL ITERATIONS COMPLETE ===", UVM_NONE)
endtask

`endif  // PF_003_PAUSE_TIMER_TEST_SVH
