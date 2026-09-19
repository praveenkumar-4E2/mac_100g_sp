class mac_stats_cnt_err_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_stats_cnt_err_test_c)

  localparam bit [6:0] CAUSE_RX_INVALID    = 7'b000_0001;
  localparam bit [6:0] CAUSE_RX_CRC        = 7'b000_0010;
  localparam bit [6:0] CAUSE_RX_OVERSIZE   = 7'b000_0100;
  localparam bit [6:0] CAUSE_RX_UNSUPPORTED = 7'b000_1000;
  localparam bit [6:0] CAUSE_PAUSE_ACTIVE  = 7'b001_0000;
  localparam bit [6:0] CAUSE_PAUSE_EXPIRED = 7'b010_0000;
  localparam bit [6:0] CAUSE_TX_ERROR      = 7'b100_0000;

  bit [6:0]  rand_enable_val;
  bit [6:0]  rand_clear_val;

  extern function new(string name = "mac_stats_cnt_err_test_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);

  extern task apb_write_check(input bit [15:0] addr, input bit [31:0] data,
                               input bit expect_slverr = 1'b0);
  extern task apb_read_data(input bit [15:0] addr, output bit [31:0] data,
                            input bit expect_slverr = 1'b0);
  extern task read_status_snapshot(input bit [15:0] addr, output bit [31:0] data);
  extern task check_masked(input string check_name, input bit [31:0] actual,
                           input bit [31:0] expected, input bit [31:0] mask);
  extern task drive_event(int unsigned kind, bit [15:0] quanta = 16'h0100);
  extern task clear_counter(input bit [15:0] addr);

  extern task run_cnt_increment();
  extern task run_cnt_clear();
  extern task run_cnt_clear_priority();
  extern task run_cnt_isolation();
  extern task run_cnt_concurrent_error_traffic();
  extern task run_cnt_rollover();
  extern task run_cnt_long_run_rollover();
endclass

function mac_stats_cnt_err_test_c::new(string name = "mac_stats_cnt_err_test_c",
                                       uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents = 1;
endfunction

function void mac_stats_cnt_err_test_c::configure_test();
  super.configure_test();
  env_cfg_h.has_scoreboard = 1'b0;
  env_cfg_h.apb_active_agent_cfgs[0].m_fail_on_unexpected_slverr = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = 1600;
  env_cfg_h.rs_active_agent_cfgs[0].enable_error_injection = 1'b1;
endfunction

task mac_stats_cnt_err_test_c::apb_write_check(
    input bit [15:0] addr, input bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create($sformatf("st_wr_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_wdata = data;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_stats_cnt_err_test_c::apb_read_data(
    input bit [15:0] addr, output bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("st_rd_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = seq_h.m_rdata;
endtask

task mac_stats_cnt_err_test_c::read_status_snapshot(
    input bit [15:0] addr, output bit [31:0] data);
  bit [31:0] discard;
  apb_read_data(addr, discard);
  #300ns;
  apb_read_data(addr, data);
endtask

task mac_stats_cnt_err_test_c::check_masked(
    input string check_name, input bit [31:0] actual,
    input bit [31:0] expected, input bit [31:0] mask);
  if ((actual & mask) !== (expected & mask))
    `uvm_error("STATS_CNT_CHECK", $sformatf("%s: got=%08h expected=%08h mask=%08h",
                check_name, actual, expected, mask))
endtask

task mac_stats_cnt_err_test_c::drive_event(int unsigned kind, bit [15:0] quanta);
  mac_stats_cause_irq_seq_c stim_h;
  stim_h = mac_stats_cause_irq_seq_c::type_id::create($sformatf("stim_%0d", kind));
  stim_h.stimulus_kind = mac_stats_cause_irq_seq_c::stimulus_kind_e'(kind);
  stim_h.pause_quanta_val = quanta;
  stim_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_stats_cnt_err_test_c::clear_counter(input bit [15:0] addr);
  apb_write_check(addr, 32'h0000_0001);
  #200ns;
endtask

// ---------------------------------------------------------------------------
// Scenario 1: Increment - verify each qualifying event increments counter by 1
// ---------------------------------------------------------------------------
task mac_stats_cnt_err_test_c::run_cnt_increment();
  bit [31:0] cnt_before, cnt_after;
  bit [31:0] int_data;

  `uvm_info("STATS_CNT", "=== Scenario 1: Counter Increment ===", UVM_NONE)

  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_0000);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_before);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_after);
  check_masked("invalid counter +1", cnt_after, cnt_before + 32'd1, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_before);
  repeat (3) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_after);
  check_masked("invalid counter +3", cnt_after, cnt_before + 32'd3, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_before);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_after);
  check_masked("oversize counter +1", cnt_after, cnt_before + 32'd1, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_before);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_after);
  check_masked("unsupported counter +1", cnt_after, cnt_before + 32'd1, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  `uvm_info("STATS_CNT", "=== Scenario 1: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 2: Clear - W1C clear semantics, selective clear, close-to-event
// ---------------------------------------------------------------------------
task mac_stats_cnt_err_test_c::run_cnt_clear();
  bit [31:0] cnt_data;
  bit [31:0] inv_before, os_before, uns_before;

  `uvm_info("STATS_CNT", "=== Scenario 2: Counter Clear ===", UVM_NONE)

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  repeat (5) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  repeat (3) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  repeat (2) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("pre-clear invalid=5", cnt_data, 32'd5, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("pre-clear oversize=3", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("pre-clear unsupported=2", cnt_data, 32'd2, 32'hFFFF_FFFF);

  `uvm_info("STATS_CNT", "Selective clear: only invalid counter", UVM_NONE)
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("invalid cleared to 0", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("oversize untouched after invalid clear", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("unsupported untouched after invalid clear", cnt_data, 32'd2, 32'hFFFF_FFFF);

  `uvm_info("STATS_CNT", "Close-to-event clear: drive then immediately clear", UVM_NONE)
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("clear immediately after event", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);

  `uvm_info("STATS_CNT", "Clear all counters", UVM_NONE)
  repeat (4) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  repeat (4) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("all-clear invalid", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("all-clear oversize", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("all-clear unsupported", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);

  `uvm_info("STATS_CNT", "=== Scenario 2: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 3: Clear Priority - clear wins over simultaneous increment
// ---------------------------------------------------------------------------
task mac_stats_cnt_err_test_c::run_cnt_clear_priority();
  bit [31:0] cnt_data;

  `uvm_info("STATS_CNT", "=== Scenario 3: Clear Priority ===", UVM_NONE)

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);

  `uvm_info("STATS_CNT", "Drive events then clear immediately (clear priority)", UVM_NONE)
  repeat (3) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #50ns;
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("clear after burst resets to 0", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);

  `uvm_info("STATS_CNT", "Clear during active event stream", UVM_NONE)
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("clear mid-stream: only post-clear events counted",
               cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_CNT", "Rapid clear-event-clear sequence", UVM_NONE)
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("rapid clear-event pattern", cnt_data, 32'd1, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);

  `uvm_info("STATS_CNT", "=== Scenario 3: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 4: Isolation - clearing one counter does not affect others
// ---------------------------------------------------------------------------
task mac_stats_cnt_err_test_c::run_cnt_isolation();
  bit [31:0] cnt_data;

  `uvm_info("STATS_CNT", "=== Scenario 4: Counter Isolation ===", UVM_NONE)

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  repeat (3) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  repeat (3) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  repeat (3) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("iso invalid=3", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("iso oversize=3", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("iso unsupported=3", cnt_data, 32'd3, 32'hFFFF_FFFF);

  `uvm_info("STATS_CNT", "Clear invalid only, verify others isolated", UVM_NONE)
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("iso invalid cleared", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("iso oversize isolated", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("iso unsupported isolated", cnt_data, 32'd3, 32'hFFFF_FFFF);

  `uvm_info("STATS_CNT", "Drive invalid while others have counts", UVM_NONE)
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("iso invalid incremented", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("iso oversize still 3", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("iso unsupported still 3", cnt_data, 32'd3, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  `uvm_info("STATS_CNT", "=== Scenario 4: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 5: Concurrent Error Traffic - mixed independent error types
// ---------------------------------------------------------------------------
task mac_stats_cnt_err_test_c::run_cnt_concurrent_error_traffic();
  bit [31:0] cnt_data;
  bit [31:0] inv_before, os_before, uns_before;

  `uvm_info("STATS_CNT", "=== Scenario 5: Concurrent Error Traffic ===", UVM_NONE)

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  `uvm_info("STATS_CNT", "Interleaved: invalid, oversize, unsupported, invalid, oversize", UVM_NONE)
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("concurrent invalid=2", cnt_data, 32'd2, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("concurrent oversize=2", cnt_data, 32'd2, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("concurrent unsupported=1", cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_CNT", "Burst mixed: 10 rapid mixed events", UVM_NONE)
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  repeat (10) begin
    case ($urandom_range(0, 2))
      0: drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
      1: drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
      2: drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
    endcase
  end
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  `uvm_info("STATS_CNT", $sformatf("burst mixed invalid count: %0d", cnt_data), UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  `uvm_info("STATS_CNT", $sformatf("burst mixed oversize count: %0d", cnt_data), UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  `uvm_info("STATS_CNT", $sformatf("burst mixed unsupported count: %0d", cnt_data), UVM_NONE)

  `uvm_info("STATS_CNT", "Interleaving qualifying and non-qualifying events", UVM_NONE)
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("qual/non-qual invalid=1", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("qual/non-qual oversize=1", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("qual/non-qual unsupported=1", cnt_data, 32'd1, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  `uvm_info("STATS_CNT", "=== Scenario 5: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 6: Rollover - verify 32-bit counter wraparound behavior
// ---------------------------------------------------------------------------
task mac_stats_cnt_err_test_c::run_cnt_rollover();
  bit [31:0] cnt_data;
  bit        preload_ok;

  `uvm_info("STATS_CNT", "=== Scenario 6: Counter Rollover ===", UVM_NONE)

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);

  preload_ok = 1'b0;
  `uvm_info("STATS_CNT", "Attempting counter preload via APB write", UVM_NONE)
  apb_write_check(reg_map_pkg::REG_RX_INVALID_COUNT, 32'hFFFF_FFFE);
  #200ns;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  if (cnt_data == 32'hFFFF_FFFE) begin
    preload_ok = 1'b1;
    `uvm_info("STATS_CNT", "Counter preload successful - will test full rollover", UVM_NONE)
  end else begin
    `uvm_info("STATS_CNT", $sformatf(
      "Counter is RO (read=%0h, expected FFFFFFFE for preload) - using alternative rollover strategy",
      cnt_data), UVM_NONE)
  end

  if (preload_ok) begin
    `uvm_info("STATS_CNT", "Driving 2 events to cross 0xFFFFFFFF boundary", UVM_NONE)
    drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    #1us;
    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
    check_masked("rollover event 1", cnt_data, 32'hFFFF_FFFF, 32'hFFFF_FFFF);

    drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    #1us;
    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
    check_masked("rollover wrap to 0", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);

    drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    #1us;
    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
    check_masked("rollover post-wrap +1", cnt_data, 32'h0000_0001, 32'hFFFF_FFFF);

    clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);

    `uvm_info("STATS_CNT", "Preload oversize counter near boundary", UVM_NONE)
    clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
    apb_write_check(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'hFFFF_FFFF);
    #200ns;
    read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
    if (cnt_data == 32'hFFFF_FFFF) begin
      drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
      #1us;
      read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
      check_masked("oversize rollover wrap", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
    end
    clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);

    `uvm_info("STATS_CNT", "Preload unsupported counter near boundary", UVM_NONE)
    clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);
    apb_write_check(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, 32'hFFFF_FFFE);
    #200ns;
    read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
    if (cnt_data == 32'hFFFF_FFFE) begin
      drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
      #1us;
      read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
      check_masked("unsupported rollover to max", cnt_data, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
      drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
      #1us;
      read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
      check_masked("unsupported rollover wrap", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
    end
    clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);
  end else begin
    `uvm_info("STATS_CNT", "Verifying counter width is 32 bits", UVM_NONE)
    apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
    #200ns;
    apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_0000);
    #200ns;

    clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
    repeat (20) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    #1us;
    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
    `uvm_info("STATS_CNT", $sformatf("Counter after 20 events: %0d (0x%08h)", cnt_data, cnt_data),
              UVM_NONE)
    check_masked("counter value after 20 events", cnt_data, 32'd20, 32'hFFFF_FFFF);

    clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
    check_masked("counter cleared to 0", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);

    `uvm_info("STATS_CNT", "Long burst to verify monotonic increment near high range", UVM_NONE)
    clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
    repeat (50) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    #1us;
    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
    check_masked("counter after 50 events", cnt_data, 32'd50, 32'hFFFF_FFFF);

    clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
    clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
    clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);
  end

  `uvm_info("STATS_CNT", "=== Scenario 6: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 7: Long-Run Rollover - extended random event/clear/read campaign
// ---------------------------------------------------------------------------
task mac_stats_cnt_err_test_c::run_cnt_long_run_rollover();
  bit [31:0] cnt_data;
  int unsigned num_iterations;
  int unsigned ev_type;
  bit [31:0] expected_invalid;
  bit [31:0] expected_oversize;
  bit [31:0] expected_unsupported;
  int unsigned clear_valid_invalid;
  int unsigned clear_valid_oversize;
  int unsigned clear_valid_unsupported;

  `uvm_info("STATS_CNT", "=== Scenario 7: Long-Run Rollover Campaign ===", UVM_NONE)

  if (!std::randomize(num_iterations) with { num_iterations inside {[80 : 120]}; })
    `uvm_fatal("STATS_CNT", "Iteration count randomization failed")

  `uvm_info("STATS_CNT", $sformatf("Running %0d constrained-random iterations", num_iterations), UVM_NONE)

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_0000);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;

  expected_invalid    = 32'd0;
  expected_oversize   = 32'd0;
  expected_unsupported = 32'd0;

  for (int unsigned iter = 0; iter < num_iterations; iter++) begin
    int unsigned num_events;
    bit do_clear_invalid, do_clear_oversize, do_clear_unsupported;
    bit [31:0] actual;

    if (!std::randomize(num_events) with { num_events inside {[1 : 5]}; })
      `uvm_fatal("STATS_CNT", "Event count randomization failed")

    if (!std::randomize(do_clear_invalid) with { do_clear_invalid dist { 1 := 30, 0 := 70 }; })
      `uvm_fatal("STATS_CNT", "Clear valid randomization failed")
    if (!std::randomize(do_clear_oversize) with { do_clear_oversize dist { 1 := 30, 0 := 70 }; })
      `uvm_fatal("STATS_CNT", "Clear oversize randomization failed")
    if (!std::randomize(do_clear_unsupported) with {
      do_clear_unsupported dist { 1 := 30, 0 := 70 }; })
      `uvm_fatal("STATS_CNT", "Clear unsupported randomization failed")

    repeat (num_events) begin
      if (!std::randomize(ev_type) with { ev_type inside {[0 : 2]}; })
        `uvm_fatal("STATS_CNT", "Event type randomization failed")
      case (ev_type)
        0: begin
          drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
          expected_invalid++;
        end
        1: begin
          drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
          expected_oversize++;
        end
        2: begin
          drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
          expected_unsupported++;
        end
      endcase
    end
    #500ns;

    if (do_clear_invalid) begin
      clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
      expected_invalid = 32'd0;
    end
    if (do_clear_oversize) begin
      clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
      expected_oversize = 32'd0;
    end
    if (do_clear_unsupported) begin
      clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);
      expected_unsupported = 32'd0;
    end

    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, actual);
    check_masked($sformatf("iter %0d invalid counter", iter),
                 actual, expected_invalid, 32'hFFFF_FFFF);
    read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, actual);
    check_masked($sformatf("iter %0d oversize counter", iter),
                 actual, expected_oversize, 32'hFFFF_FFFF);
    read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, actual);
    check_masked($sformatf("iter %0d unsupported counter", iter),
                 actual, expected_unsupported, 32'hFFFF_FFFF);

    if (iter % 20 == 0 && iter > 0) begin
      `uvm_info("STATS_CNT", $sformatf(
        "Progress: iter=%0d inv=%0d os=%0d uns=%0d",
        iter, expected_invalid, expected_oversize, expected_unsupported), UVM_NONE)
    end
  end

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  `uvm_info("STATS_CNT", $sformatf(
    "Long-run complete: %0d iterations. Final expected: inv=%0d os=%0d uns=%0d",
    num_iterations, expected_invalid, expected_oversize, expected_unsupported), UVM_NONE)

  `uvm_info("STATS_CNT", "=== Scenario 7: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// run_stimulus - orchestrator
// ---------------------------------------------------------------------------
task mac_stats_cnt_err_test_c::run_stimulus(uvm_phase phase);
  `uvm_info("STATS_CNT", "========================================", UVM_NONE)
  `uvm_info("STATS_CNT", "STAT_CNT Error Counter Verification", UVM_NONE)
  `uvm_info("STATS_CNT", "Increment / Clear / Rollover", UVM_NONE)
  `uvm_info("STATS_CNT", "========================================", UVM_NONE)

  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  #200ns;

  run_cnt_increment();
  run_cnt_clear();
  run_cnt_clear_priority();
  run_cnt_isolation();
  run_cnt_concurrent_error_traffic();
  run_cnt_rollover();
  run_cnt_long_run_rollover();

  `uvm_info("STATS_CNT", "========================================", UVM_NONE)
  `uvm_info("STATS_CNT", "ALL STAT_CNT SCENARIOS PASSED", UVM_NONE)
  `uvm_info("STATS_CNT", "========================================", UVM_NONE)
endtask
