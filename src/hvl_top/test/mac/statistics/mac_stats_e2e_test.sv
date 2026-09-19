class mac_stats_e2e_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_stats_e2e_test_c)

  localparam bit [6:0] CAUSE_RX_INVALID    = 7'b000_0001;
  localparam bit [6:0] CAUSE_RX_CRC        = 7'b000_0010;
  localparam bit [6:0] CAUSE_RX_OVERSIZE   = 7'b000_0100;
  localparam bit [6:0] CAUSE_RX_UNSUPPORTED = 7'b000_1000;
  localparam bit [6:0] CAUSE_PAUSE_ACTIVE  = 7'b001_0000;
  localparam bit [6:0] CAUSE_PAUSE_EXPIRED = 7'b010_0000;
  localparam bit [6:0] CAUSE_TX_ERROR      = 7'b100_0000;

  extern function new(string name = "mac_stats_e2e_test_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);

  extern task apb_write_check(input bit [15:0] addr, input bit [31:0] data,
                               input bit expect_slverr = 1'b0);
  extern task apb_read_data(input bit [15:0] addr, output bit [31:0] data,
                            input bit expect_slverr = 1'b0);
  extern task read_status_snapshot(input bit [15:0] addr, output bit [31:0] data);
  extern task check_masked(input string check_name, input bit [31:0] actual,
                           input bit [31:0] expected, input bit [31:0] mask);
  extern task drive_rx_event(int unsigned kind, bit [15:0] quanta = 16'h0100);
  extern task drive_tx_traffic(int unsigned count = 5);
  extern task drive_pause_frame(bit [15:0] quanta = 16'h0010);
  extern task clear_counter(input bit [15:0] addr);
  extern task clear_all_counters();
  extern task clear_all_status();

  extern task run_e2e_tx_no_counter_incr();
  extern task run_e2e_rx_known_counts();
  extern task run_e2e_error_control_pause();
  extern task run_e2e_read_individual_all();
  extern task run_e2e_interleave_qual_nonqual();
  extern task run_e2e_vary_read_timing();
  extern task run_e2e_random_campaign();
endclass

function mac_stats_e2e_test_c::new(string name = "mac_stats_e2e_test_c",
                                   uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents = 1;
  num_rs_active_agents  = 1;
endfunction

function void mac_stats_e2e_test_c::configure_test();
  super.configure_test();
  env_cfg_h.has_scoreboard = 1'b0;
  env_cfg_h.apb_active_agent_cfgs[0].m_fail_on_unexpected_slverr = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = 1600;
  env_cfg_h.rs_active_agent_cfgs[0].enable_error_injection = 1'b1;
  env_cfg_h.axi_active_agent_cfgs[0].enable_error_injection = 1'b0;
endfunction

task mac_stats_e2e_test_c::apb_write_check(
    input bit [15:0] addr, input bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create($sformatf("e2e_wr_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_wdata = data;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_stats_e2e_test_c::apb_read_data(
    input bit [15:0] addr, output bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("e2e_rd_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = seq_h.m_rdata;
endtask

task mac_stats_e2e_test_c::read_status_snapshot(
    input bit [15:0] addr, output bit [31:0] data);
  bit [31:0] discard;
  apb_read_data(addr, discard);
  #300ns;
  apb_read_data(addr, data);
endtask

task mac_stats_e2e_test_c::check_masked(
    input string check_name, input bit [31:0] actual,
    input bit [31:0] expected, input bit [31:0] mask);
  if ((actual & mask) !== (expected & mask))
    `uvm_error("STATS_E2E", $sformatf("%s: got=%08h expected=%08h mask=%08h",
                check_name, actual, expected, mask))
endtask

task mac_stats_e2e_test_c::drive_rx_event(int unsigned kind, bit [15:0] quanta);
  mac_stats_cause_irq_seq_c stim_h;
  stim_h = mac_stats_cause_irq_seq_c::type_id::create($sformatf("rx_stim_%0d", kind));
  stim_h.stimulus_kind = mac_stats_cause_irq_seq_c::stimulus_kind_e'(kind);
  stim_h.pause_quanta_val = quanta;
  stim_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_stats_e2e_test_c::drive_tx_traffic(int unsigned count);
  axi_sequence_c tx_seq_h;
  tx_seq_h = axi_sequence_c::type_id::create("e2e_tx_seq");
  if (!tx_seq_h.randomize() with { soft num_tx == count; })
    `uvm_fatal("STATS_E2E", "TX sequence randomization failed")
  tx_seq_h.start(env_h.virtual_sequencer_h.client_ingress_seqr_h);
endtask

task mac_stats_e2e_test_c::drive_pause_frame(bit [15:0] quanta);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_PAUSE_ACTIVE, quanta);
endtask

task mac_stats_e2e_test_c::clear_counter(input bit [15:0] addr);
  apb_write_check(addr, 32'h0000_0001);
  #200ns;
endtask

task mac_stats_e2e_test_c::clear_all_counters();
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);
endtask

task mac_stats_e2e_test_c::clear_all_status();
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;
endtask

// ---------------------------------------------------------------------------
// Scenario 1: TX-only event counts — TX traffic must not increment RX counters
// ---------------------------------------------------------------------------
task mac_stats_e2e_test_c::run_e2e_tx_no_counter_incr();
  bit [31:0] cnt_data;
  bit [31:0] tx_status;

  `uvm_info("STATS_E2E", "=== Scenario 1: TX-Only No Counter Increment ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();
  #200ns;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("invalid before TX", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("oversize before TX", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("unsupported before TX", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "Driving 10 clean TX frames via AXI agent", UVM_NONE)
  drive_tx_traffic(10);
  #2us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("invalid after 10 TX", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("oversize after 10 TX", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("unsupported after 10 TX", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);

  read_status_snapshot(reg_map_pkg::REG_TX_STATUS, tx_status);
  check_masked("tx_error hardwired 0", tx_status, 32'h0000_0000, 32'h0000_0001);

  `uvm_info("STATS_E2E", "Driving 20 more TX frames (burst)", UVM_NONE)
  drive_tx_traffic(20);
  #2us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("invalid after 30 TX", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("oversize after 30 TX", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("unsupported after 30 TX", cnt_data, 32'h0000_0000, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "=== Scenario 1: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 2: RX-only known event counts
// ---------------------------------------------------------------------------
task mac_stats_e2e_test_c::run_e2e_rx_known_counts();
  bit [31:0] cnt_data;

  `uvm_info("STATS_E2E", "=== Scenario 2: RX-Only Known Event Counts ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();

  `uvm_info("STATS_E2E", "Single invalid frame -> counter should be 1", UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("single invalid", cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "3 more invalid frames -> counter should be 4", UVM_NONE)
  repeat (3) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("4x invalid", cnt_data, 32'd4, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);

  `uvm_info("STATS_E2E", "Single oversize frame -> counter should be 1", UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("single oversize", cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "2 more oversize -> counter should be 3", UVM_NONE)
  repeat (2) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("3x oversize", cnt_data, 32'd3, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);

  `uvm_info("STATS_E2E", "Single unsupported frame -> counter should be 1", UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("single unsupported", cnt_data, 32'd1, 32'hFFFF_FFFF);

  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);

  `uvm_info("STATS_E2E", "Burst: 7 invalid frames -> counter should be 7", UVM_NONE)
  repeat (7) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("burst 7 invalid", cnt_data, 32'd7, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "CRC frame does NOT increment invalid counter (separate path)", UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("crc no incr invalid", cnt_data, 32'd7, 32'hFFFF_FFFF);

  clear_all_counters();
  #500ns;

  `uvm_info("STATS_E2E", "=== Scenario 2: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 3: Error, control, and PAUSE events; mixed TX/RX/error sequence
// ---------------------------------------------------------------------------
task mac_stats_e2e_test_c::run_e2e_error_control_pause();
  bit [31:0] cnt_data;
  bit [31:0] rx_status;
  bit [31:0] pause_status;

  `uvm_info("STATS_E2E", "=== Scenario 3: Error, Control, PAUSE Events ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();
  #200ns;

  `uvm_info("STATS_E2E", "Mixed: invalid, oversize, unsupported, then PAUSE", UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("mixed invalid=1", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("mixed oversize=1", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("mixed unsupported=1", cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "PAUSE frame: verify pause_active status", UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_PAUSE_ACTIVE, 16'h0010);
  #500ns;

  read_status_snapshot(reg_map_pkg::REG_RX_STATUS, rx_status);
  check_masked("pause_active set", rx_status, 32'h0000_0001, 32'h0000_0001);

  `uvm_info("STATS_E2E", "Wait for PAUSE to expire", UVM_NONE)
  #5us;

  read_status_snapshot(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("STATS_E2E", $sformatf("pause_status=0x%08h", pause_status), UVM_NONE)

  `uvm_info("STATS_E2E", "Verify error counters unchanged by PAUSE", UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("invalid unchanged after PAUSE", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("oversize unchanged after PAUSE", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("unsupported unchanged after PAUSE", cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "Mixed TX/RX: TX traffic interleaved with RX errors", UVM_NONE)
  clear_all_counters();
  clear_all_status();

  drive_tx_traffic(3);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_tx_traffic(2);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  drive_tx_traffic(2);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  drive_tx_traffic(3);
  #2us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("mixed TX/RX invalid=1", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("mixed TX/RX oversize=1", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("mixed TX/RX unsupported=1", cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "Burst mixed: 5 invalid + 3 oversize + 2 unsupported", UVM_NONE)
  clear_all_counters();
  clear_all_status();

  repeat (5) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  repeat (3) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  repeat (2) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("burst mixed invalid=5", cnt_data, 32'd5, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("burst mixed oversize=3", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("burst mixed unsupported=2", cnt_data, 32'd2, 32'hFFFF_FFFF);

  clear_all_counters();

  `uvm_info("STATS_E2E", "=== Scenario 3: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 4: Read individual/all counters after deterministic traffic
// ---------------------------------------------------------------------------
task mac_stats_e2e_test_c::run_e2e_read_individual_all();
  bit [31:0] cnt_inv, cnt_os, cnt_uns;
  bit [31:0] cnt_inv2, cnt_os2, cnt_uns2;

  `uvm_info("STATS_E2E", "=== Scenario 4: Read Individual/All Counters ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();

  repeat (4) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  repeat (2) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  repeat (3) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  #1us;

  `uvm_info("STATS_E2E", "Read each counter individually", UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_inv);
  check_masked("individual invalid", cnt_inv, 32'd4, 32'hFFFF_FFFF);

  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_os);
  check_masked("individual oversize", cnt_os, 32'd2, 32'hFFFF_FFFF);

  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_uns);
  check_masked("individual unsupported", cnt_uns, 32'd3, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "Read all counters back-to-back (coherent snapshot)", UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_inv2);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_os2);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_uns2);

  check_masked("coherent invalid", cnt_inv2, cnt_inv, 32'hFFFF_FFFF);
  check_masked("coherent oversize", cnt_os2, cnt_os, 32'hFFFF_FFFF);
  check_masked("coherent unsupported", cnt_uns2, cnt_uns, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "No new events between reads -> values must match", UVM_NONE)
  #500ns;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_inv2);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_os2);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_uns2);

  check_masked("stable invalid", cnt_inv2, cnt_inv, 32'hFFFF_FFFF);
  check_masked("stable oversize", cnt_os2, cnt_os, 32'hFFFF_FFFF);
  check_masked("stable unsupported", cnt_uns2, cnt_uns, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "Drive 1 more invalid, re-read all", UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_inv2);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_os2);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_uns2);

  check_masked("invalid +1", cnt_inv2, cnt_inv + 32'd1, 32'hFFFF_FFFF);
  check_masked("oversize stable after invalid", cnt_os2, cnt_os, 32'hFFFF_FFFF);
  check_masked("unsupported stable after invalid", cnt_uns2, cnt_uns, 32'hFFFF_FFFF);

  clear_all_counters();

  `uvm_info("STATS_E2E", "=== Scenario 4: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 5: Interleave qualifying and non-qualifying events
// ---------------------------------------------------------------------------
task mac_stats_e2e_test_c::run_e2e_interleave_qual_nonqual();
  bit [31:0] cnt_data;

  `uvm_info("STATS_E2E", "=== Scenario 5: Interleave Qualifying/Non-Qualifying ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();

  `uvm_info("STATS_E2E", "Pattern: invalid -> clean -> oversize -> clean -> unsupported -> clean",
            UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("interleave invalid=1", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("interleave oversize=1", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("interleave unsupported=1", cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "Burst interleave: 3x(invalid + clean) + 2x(oversize + clean)", UVM_NONE)
  clear_all_counters();

  repeat (3) begin
    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  end
  repeat (2) begin
    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  end
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("burst interleave invalid=3", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("burst interleave oversize=2", cnt_data, 32'd2, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("burst interleave unsupported=0", cnt_data, 32'd0, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "TX interleaved with RX errors: tx -> invalid -> tx -> clean", UVM_NONE)
  clear_all_counters();

  drive_tx_traffic(2);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_tx_traffic(2);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_tx_traffic(2);
  #2us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("TX/RX interleave invalid=1", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("TX/RX interleave oversize=0", cnt_data, 32'd0, 32'hFFFF_FFFF);

  clear_all_counters();

  `uvm_info("STATS_E2E", "=== Scenario 5: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 6: Vary management-read timing
// ---------------------------------------------------------------------------
task mac_stats_e2e_test_c::run_e2e_vary_read_timing();
  bit [31:0] cnt_data;
  time read_delays [4];

  read_delays[0] = 100ns;
  read_delays[1] = 300ns;
  read_delays[2] = 500ns;
  read_delays[3] = 1000ns;

  `uvm_info("STATS_E2E", "=== Scenario 6: Vary Management-Read Timing ===", UVM_NONE)

  for (int i = 0; i < 4; i++) begin
    `uvm_info("STATS_E2E", $sformatf("Read delay: %0t", read_delays[i]), UVM_NONE)

    clear_all_counters();
    clear_all_status();

    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    #read_delays[i];

    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
    check_masked($sformatf("invalid read at %0t", read_delays[i]),
                 cnt_data, 32'd1, 32'hFFFF_FFFF);
  end

  `uvm_info("STATS_E2E", "Rapid back-to-back reads at same address", UVM_NONE)
  clear_all_counters();
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("rapid read 1", cnt_data, 32'd2, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("rapid read 2", cnt_data, 32'd2, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("rapid read 3", cnt_data, 32'd2, 32'hFFFF_FFFF);

  `uvm_info("STATS_E2E", "Read during active event stream", UVM_NONE)
  clear_all_counters();
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #50ns;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  `uvm_info("STATS_E2E", $sformatf("mid-stream read: count=%0d", cnt_data), UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("post-stream read", cnt_data, 32'd3, 32'hFFFF_FFFF);

  clear_all_counters();

  `uvm_info("STATS_E2E", "=== Scenario 6: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 7: Constrained-random event/clear/read campaigns
// ---------------------------------------------------------------------------
task mac_stats_e2e_test_c::run_e2e_random_campaign();
  bit [31:0] cnt_data;
  int unsigned num_iterations;
  int unsigned ev_type;
  bit [31:0] expected_invalid;
  bit [31:0] expected_oversize;
  bit [31:0] expected_unsupported;
  bit do_clear_invalid, do_clear_oversize, do_clear_unsupported;
  bit do_read_check;
  bit [6:0] rand_enable_val;

  `uvm_info("STATS_E2E", "=== Scenario 7: Constrained-Random Campaign ===", UVM_NONE)

  if (!std::randomize(num_iterations) with { num_iterations inside {[50 : 80]}; })
    `uvm_fatal("STATS_E2E", "Iteration count randomization failed")

  `uvm_info("STATS_E2E", $sformatf("Running %0d constrained-random iterations", num_iterations),
            UVM_NONE)

  clear_all_counters();
  #500ns;
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  expected_invalid    = 32'd0;
  expected_oversize   = 32'd0;
  expected_unsupported = 32'd0;

  for (int unsigned iter = 0; iter < num_iterations; iter++) begin
    int unsigned num_events;
    bit [31:0] actual;

    if (!std::randomize(rand_enable_val) with {
      rand_enable_val inside {[7'b000_0001 : 7'b000_1111]};
    })
      `uvm_fatal("STATS_E2E", "Enable randomization failed")

    apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
    #200ns;
    apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, {25'd0, rand_enable_val});
    #200ns;

    if (!std::randomize(num_events) with { num_events inside {[1 : 6]}; })
      `uvm_fatal("STATS_E2E", "Event count randomization failed")

    repeat (num_events) begin
      if (!std::randomize(ev_type) with { ev_type inside {[0 : 4]}; })
        `uvm_fatal("STATS_E2E", "Event type randomization failed")
      case (ev_type)
        0: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID); expected_invalid++; end
        1: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC); end
        2: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE); expected_oversize++; end
        3: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
               expected_unsupported++; end
        4: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA); end
      endcase
    end
    #1us;

    if (!std::randomize(do_clear_invalid) with { do_clear_invalid dist { 1 := 25, 0 := 75 }; })
      `uvm_fatal("STATS_E2E", "Clear invalid randomization failed")
    if (!std::randomize(do_clear_oversize) with { do_clear_oversize dist { 1 := 25, 0 := 75 }; })
      `uvm_fatal("STATS_E2E", "Clear oversize randomization failed")
    if (!std::randomize(do_clear_unsupported) with {
      do_clear_unsupported dist { 1 := 25, 0 := 75 }; })
      `uvm_fatal("STATS_E2E", "Clear unsupported randomization failed")
    if (!std::randomize(do_read_check) with { do_read_check dist { 1 := 80, 0 := 20 }; })
      `uvm_fatal("STATS_E2E", "Read check randomization failed")

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
    #500ns;

    if (do_read_check) begin
      read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, actual);
      check_masked($sformatf("iter %0d invalid", iter),
                   actual, expected_invalid, 32'hFFFF_FFFF);
      read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, actual);
      check_masked($sformatf("iter %0d oversize", iter),
                   actual, expected_oversize, 32'hFFFF_FFFF);
      read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, actual);
      check_masked($sformatf("iter %0d unsupported", iter),
                   actual, expected_unsupported, 32'hFFFF_FFFF);
    end

    if (iter % 15 == 0 && iter > 0) begin
      `uvm_info("STATS_E2E", $sformatf(
        "Progress: iter=%0d inv=%0d os=%0d uns=%0d",
        iter, expected_invalid, expected_oversize, expected_unsupported), UVM_NONE)
    end
  end

  clear_all_counters();
  clear_all_status();

  `uvm_info("STATS_E2E", $sformatf(
    "Campaign complete: %0d iterations. Final: inv=%0d os=%0d uns=%0d",
    num_iterations, expected_invalid, expected_oversize, expected_unsupported), UVM_NONE)

  `uvm_info("STATS_E2E", "=== Scenario 7: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// run_stimulus - orchestrator
// ---------------------------------------------------------------------------
task mac_stats_e2e_test_c::run_stimulus(uvm_phase phase);
  `uvm_info("STATS_E2E", "========================================", UVM_NONE)
  `uvm_info("STATS_E2E", "STAT_E2E End-to-End Statistics Test", UVM_NONE)
  `uvm_info("STATS_E2E", "TX / RX / Error / Control / PAUSE", UVM_NONE)
  `uvm_info("STATS_E2E", "========================================", UVM_NONE)

  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  #200ns;
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  run_e2e_tx_no_counter_incr();
  run_e2e_rx_known_counts();
  run_e2e_error_control_pause();
  run_e2e_read_individual_all();
  run_e2e_interleave_qual_nonqual();
  run_e2e_vary_read_timing();
  run_e2e_random_campaign();

  `uvm_info("STATS_E2E", "========================================", UVM_NONE)
  `uvm_info("STATS_E2E", "ALL STAT_E2E SCENARIOS PASSED", UVM_NONE)
  `uvm_info("STATS_E2E", "========================================", UVM_NONE)
endtask
