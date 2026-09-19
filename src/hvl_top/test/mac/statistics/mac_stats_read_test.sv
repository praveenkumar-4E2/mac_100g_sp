class mac_stats_read_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_stats_read_test_c)

  localparam bit [6:0] CAUSE_RX_INVALID    = 7'b000_0001;
  localparam bit [6:0] CAUSE_RX_CRC        = 7'b000_0010;
  localparam bit [6:0] CAUSE_RX_OVERSIZE   = 7'b000_0100;
  localparam bit [6:0] CAUSE_RX_UNSUPPORTED = 7'b000_1000;
  localparam bit [6:0] CAUSE_PAUSE_ACTIVE  = 7'b001_0000;
  localparam bit [6:0] CAUSE_PAUSE_EXPIRED = 7'b010_0000;
  localparam bit [6:0] CAUSE_TX_ERROR      = 7'b100_0000;

  extern function new(string name = "mac_stats_read_test_c", uvm_component parent = null);
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
  extern task read_all_counters(string tag = "");
  extern task read_all_status(string tag = "");

  extern task run_read_during_tx_only();
  extern task run_read_during_rx_only();
  extern task run_read_during_error_traffic();
  extern task run_read_during_pause();
  extern task run_read_during_mixed_traffic();
  extern task run_read_repeated_timing();
  extern task run_read_interleave_qual_nonqual();
  extern task run_read_random_campaign();
endclass

function mac_stats_read_test_c::new(string name = "mac_stats_read_test_c",
                                    uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents = 1;
  num_rs_active_agents  = 1;
endfunction

function void mac_stats_read_test_c::configure_test();
  super.configure_test();
  env_cfg_h.has_scoreboard = 1'b0;
  env_cfg_h.apb_active_agent_cfgs[0].m_fail_on_unexpected_slverr = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = 1600;
  env_cfg_h.rs_active_agent_cfgs[0].enable_error_injection = 1'b1;
  env_cfg_h.axi_active_agent_cfgs[0].enable_error_injection = 1'b0;
endfunction

task mac_stats_read_test_c::apb_write_check(
    input bit [15:0] addr, input bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create($sformatf("rd_wr_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_wdata = data;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_stats_read_test_c::apb_read_data(
    input bit [15:0] addr, output bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("rd_rd_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = seq_h.m_rdata;
endtask

task mac_stats_read_test_c::read_status_snapshot(
    input bit [15:0] addr, output bit [31:0] data);
  bit [31:0] discard;
  apb_read_data(addr, discard);
  #300ns;
  apb_read_data(addr, data);
endtask

task mac_stats_read_test_c::check_masked(
    input string check_name, input bit [31:0] actual,
    input bit [31:0] expected, input bit [31:0] mask);
  if ((actual & mask) !== (expected & mask))
    `uvm_error("STATS_READ", $sformatf("%s: got=%08h expected=%08h mask=%08h",
                check_name, actual, expected, mask))
endtask

task mac_stats_read_test_c::drive_rx_event(int unsigned kind, bit [15:0] quanta);
  mac_stats_cause_irq_seq_c stim_h;
  stim_h = mac_stats_cause_irq_seq_c::type_id::create($sformatf("rx_stim_%0d", kind));
  stim_h.stimulus_kind = mac_stats_cause_irq_seq_c::stimulus_kind_e'(kind);
  stim_h.pause_quanta_val = quanta;
  stim_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_stats_read_test_c::drive_tx_traffic(int unsigned count);
  axi_sequence_c tx_seq_h;
  tx_seq_h = axi_sequence_c::type_id::create("rd_tx_seq");
  if (!tx_seq_h.randomize() with { soft num_tx == count; })
    `uvm_fatal("STATS_READ", "TX sequence randomization failed")
  tx_seq_h.start(env_h.virtual_sequencer_h.client_ingress_seqr_h);
endtask

task mac_stats_read_test_c::drive_pause_frame(bit [15:0] quanta);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_PAUSE_ACTIVE, quanta);
endtask

task mac_stats_read_test_c::clear_counter(input bit [15:0] addr);
  apb_write_check(addr, 32'h0000_0001);
  #200ns;
endtask

task mac_stats_read_test_c::clear_all_counters();
  clear_counter(reg_map_pkg::REG_RX_INVALID_COUNT);
  clear_counter(reg_map_pkg::REG_RX_OVERSIZE_COUNT);
  clear_counter(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT);
endtask

task mac_stats_read_test_c::clear_all_status();
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;
endtask

task mac_stats_read_test_c::read_all_counters(string tag = "");
  bit [31:0] data;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, data);
  `uvm_info("STATS_READ", $sformatf("%s invalid_count=%0d", tag, data), UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, data);
  `uvm_info("STATS_READ", $sformatf("%s oversize_count=%0d", tag, data), UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, data);
  `uvm_info("STATS_READ", $sformatf("%s unsupported_count=%0d", tag, data), UVM_NONE)
endtask

task mac_stats_read_test_c::read_all_status(string tag = "");
  bit [31:0] data;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  `uvm_info("STATS_READ", $sformatf("%s int_status=0x%08h", tag, data), UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_STATUS, data);
  `uvm_info("STATS_READ", $sformatf("%s rx_status=0x%08h", tag, data), UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_PAUSE_STATUS, data);
  `uvm_info("STATS_READ", $sformatf("%s pause_status=0x%08h", tag, data), UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_TX_STATUS, data);
  `uvm_info("STATS_READ", $sformatf("%s tx_status=0x%08h", tag, data), UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 1: Read during TX-only traffic
// ---------------------------------------------------------------------------
task mac_stats_read_test_c::run_read_during_tx_only();
  bit [31:0] cnt_data, tx_status;

  `uvm_info("STATS_READ", "=== Scenario 1: Read During TX-Only Traffic ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();

  `uvm_info("STATS_READ", "Read before TX starts", UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("pre-TX invalid", cnt_data, 32'h0, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("pre-TX oversize", cnt_data, 32'h0, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("pre-TX unsupported", cnt_data, 32'h0, 32'hFFFF_FFFF);

  `uvm_info("STATS_READ", "Driving 15 TX frames", UVM_NONE)
  drive_tx_traffic(15);

  `uvm_info("STATS_READ", "Read after 15 TX frames", UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("mid-TX invalid", cnt_data, 32'h0, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("mid-TX oversize", cnt_data, 32'h0, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("mid-TX unsupported", cnt_data, 32'h0, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_TX_STATUS, tx_status);
  check_masked("mid-TX tx_error=0", tx_status, 32'h0, 32'h1);

  `uvm_info("STATS_READ", "Driving 15 more TX frames", UVM_NONE)
  drive_tx_traffic(15);

  `uvm_info("STATS_READ", "Read after 30 total TX frames", UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("post-TX invalid", cnt_data, 32'h0, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("post-TX oversize", cnt_data, 32'h0, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("post-TX unsupported", cnt_data, 32'h0, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_TX_STATUS, tx_status);
  check_masked("post-TX tx_error=0", tx_status, 32'h0, 32'h1);

  clear_all_counters();

  `uvm_info("STATS_READ", "=== Scenario 1: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 2: Read during RX-only traffic
// ---------------------------------------------------------------------------
task mac_stats_read_test_c::run_read_during_rx_only();
  bit [31:0] cnt_data;

  `uvm_info("STATS_READ", "=== Scenario 2: Read During RX-Only Traffic ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();

  `uvm_info("STATS_READ", "Drive invalid, read, drive oversize, read, drive unsupported, read",
            UVM_NONE)

  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("after invalid read invalid", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("after invalid read oversize", cnt_data, 32'h0, 32'hFFFF_FFFF);

  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("after oversize read invalid", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("after oversize read oversize", cnt_data, 32'd1, 32'hFFFF_FFFF);

  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("after unsupported read uns", cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_READ", "Burst 5 invalid, read all during burst end", UVM_NONE)
  repeat (5) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("burst invalid count", cnt_data, 32'd6, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("burst oversize stable", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("burst unsupported stable", cnt_data, 32'd1, 32'hFFFF_FFFF);

  clear_all_counters();

  `uvm_info("STATS_READ", "=== Scenario 2: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 3: Read during sustained error traffic
// ---------------------------------------------------------------------------
task mac_stats_read_test_c::run_read_during_error_traffic();
  bit [31:0] cnt_inv, cnt_os, cnt_uns;
  bit [31:0] prev_inv, prev_os, prev_uns;

  `uvm_info("STATS_READ", "=== Scenario 3: Read During Sustained Error Traffic ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();

  prev_inv = 0; prev_os = 0; prev_uns = 0;

  repeat (20) begin
    case ($urandom_range(0, 2))
      0: drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
      1: drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
      2: drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
    endcase

    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_inv);
    read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_os);
    read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_uns);

    if (cnt_inv < prev_inv)
      `uvm_error("STATS_READ", $sformatf("invalid regressed: %0d -> %0d", prev_inv, cnt_inv))
    if (cnt_os < prev_os)
      `uvm_error("STATS_READ", $sformatf("oversize regressed: %0d -> %0d", prev_os, cnt_os))
    if (cnt_uns < prev_uns)
      `uvm_error("STATS_READ", $sformatf("unsupported regressed: %0d -> %0d", prev_uns, cnt_uns))

    prev_inv = cnt_inv;
    prev_os = cnt_os;
    prev_uns = cnt_uns;
  end

  `uvm_info("STATS_READ", $sformatf("Final: inv=%0d os=%0d uns=%0d", prev_inv, prev_os, prev_uns),
            UVM_NONE)

  clear_all_counters();

  `uvm_info("STATS_READ", "=== Scenario 3: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 4: Read during PAUSE traffic
// ---------------------------------------------------------------------------
task mac_stats_read_test_c::run_read_during_pause();
  bit [31:0] cnt_data, rx_status, pause_status;

  `uvm_info("STATS_READ", "=== Scenario 4: Read During PAUSE Traffic ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();

  repeat (3) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("pre-pause invalid=3", cnt_data, 32'd3, 32'hFFFF_FFFF);

  `uvm_info("STATS_READ", "Drive PAUSE frame, read during PAUSE active", UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_PAUSE_ACTIVE, 16'h0020);
  #500ns;

  read_status_snapshot(reg_map_pkg::REG_RX_STATUS, rx_status);
  `uvm_info("STATS_READ", $sformatf("during PAUSE: rx_status=0x%08h", rx_status), UVM_NONE)
  check_masked("pause_active during PAUSE", rx_status, 32'h1, 32'h1);

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("invalid unchanged during PAUSE", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("oversize unchanged during PAUSE", cnt_data, 32'h0, 32'hFFFF_FFFF);

  `uvm_info("STATS_READ", "Wait for PAUSE to expire, read pause_expired", UVM_NONE)
  #5us;

  read_status_snapshot(reg_map_pkg::REG_PAUSE_STATUS, pause_status);
  `uvm_info("STATS_READ", $sformatf("after PAUSE: pause_status=0x%08h", pause_status), UVM_NONE)

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("invalid still 3 after PAUSE", cnt_data, 32'd3, 32'hFFFF_FFFF);

  `uvm_info("STATS_READ", "Drive error after PAUSE, verify counter increments", UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("invalid after post-PAUSE error", cnt_data, 32'd4, 32'hFFFF_FFFF);

  clear_all_counters();

  `uvm_info("STATS_READ", "=== Scenario 4: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 5: Read during mixed TX+RX+error+PAUSE traffic
// ---------------------------------------------------------------------------
task mac_stats_read_test_c::run_read_during_mixed_traffic();
  bit [31:0] cnt_inv, cnt_os, cnt_uns;
  bit [31:0] prev_inv, prev_os, prev_uns;
  int unsigned read_count;

  `uvm_info("STATS_READ", "=== Scenario 5: Read During Mixed Traffic ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();

  prev_inv = 0; prev_os = 0; prev_uns = 0;
  read_count = 0;

  repeat (5) begin
    drive_tx_traffic(3);
    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    drive_tx_traffic(2);
    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
    drive_tx_traffic(2);
    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
    drive_tx_traffic(3);

    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_inv);
    read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_os);
    read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_uns);

    if (cnt_inv < prev_inv)
      `uvm_error("STATS_READ", $sformatf("mixed: invalid regressed %0d->%0d", prev_inv, cnt_inv))
    if (cnt_os < prev_os)
      `uvm_error("STATS_READ", $sformatf("mixed: oversize regressed %0d->%0d", prev_os, cnt_os))
    if (cnt_uns < prev_uns)
      `uvm_error("STATS_READ", $sformatf("mixed: unsupported regressed %0d->%0d", prev_uns, cnt_uns))

    prev_inv = cnt_inv;
    prev_os = cnt_os;
    prev_uns = cnt_uns;
    read_count++;
  end

  `uvm_info("STATS_READ", $sformatf(
    "Mixed traffic complete: %0d reads. inv=%0d os=%0d uns=%0d",
    read_count, prev_inv, prev_os, prev_uns), UVM_NONE)

  check_masked("mixed invalid final", prev_inv, 32'd5, 32'hFFFF_FFFF);
  check_masked("mixed oversize final", prev_os, 32'd5, 32'hFFFF_FFFF);
  check_masked("mixed unsupported final", prev_uns, 32'd5, 32'hFFFF_FFFF);

  clear_all_counters();

  `uvm_info("STATS_READ", "=== Scenario 5: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 6: Repeated management-read timing during traffic
// ---------------------------------------------------------------------------
task mac_stats_read_test_c::run_read_repeated_timing();
  bit [31:0] cnt_data;
  time read_delays [6];

  read_delays[0] = 50ns;
  read_delays[1] = 100ns;
  read_delays[2] = 200ns;
  read_delays[3] = 500ns;
  read_delays[4] = 1000ns;
  read_delays[5] = 2000ns;

  `uvm_info("STATS_READ", "=== Scenario 6: Repeated Management-Read Timing ===", UVM_NONE)

  for (int i = 0; i < 6; i++) begin
    `uvm_info("STATS_READ", $sformatf("--- Read delay: %0t ---", read_delays[i]), UVM_NONE)

    clear_all_counters();
    clear_all_status();

    repeat (5) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    #read_delays[i];

    read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
    if (i <= 1) begin
      `uvm_info("STATS_READ", $sformatf("short delay %0t: count=%0d (may be partial)",
                 read_delays[i], cnt_data), UVM_NONE)
    end else begin
      check_masked($sformatf("delay %0t invalid", read_delays[i]),
                   cnt_data, 32'd5, 32'hFFFF_FFFF);
    end
  end

  `uvm_info("STATS_READ", "Rapid triple back-to-back reads at same address", UVM_NONE)
  clear_all_counters();
  repeat (3) drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("triple read 1", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("triple read 2", cnt_data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("triple read 3", cnt_data, 32'd3, 32'hFFFF_FFFF);

  `uvm_info("STATS_READ", "Back-to-back reads across different addresses", UVM_NONE)
  clear_all_counters();
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("cross-addr invalid", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("cross-addr oversize", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("cross-addr unsupported", cnt_data, 32'h0, 32'hFFFF_FFFF);

  clear_all_counters();

  `uvm_info("STATS_READ", "=== Scenario 6: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 7: Interleave qualifying and non-qualifying events, read between
// ---------------------------------------------------------------------------
task mac_stats_read_test_c::run_read_interleave_qual_nonqual();
  bit [31:0] cnt_data;

  `uvm_info("STATS_READ", "=== Scenario 7: Interleave Qualifying/Non-Qualifying ===", UVM_NONE)

  clear_all_counters();
  clear_all_status();

  `uvm_info("STATS_READ", "invalid -> clean -> oversize -> clean -> unsupported -> clean",
            UVM_NONE)
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("after invalid", cnt_data, 32'd1, 32'hFFFF_FFFF);

  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("after clean invalid stable", cnt_data, 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("after clean oversize=0", cnt_data, 32'h0, 32'hFFFF_FFFF);

  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("after oversize", cnt_data, 32'd1, 32'hFFFF_FFFF);

  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("after clean oversize stable", cnt_data, 32'd1, 32'hFFFF_FFFF);

  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("after unsupported", cnt_data, 32'd1, 32'hFFFF_FFFF);

  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, cnt_data);
  check_masked("after clean unsupported stable", cnt_data, 32'd1, 32'hFFFF_FFFF);

  `uvm_info("STATS_READ", "Burst interleave: 4x(invalid + clean), read all after each pair",
            UVM_NONE)
  clear_all_counters();
  repeat (4) begin
    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  end
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("burst interleave invalid=4", cnt_data, 32'd4, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("burst interleave oversize=0", cnt_data, 32'h0, 32'hFFFF_FFFF);

  `uvm_info("STATS_READ", "TX interleaved with RX errors + reads between", UVM_NONE)
  clear_all_counters();

  drive_tx_traffic(2);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("tx-rx interleave invalid=1", cnt_data, 32'd1, 32'hFFFF_FFFF);

  drive_tx_traffic(2);
  drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, cnt_data);
  check_masked("tx-rx interleave oversize=1", cnt_data, 32'd1, 32'hFFFF_FFFF);

  drive_tx_traffic(2);
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, cnt_data);
  check_masked("after more TX invalid stable", cnt_data, 32'd1, 32'hFFFF_FFFF);

  clear_all_counters();

  `uvm_info("STATS_READ", "=== Scenario 7: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Scenario 8: Constrained-random event/clear/read campaigns
// ---------------------------------------------------------------------------
task mac_stats_read_test_c::run_read_random_campaign();
  bit [31:0] cnt_data;
  int unsigned num_iterations;
  int unsigned ev_type;
  bit [31:0] expected_invalid, expected_oversize, expected_unsupported;
  bit do_clear_invalid, do_clear_oversize, do_clear_unsupported;
  bit do_read_individual, do_read_all;
  bit [31:0] actual;
  int unsigned read_delay_idx;
  time read_delays [4];

  read_delays[0] = 100ns;
  read_delays[1] = 300ns;
  read_delays[2] = 500ns;
  read_delays[3] = 1000ns;

  `uvm_info("STATS_READ", "=== Scenario 8: Constrained-Random Campaign ===", UVM_NONE)

  if (!std::randomize(num_iterations) with { num_iterations inside {[50 : 80]}; })
    `uvm_fatal("STATS_READ", "Iteration count randomization failed")

  `uvm_info("STATS_READ", $sformatf("Running %0d iterations", num_iterations), UVM_NONE)

  clear_all_counters();
  #500ns;
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  expected_invalid    = 32'd0;
  expected_oversize   = 32'd0;
  expected_unsupported = 32'd0;

  for (int unsigned iter = 0; iter < num_iterations; iter++) begin
    int unsigned num_events;

    if (!std::randomize(num_events) with { num_events inside {[1 : 6]}; })
      `uvm_fatal("STATS_READ", "Event count randomization failed")

    repeat (num_events) begin
      if (!std::randomize(ev_type) with { ev_type inside {[0 : 4]}; })
        `uvm_fatal("STATS_READ", "Event type randomization failed")
      case (ev_type)
        0: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID); expected_invalid++; end
        1: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC); end
        2: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE); expected_oversize++; end
        3: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
               expected_unsupported++; end
        4: begin drive_rx_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA); end
      endcase
    end

    if (!std::randomize(read_delay_idx) with { read_delay_idx inside {[0 : 3]}; })
      `uvm_fatal("STATS_READ", "Read delay randomization failed")
    #read_delays[read_delay_idx];

    if (!std::randomize(do_clear_invalid) with { do_clear_invalid dist { 1 := 20, 0 := 80 }; })
      `uvm_fatal("STATS_READ", "Clear invalid randomization failed")
    if (!std::randomize(do_clear_oversize) with { do_clear_oversize dist { 1 := 20, 0 := 80 }; })
      `uvm_fatal("STATS_READ", "Clear oversize randomization failed")
    if (!std::randomize(do_clear_unsupported) with {
      do_clear_unsupported dist { 1 := 20, 0 := 80 }; })
      `uvm_fatal("STATS_READ", "Clear unsupported randomization failed")
    if (!std::randomize(do_read_individual) with {
      do_read_individual dist { 1 := 70, 0 := 30 }; })
      `uvm_fatal("STATS_READ", "Read individual randomization failed")
    if (!std::randomize(do_read_all) with { do_read_all dist { 1 := 50, 0 := 50 }; })
      `uvm_fatal("STATS_READ", "Read all randomization failed")

    if (do_read_individual) begin
      read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, actual);
      check_masked($sformatf("iter %0d invalid", iter),
                   actual, expected_invalid, 32'hFFFF_FFFF);
    end

    if (do_read_all) begin
      read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, actual);
      check_masked($sformatf("iter %0d all invalid", iter),
                   actual, expected_invalid, 32'hFFFF_FFFF);
      read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, actual);
      check_masked($sformatf("iter %0d all oversize", iter),
                   actual, expected_oversize, 32'hFFFF_FFFF);
      read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, actual);
      check_masked($sformatf("iter %0d all unsupported", iter),
                   actual, expected_unsupported, 32'hFFFF_FFFF);
    end

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
    #200ns;

    if (do_clear_invalid || do_clear_oversize || do_clear_unsupported) begin
      read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, actual);
      check_masked($sformatf("iter %0d post-clear invalid", iter),
                   actual, expected_invalid, 32'hFFFF_FFFF);
      read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, actual);
      check_masked($sformatf("iter %0d post-clear oversize", iter),
                   actual, expected_oversize, 32'hFFFF_FFFF);
      read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, actual);
      check_masked($sformatf("iter %0d post-clear unsupported", iter),
                   actual, expected_unsupported, 32'hFFFF_FFFF);
    end

    if (iter % 15 == 0 && iter > 0) begin
      `uvm_info("STATS_READ", $sformatf(
        "Progress: iter=%0d inv=%0d os=%0d uns=%0d",
        iter, expected_invalid, expected_oversize, expected_unsupported), UVM_NONE)
    end
  end

  clear_all_counters();
  clear_all_status();

  `uvm_info("STATS_READ", $sformatf(
    "Campaign complete: %0d iterations. Final: inv=%0d os=%0d uns=%0d",
    num_iterations, expected_invalid, expected_oversize, expected_unsupported), UVM_NONE)

  `uvm_info("STATS_READ", "=== Scenario 8: DONE ===", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// run_stimulus - orchestrator
// ---------------------------------------------------------------------------
task mac_stats_read_test_c::run_stimulus(uvm_phase phase);
  `uvm_info("STATS_READ", "========================================", UVM_NONE)
  `uvm_info("STATS_READ", "STAT_READ Read Coherency During Traffic", UVM_NONE)
  `uvm_info("STATS_READ", "========================================", UVM_NONE)

  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  #200ns;
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  run_read_during_tx_only();
  run_read_during_rx_only();
  run_read_during_error_traffic();
  run_read_during_pause();
  run_read_during_mixed_traffic();
  run_read_repeated_timing();
  run_read_interleave_qual_nonqual();
  run_read_random_campaign();

  `uvm_info("STATS_READ", "========================================", UVM_NONE)
  `uvm_info("STATS_READ", "ALL STAT_READ SCENARIOS PASSED", UVM_NONE)
  `uvm_info("STATS_READ", "========================================", UVM_NONE)
endtask
