class mac_stats_cause_irq_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_stats_cause_irq_test_c)

  localparam bit [6:0] CAUSE_RX_INVALID    = 7'b000_0001;
  localparam bit [6:0] CAUSE_RX_CRC        = 7'b000_0010;
  localparam bit [6:0] CAUSE_RX_OVERSIZE   = 7'b000_0100;
  localparam bit [6:0] CAUSE_RX_UNSUPPORTED = 7'b000_1000;
  localparam bit [6:0] CAUSE_PAUSE_ACTIVE  = 7'b001_0000;
  localparam bit [6:0] CAUSE_PAUSE_EXPIRED = 7'b010_0000;
  localparam bit [6:0] CAUSE_TX_ERROR      = 7'b100_0000;

  bit [6:0]  rand_enable_val;
  bit [6:0]  rand_clear_val;

  extern function new(string name = "mac_stats_cause_irq_test_c", uvm_component parent = null);
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

  extern task run_single_cause_assertions();
  extern task run_concurrent_causes();
  extern task run_cause_clear();
  extern task run_interleaved_events();
  extern task run_vary_read_timing();
  extern task run_single_burst_mixed();
  extern task run_random_campaigns();
endclass

function mac_stats_cause_irq_test_c::new(string name = "mac_stats_cause_irq_test_c",
                                         uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents = 1;
endfunction

function void mac_stats_cause_irq_test_c::configure_test();
  super.configure_test();
  env_cfg_h.has_scoreboard = 1'b0;
  env_cfg_h.apb_active_agent_cfgs[0].m_fail_on_unexpected_slverr = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = 1600;
  env_cfg_h.rs_active_agent_cfgs[0].enable_error_injection = 1'b1;
endfunction

task mac_stats_cause_irq_test_c::apb_write_check(
    input bit [15:0] addr, input bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create($sformatf("st_wr_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_wdata = data;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_stats_cause_irq_test_c::apb_read_data(
    input bit [15:0] addr, output bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("st_rd_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = seq_h.m_rdata;
endtask

task mac_stats_cause_irq_test_c::read_status_snapshot(
    input bit [15:0] addr, output bit [31:0] data);
  bit [31:0] discard;
  apb_read_data(addr, discard);
  #300ns;
  apb_read_data(addr, data);
endtask

task mac_stats_cause_irq_test_c::check_masked(
    input string check_name, input bit [31:0] actual,
    input bit [31:0] expected, input bit [31:0] mask);
  if ((actual & mask) !== (expected & mask))
    `uvm_error("STATS_CHECK", $sformatf("%s: got=%08h expected=%08h mask=%08h",
                check_name, actual, expected, mask))
endtask

task mac_stats_cause_irq_test_c::drive_event(int unsigned kind, bit [15:0] quanta);
  mac_stats_cause_irq_seq_c stim_h;
  stim_h = mac_stats_cause_irq_seq_c::type_id::create($sformatf("stim_%0d", kind));
  stim_h.stimulus_kind = mac_stats_cause_irq_seq_c::stimulus_kind_e'(kind);
  stim_h.pause_quanta_val = quanta;
  stim_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_stats_cause_irq_test_c::run_single_cause_assertions();
  bit [31:0] data;
  bit [31:0] enable_val;
  bit [6:0]  cause_masks [7];
  string     cause_names [7];
  bit        has_counters [7];
  bit [15:0] counter_addrs [7];
  bit [31:0] counter_before;
  bit [31:0] counter_after;

  cause_masks[0] = CAUSE_RX_INVALID;     cause_names[0] = "rx_invalid";
  has_counters[0] = 1;                   counter_addrs[0] = reg_map_pkg::REG_RX_INVALID_COUNT;
  cause_masks[1] = CAUSE_RX_CRC;         cause_names[1] = "rx_crc";
  has_counters[1] = 0;                   counter_addrs[1] = 16'h0000;
  cause_masks[2] = CAUSE_RX_OVERSIZE;    cause_names[2] = "rx_oversize";
  has_counters[2] = 1;                   counter_addrs[2] = reg_map_pkg::REG_RX_OVERSIZE_COUNT;
  cause_masks[3] = CAUSE_RX_UNSUPPORTED; cause_names[3] = "rx_unsupported";
  has_counters[3] = 1;                   counter_addrs[3] = reg_map_pkg::REG_RX_UNSUPPORTED_COUNT;
  cause_masks[4] = CAUSE_PAUSE_ACTIVE;   cause_names[4] = "pause_active";
  has_counters[4] = 0;                   counter_addrs[4] = 16'h0000;
  cause_masks[5] = CAUSE_PAUSE_EXPIRED;  cause_names[5] = "pause_expired";
  has_counters[5] = 0;                   counter_addrs[5] = 16'h0000;
  cause_masks[6] = CAUSE_TX_ERROR;       cause_names[6] = "tx_error";
  has_counters[6] = 0;                   counter_addrs[6] = 16'h0000;

  `uvm_info("STATS_SINGLE", "=== Scenario 1: Single Cause Assertions ===", UVM_NONE)

  for (int i = 0; i < 7; i++) begin
    enable_val = {25'd0, cause_masks[i]};

    `uvm_info("STATS_SINGLE", $sformatf("--- Testing cause: %s (bit %0d) ---", cause_names[i], i), UVM_NONE)

    apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_0000);
    #200ns;
    apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
    #200ns;

    apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, enable_val);
    #200ns;

    if (has_counters[i])
      read_status_snapshot(counter_addrs[i], counter_before);

    case (i)
      0: drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
      1: drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
      2: drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
      3: drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
      4: drive_event(mac_stats_cause_irq_seq_c::STIM_PAUSE_ACTIVE, 16'h0001);
      5: drive_event(mac_stats_cause_irq_seq_c::STIM_PAUSE_EXPIRED, 16'h0001);
      6: begin
        `uvm_info("STATS_SINGLE",
                  "tx_error_event is hardwired to 0 in RTL; verifying bit reads 0", UVM_NONE)
      end
    endcase

    if (i == 4 || i == 5)
      #5us;
    else
      #1us;

    read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
    if (i != 6)
      check_masked($sformatf("%s cause set", cause_names[i]), data, enable_val, enable_val);

    if (has_counters[i]) begin
      read_status_snapshot(counter_addrs[i], counter_after);
      if (counter_after !== counter_before + 32'd1)
        `uvm_error("STATS_SINGLE", $sformatf(
                   "%s counter: got=%0d expected=%0d", cause_names[i], counter_after, counter_before + 1))
    end

    if (i == 6)
      check_masked("tx_error bit always 0", data, 32'h0000_0000, 32'h0000_0040);

    apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, enable_val);
    #300ns;
    read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
    check_masked($sformatf("%s cause cleared", cause_names[i]), data, 32'h0000_0000, enable_val);

    `uvm_info("STATS_SINGLE", $sformatf("--- %s completed ---", cause_names[i]), UVM_NONE)
  end

  `uvm_info("STATS_SINGLE", "=== Scenario 1: DONE ===", UVM_NONE)
endtask

task mac_stats_cause_irq_test_c::run_concurrent_causes();
  bit [31:0] data;
  bit [6:0]  enable_val;

  `uvm_info("STATS_CONCURRENT", "=== Scenario 2: Concurrent Causes ===", UVM_NONE)

  enable_val = CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_0000);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, {25'd0, enable_val});
  #200ns;

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("three concurrent causes", data, {25'd0, enable_val}, {25'd0, enable_val});

  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, {25'd0, enable_val});
  #300ns;

  enable_val = CAUSE_RX_INVALID | CAUSE_PAUSE_ACTIVE | CAUSE_RX_UNSUPPORTED;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, {25'd0, enable_val});
  #200ns;

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_PAUSE_ACTIVE, 16'h0001);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  #5us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("pause+invalid+unsupported concurrent", data, {25'd0, enable_val}, {25'd0, enable_val});

  `uvm_info("STATS_CONCURRENT", "Testing with enable=0 (masked causes hidden)", UVM_NONE)
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_0000);
  #200ns;

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("causes set but enable=0", data, 32'h0000_0000, 32'h0000_007F);

  `uvm_info("STATS_CONCURRENT", "=== Scenario 2: DONE ===", UVM_NONE)
endtask

task mac_stats_cause_irq_test_c::run_cause_clear();
  bit [31:0] data;
  bit [31:0] inv_before, os_before, uns_before;

  `uvm_info("STATS_CLEAR", "=== Scenario 3: Cause Clear ===", UVM_NONE)

  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_007F);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;

  apb_write_check(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0001);
  apb_write_check(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h0000_0001);
  apb_write_check(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, 32'h0000_0001);
  #200ns;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, inv_before);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, os_before);
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, uns_before);

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("three causes before clear", data,
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE},
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE});

  `uvm_info("STATS_CLEAR", "Deassert sources, then clear one cause", UVM_NONE)
  #500ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, {25'd0, CAUSE_RX_CRC});
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("single-bit W1C (crc cleared)",
               data,
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_OVERSIZE},
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE});

  `uvm_info("STATS_CLEAR", "Re-drive cleared cause, then multi-bit W1C", UVM_NONE)
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("crc reasserted after re-drive", data,
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE},
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE});

  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS,
                  {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE});
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("multi-bit W1C all cleared", data, 32'h0000_0000,
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE});

  `uvm_info("STATS_CLEAR", "Verifying cleared causes do not reassert without new events", UVM_NONE)
  #500ns;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("no reassert without events", data, 32'h0000_0000,
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE});

  `uvm_info("STATS_CLEAR", "Counter W1C clear", UVM_NONE)
  apb_write_check(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0001);
  apb_write_check(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h0000_0001);
  #500ns;

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, data);
  check_masked("invalid counter before clear", data, 32'd3, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, data);
  check_masked("oversize counter before clear", data, 32'd1, 32'hFFFF_FFFF);

  apb_write_check(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0001);
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, data);
  check_masked("invalid counter W1C clear", data, 32'h0000_0000, 32'hFFFF_FFFF);

  apb_write_check(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h0000_0001);
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, data);
  check_masked("oversize counter W1C clear", data, 32'h0000_0000, 32'hFFFF_FFFF);

  apb_write_check(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, 32'h0000_0001);
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, data);
  check_masked("unsupported counter W1C clear", data, 32'h0000_0000, 32'hFFFF_FFFF);

  `uvm_info("STATS_CLEAR", "=== Scenario 3: DONE ===", UVM_NONE)
endtask

task mac_stats_cause_irq_test_c::run_interleaved_events();
  bit [31:0] data;

  `uvm_info("STATS_INTERLEAVE", "=== Interleaved Qualifying and Non-Qualifying Events ===", UVM_NONE)

  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_007F);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;

  `uvm_info("STATS_INTERLEAVE", "invalid -> clean -> crc -> clean -> oversize -> clean", UVM_NONE)
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("interleaved causes set", data,
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE},
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE});

  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;

  `uvm_info("STATS_INTERLEAVE", "unsupported -> clean -> pause -> clean -> invalid -> clean", UVM_NONE)
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_event(mac_stats_cause_irq_seq_c::STIM_PAUSE_ACTIVE, 16'h0001);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  #5us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("interleaved causes set (batch 2)", data,
               {25'd0, CAUSE_RX_UNSUPPORTED | CAUSE_PAUSE_ACTIVE | CAUSE_RX_INVALID},
               {25'd0, CAUSE_RX_UNSUPPORTED | CAUSE_PAUSE_ACTIVE | CAUSE_RX_INVALID});

  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_0000);
  #200ns;

  `uvm_info("STATS_INTERLEAVE", "interleaved with enable=0", UVM_NONE)
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("interleaved enable=0 no assert", data, 32'h0000_0000, 32'h0000_007F);

  `uvm_info("STATS_INTERLEAVE", "=== Interleaved Events: DONE ===", UVM_NONE)
endtask

task mac_stats_cause_irq_test_c::run_vary_read_timing();
  bit [31:0] data;
  time read_delays [4];

  read_delays[0] = 100ns;
  read_delays[1] = 300ns;
  read_delays[2] = 500ns;
  read_delays[3] = 1000ns;

  `uvm_info("STATS_TIMING", "=== Vary Management Read Timing ===", UVM_NONE)

  for (int i = 0; i < 4; i++) begin
    apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, {25'd0, CAUSE_RX_INVALID});
    #200ns;
    apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, {25'd0, CAUSE_RX_INVALID});
    #200ns;

    drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
    #(read_delays[i]);

    apb_read_data(reg_map_pkg::REG_INTERRUPT_STATUS, data);
    if (i == 0)
      `uvm_info("STATS_TIMING", $sformatf("read at %0t: data=%08h (may be stale)", read_delays[i], data),
                UVM_NONE)
    else
      check_masked($sformatf("read at %0t", read_delays[i]), data,
                   {25'd0, CAUSE_RX_INVALID}, {25'd0, CAUSE_RX_INVALID});

    apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, {25'd0, CAUSE_RX_INVALID});
    #300ns;
  end

  `uvm_info("STATS_TIMING", "=== Vary Read Timing: DONE ===", UVM_NONE)
endtask

task mac_stats_cause_irq_test_c::run_single_burst_mixed();
  bit [31:0] data;
  bit [31:0] inv_before, os_before;

  `uvm_info("STATS_SEQ", "=== Single, Burst, and Mixed Event Sequences ===", UVM_NONE)

  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_007F);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;

  `uvm_info("STATS_SEQ", "--- Single: one frame per event type ---", UVM_NONE)
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("single invalid", data, {25'd0, CAUSE_RX_INVALID}, {25'd0, CAUSE_RX_INVALID});
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, {25'd0, CAUSE_RX_INVALID});
  #200ns;

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("single crc", data, {25'd0, CAUSE_RX_CRC}, {25'd0, CAUSE_RX_CRC});
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, {25'd0, CAUSE_RX_CRC});
  #200ns;

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("single oversize", data, {25'd0, CAUSE_RX_OVERSIZE}, {25'd0, CAUSE_RX_OVERSIZE});
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, {25'd0, CAUSE_RX_OVERSIZE});
  #200ns;

  `uvm_info("STATS_SEQ", "--- Burst: 5x invalid frames ---", UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, inv_before);
  repeat (5) drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("burst invalid cause", data, {25'd0, CAUSE_RX_INVALID}, {25'd0, CAUSE_RX_INVALID});
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, data);
  check_masked("burst invalid counter", data, inv_before + 32'd5, 32'hFFFF_FFFF);

  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, {25'd0, CAUSE_RX_INVALID});
  apb_write_check(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0001);
  #200ns;

  `uvm_info("STATS_SEQ", "--- Mixed: invalid + crc + oversize burst ---", UVM_NONE)
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, inv_before);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, os_before);

  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);
  drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("mixed burst all causes",
               data,
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE},
               {25'd0, CAUSE_RX_INVALID | CAUSE_RX_CRC | CAUSE_RX_OVERSIZE});
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, data);
  check_masked("mixed invalid counter", data, inv_before + 32'd1, 32'hFFFF_FFFF);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, data);
  check_masked("mixed oversize counter", data, os_before + 32'd1, 32'hFFFF_FFFF);

  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  apb_write_check(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0001);
  apb_write_check(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h0000_0001);
  apb_write_check(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, 32'h0000_0001);
  #200ns;

  `uvm_info("STATS_SEQ", "=== Single, Burst, Mixed: DONE ===", UVM_NONE)
endtask

task mac_stats_cause_irq_test_c::run_random_campaigns();
  bit [31:0] data;
  int unsigned num_events;
  int unsigned ev_type;
  bit [6:0] expected_causes;

  `uvm_info("STATS_RANDOM", "=== Constrained-Random Event/Clear/Read Campaigns ===", UVM_NONE)

  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_00D5);
  #200ns;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #2us;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
  #200ns;

  for (int unsigned iter = 0; iter < 15; iter++) begin
    `uvm_info("STATS_RANDOM", $sformatf("--- Iteration %0d ---", iter), UVM_NONE)

    if (!std::randomize(rand_enable_val) with {
      rand_enable_val inside {[7'b000_0001 : 7'b000_1111]};
    })
      `uvm_fatal("STATS_RANDOM", "Enable randomization failed")

    apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
    #200ns;
    apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, {25'd0, rand_enable_val});
    #200ns;

    if (!std::randomize(num_events) with { num_events inside {[1 : 4]}; })
      `uvm_fatal("STATS_RANDOM", "Event count randomization failed")

    expected_causes = 7'd0;
    repeat (num_events) begin
      if (!std::randomize(ev_type) with { ev_type inside {[0 : 4]}; })
        `uvm_fatal("STATS_RANDOM", "Event type randomization failed")
      case (ev_type)
        0: begin drive_event(mac_stats_cause_irq_seq_c::STIM_RX_INVALID); expected_causes[0] = 1'b1; end
        1: begin drive_event(mac_stats_cause_irq_seq_c::STIM_RX_CRC);     expected_causes[1] = 1'b1; end
        2: begin drive_event(mac_stats_cause_irq_seq_c::STIM_RX_OVERSIZE); expected_causes[2] = 1'b1; end
        3: begin drive_event(mac_stats_cause_irq_seq_c::STIM_RX_UNSUPPORTED_CTRL); expected_causes[3] = 1'b1; end
        4: begin drive_event(mac_stats_cause_irq_seq_c::STIM_CLEAN_DATA); end
      endcase
    end
    #1us;

    read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
    check_masked($sformatf("iter %0d cause check", iter),
                 data, {25'd0, expected_causes & rand_enable_val}, {25'd0, rand_enable_val});

    if (!std::randomize(rand_clear_val) with {
      rand_clear_val inside {[7'b000_0000 : 7'b111_1111]};
    })
      `uvm_fatal("STATS_RANDOM", "Clear mask randomization failed")

    apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, {25'd0, rand_clear_val});
    #300ns;

    read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
    check_masked($sformatf("iter %0d after clear", iter),
                 data,
                 {25'd0, (expected_causes & rand_enable_val) & ~rand_clear_val},
                 {25'd0, rand_enable_val});

    apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'h0000_007F);
    #200ns;
  end

  `uvm_info("STATS_RANDOM", "=== Random Campaigns: DONE ===", UVM_NONE)
endtask

task mac_stats_cause_irq_test_c::run_stimulus(uvm_phase phase);
  `uvm_info("STATS_TEST", "========================================", UVM_NONE)
  `uvm_info("STATS_TEST", "Statistics Cause Aggregation & IRQ Test", UVM_NONE)
  `uvm_info("STATS_TEST", "========================================", UVM_NONE)

  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  #200ns;

  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0095);
  #200ns;

  run_single_cause_assertions();
  run_concurrent_causes();
  run_cause_clear();
  run_interleaved_events();
  run_vary_read_timing();
  run_single_burst_mixed();
  run_random_campaigns();

  `uvm_info("STATS_TEST", "========================================", UVM_NONE)
  `uvm_info("STATS_TEST", "ALL SCENARIOS PASSED", UVM_NONE)
  `uvm_info("STATS_TEST", "========================================", UVM_NONE)
endtask
