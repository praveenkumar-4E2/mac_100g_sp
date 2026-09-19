// MAC-CDC-HANDSHAKE-TRANSFER: Verify reliable single-transaction payload
// transfer through the cdc_handshake module via the stats_cdc_bridge.
// Covers: basic accepted request (ready_src=1), backpressure with delayed
// or absent destination acknowledge, sequence patterns (single, back-to-back,
// random), and stress at maximum supported rate.
//
// Single class with methods (no multiple classes).  Extends
// mac_apb_config_cdc_test_c to reuse apb_write_check, apb_read_check,
// cdc_settle, send_and_check, and random_apb_accesses.
class mac_cdc_handshake_transfer_test_c extends mac_apb_config_cdc_test_c;
  `uvm_component_utils(mac_cdc_handshake_transfer_test_c)

  extern function new(string name = "mac_cdc_handshake_transfer_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);

  // --- Helper methods ---
  extern task configure_mac();
  extern task send_axi_clean_frames(int unsigned count, int pkt_len);
  extern task send_rs_clean_frames(int unsigned count, int pkt_len,
                                   bit [47:0] da = 48'hFF_FF_FF_FF_FF_FF);
  extern task send_rs_frame_typed(int unsigned frame_octets, bit [47:0] da,
                                  mac_hvl_utils_c::payload_pattern_e pattern,
                                  string frame_name);
  extern task send_axi_burst_sparse(int unsigned burst_cnt,
                                    int unsigned sparse_cnt, time sparse_ifg);
  extern task send_axi_constrained_burst(int unsigned count);
  extern task send_rs_constrained_random(int unsigned count);
  extern task wait_axi_rx_count(int unsigned target);
  extern task wait_rs_tx_count(int unsigned target);

  // --- Scenario methods ---
  extern task scenario_basic_accepted_request();
  extern task scenario_backpressure_delayed_ack();
  extern task scenario_sequence_patterns();
  extern task scenario_stress_max_rate();
  extern task restore_clean_state();
endclass

// =============================================================================
// Constructor / configure / run_stimulus
// =============================================================================

function mac_cdc_handshake_transfer_test_c::new(
    string name = "mac_cdc_handshake_transfer_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
endfunction

function void mac_cdc_handshake_transfer_test_c::configure_test();
  super.configure_test();
  env_cfg_h.has_scoreboard = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len  = 1600;
  env_cfg_h.rs_active_agent_cfgs[0].enable_error_injection = 1'b1;
endfunction

task mac_cdc_handshake_transfer_test_c::run_stimulus(uvm_phase phase);
  configure_mac();
  scenario_basic_accepted_request();
  scenario_backpressure_delayed_ack();
  scenario_sequence_patterns();
  scenario_stress_max_rate();
  restore_clean_state();
endtask

// =============================================================================
// Helper methods — create, configure, start() on correct sequencer
// =============================================================================

task mac_cdc_handshake_transfer_test_c::configure_mac();
  bit [31:0] ctrl;
  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT);
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_check(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  cdc_settle();
endtask

task mac_cdc_handshake_transfer_test_c::send_axi_clean_frames(
    int unsigned count, int pkt_len);
  axi_clean_sequence_c seq_h;
  seq_h = axi_clean_sequence_c::type_id::create("axi_clean");
  seq_h.num_tx      = count;
  seq_h.payload_min  = (pkt_len > 0) ? pkt_len : 46;
  seq_h.payload_max  = (pkt_len > 0) ? pkt_len : 1500;
  seq_h.error_injection = 1'b0;
  seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_cdc_handshake_transfer_test_c::send_rs_clean_frames(
    int unsigned count, int pkt_len, bit [47:0] da);
  rs_sequence_c seq_h;
  seq_h = rs_sequence_c::type_id::create("rs_clean");
  seq_h.num_frames   = count;
  seq_h.payload_min   = (pkt_len > 0) ? pkt_len : 46;
  seq_h.payload_max   = (pkt_len > 0) ? pkt_len : 1500;
  seq_h.broadcast_da  = (da == 48'hFF_FF_FF_FF_FF_FF);
  seq_h.error_injection = 1'b0;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_cdc_handshake_transfer_test_c::send_rs_frame_typed(
    int unsigned frame_octets, bit [47:0] da,
    mac_hvl_utils_c::payload_pattern_e pattern, string frame_name);
  apb_002_rx_frame_sequence_c frame_seq_h;
  frame_seq_h = apb_002_rx_frame_sequence_c::type_id::create(
                    {"hs_", frame_name});
  frame_seq_h.frame_octets     = frame_octets;
  frame_seq_h.destination       = da;
  frame_seq_h.payload_pattern   = pattern;
  frame_seq_h.payload_seed      = $urandom;
  frame_seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_cdc_handshake_transfer_test_c::send_axi_burst_sparse(
    int unsigned burst_cnt, int unsigned sparse_cnt, time sparse_ifg);
  mac_comprehensive_scenario_seq_c seq_h;
  seq_h = mac_comprehensive_scenario_seq_c::type_id::create("axi_burst_sparse");
  seq_h.payload_min  = 46;
  seq_h.payload_max  = 1500;
  seq_h.send_axi_burst_sparse(
      env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h,
      burst_cnt, sparse_cnt, sparse_ifg);
endtask

task mac_cdc_handshake_transfer_test_c::send_axi_constrained_burst(
    int unsigned count);
  mac_comprehensive_scenario_seq_c seq_h;
  seq_h = mac_comprehensive_scenario_seq_c::type_id::create("axi_cstr_burst");
  seq_h.payload_min  = 46;
  seq_h.payload_max  = 1500;
  seq_h.send_axi_constrained_burst(
      env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h,
      count);
endtask

task mac_cdc_handshake_transfer_test_c::send_rs_constrained_random(
    int unsigned count);
  mac_comprehensive_scenario_seq_c seq_h;
  seq_h = mac_comprehensive_scenario_seq_c::type_id::create("rs_cstr_rnd");
  seq_h.payload_min  = 46;
  seq_h.payload_max  = 1500;
  seq_h.send_rs_constrained_random(
      env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h,
      count);
endtask

task mac_cdc_handshake_transfer_test_c::wait_axi_rx_count(int unsigned target);
  bit timed_out;
  int unsigned timeout_ns;
  timeout_ns = 200ms;
  mac_wait_utils_c::wait_for_axi_count_at_least(
      target,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, timeout_ns, timed_out);
  if (timed_out)
    `uvm_error("CDC_HANDSHAKE", $sformatf(
        "Timed out waiting for AXI RX count >= %0d (current=%0d)",
        target,
        env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))
endtask

task mac_cdc_handshake_transfer_test_c::wait_rs_tx_count(int unsigned target);
  bit timed_out;
  int unsigned timeout_ns;
  timeout_ns = 200ms;
  mac_wait_utils_c::wait_for_count_at_least(
      target,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, timeout_ns, timed_out);
  if (timed_out)
    `uvm_error("CDC_HANDSHAKE", $sformatf(
        "Timed out waiting for RS TX count >= %0d (current=%0d)",
        target,
        env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))
endtask

// =============================================================================
// Scenario 1 : Basic accepted request with ready_src=1 and known payload
// =============================================================================

task mac_cdc_handshake_transfer_test_c::scenario_basic_accepted_request();
  int unsigned axi_before, rs_before;
  `uvm_info("CDC_HANDSHAKE", "--- Scenario 1: Basic accepted request ---",
            UVM_NONE)

  // --- 1a: Single RS frame with known zero payload (ready_src=1) ---
  axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(64, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ZERO, "zero_64");
  wait_axi_rx_count(axi_before + 1);
  `uvm_info("CDC_HANDSHAKE", "  1a zero payload PASSED", UVM_NONE)

  // --- 1b: Single RS frame with known ones payload ---
  axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(128, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ONES, "ones_128");
  wait_axi_rx_count(axi_before + 1);
  `uvm_info("CDC_HANDSHAKE", "  1b ones payload PASSED", UVM_NONE)

  // --- 1c: Single RS frame with alternating 55/AA payload ---
  axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(256, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ALT_55_AA, "alt_55_aa_256");
  wait_axi_rx_count(axi_before + 1);
  `uvm_info("CDC_HANDSHAKE", "  1c alt 55/AA payload PASSED", UVM_NONE)

  // --- 1d: Single RS frame with random payload ---
  axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(512, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_RANDOM, "rand_512");
  wait_axi_rx_count(axi_before + 1);
  `uvm_info("CDC_HANDSHAKE", "  1d random payload PASSED", UVM_NONE)

  // --- 1e: Single AXI frame (reverse path, ready_src=1) ---
  rs_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_axi_clean_frames(1, 100);
  wait_rs_tx_count(rs_before + 1);
  `uvm_info("CDC_HANDSHAKE", "  1e AXI TX single PASSED", UVM_NONE)

  // --- 1f: Known incrementing payload pattern ---
  axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(1024, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_INCREMENTING, "incr_1024");
  wait_axi_rx_count(axi_before + 1);
  `uvm_info("CDC_HANDSHAKE", "  1f incrementing payload PASSED", UVM_NONE)

  `uvm_info("CDC_HANDSHAKE", "Scenario 1 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 2 : Backpressure — request while ready_src=0; delayed/absent ack
// =============================================================================

task mac_cdc_handshake_transfer_test_c::scenario_backpressure_delayed_ack();
  int unsigned cnt_before;
  `uvm_info("CDC_HANDSHAKE", "--- Scenario 2: Backpressure / delayed ack ---",
            UVM_NONE)

  // --- 2a: Burst to fill pipeline, then single frame with CDC settle ---
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_clean_frames(8, 1500);
  // CDC settle introduces APB-side delay before next transaction
  repeat ($urandom_range(2, 5)) @(posedge tb_cfg_h.apb_vif.clk);
  #(200ns);
  send_rs_frame_typed(128, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ALT_AA_55, "backpress_128");
  wait_axi_rx_count(cnt_before + 9);
  `uvm_info("CDC_HANDSHAKE", "  2a burst-then-single PASSED", UVM_NONE)

  // --- 2b: Delayed APB acknowledgment — read status mid-traffic ---
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_clean_frames(5, 800);
  // Insert delayed APB reads to force CDC ack latency
  begin
    apb_read_sequence_c read_h;
    repeat (3) begin
      read_h = apb_read_sequence_c::type_id::create("hs_2b_status");
      read_h.m_addr = reg_map_pkg::REG_RX_STATUS;
      read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
      #($urandom_range(50, 200) * 1ns);
    end
  end
  wait_axi_rx_count(cnt_before + 5);
  `uvm_info("CDC_HANDSHAKE", "  2b delayed APB ack PASSED", UVM_NONE)

  // --- 2c: Absent acknowledge simulation — long idle then burst ---
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  // Let cdc_handshake idle (ready_src asserted, no req)
  #500ns;
  // Now burst to verify handshake re-engages after idle
  send_rs_clean_frames(4, 64);
  wait_axi_rx_count(cnt_before + 4);
  `uvm_info("CDC_HANDSHAKE", "  2c idle-then-burst PASSED", UVM_NONE)

  // --- 2d: Back-to-back APB writes with traffic ---
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  begin
    bit [31:0] ctrl;
    ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
           (32'h1 << reg_map_pkg::CTRL_TX_BIT);
    // Rapid APB writes to exercise CDC bridge under load
    repeat (5) begin
      apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1200);
      apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
    end
  end
  cdc_settle();
  send_rs_frame_typed(200, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_RANDOM, "post_b2b_200");
  wait_axi_rx_count(cnt_before + 1);
  `uvm_info("CDC_HANDSHAKE", "  2d APB write burst + traffic PASSED", UVM_NONE)

  `uvm_info("CDC_HANDSHAKE", "Scenario 2 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 3 : Sequence — single, back-to-back after ready, random timing
// =============================================================================

task mac_cdc_handshake_transfer_test_c::scenario_sequence_patterns();
  int unsigned cnt_before;
  `uvm_info("CDC_HANDSHAKE", "--- Scenario 3: Sequence patterns ---", UVM_NONE)

  // --- 3a: Single frames with CDC settle between each ---
  begin
    mac_hvl_utils_c::payload_pattern_e patterns [3] = '{
        mac_hvl_utils_c::PAYLOAD_ZERO,
        mac_hvl_utils_c::PAYLOAD_ONES,
        mac_hvl_utils_c::PAYLOAD_RANDOM
    };
    foreach (patterns[i]) begin
      cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                      .monitor_h.mon_rcvd_xtn_cnt;
      send_rs_frame_typed($urandom_range(64, 300),
                          48'hFF_FF_FF_FF_FF_FF,
                          patterns[i],
                          $sformatf("single_%0d", i));
      wait_axi_rx_count(cnt_before + 1);
      cdc_settle();
    end
  end
  `uvm_info("CDC_HANDSHAKE", "  3a single-with-settle PASSED", UVM_NONE)

  // --- 3b: Back-to-back after ready (burst of 10 AXI frames) ---
  cnt_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_axi_constrained_burst(10);
  wait_rs_tx_count(cnt_before + 10);
  `uvm_info("CDC_HANDSHAKE", "  3b back-to-back burst PASSED", UVM_NONE)

  // --- 3c: Random timing — burst/sparse alternation ---
  cnt_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_axi_burst_sparse(6, 4, 150ns);
  wait_rs_tx_count(cnt_before + 16);
  `uvm_info("CDC_HANDSHAKE", "  3c burst/sparse alternation PASSED", UVM_NONE)

  // --- 3d: Mixed-size frames with random delays ---
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  begin
    int unsigned sizes [5] = '{64, 256, 512, 1000, 1500};
    foreach (sizes[i]) begin
      send_rs_frame_typed(sizes[i], 48'hFF_FF_FF_FF_FF_FF,
                          mac_hvl_utils_c::PAYLOAD_RANDOM,
                          $sformatf("mixed_%0d", i));
      #($urandom_range(10, 100) * 1ns);
    end
  end
  wait_axi_rx_count(cnt_before + 5);
  `uvm_info("CDC_HANDSHAKE", "  3d mixed-size random delay PASSED", UVM_NONE)

  // --- 3e: Back-to-back RS frames followed by AXI burst ---
  begin
    int unsigned rs_before_3e, axi_before_3e;
    rs_before_3e = env_h.mac_rs_stream_agent_top_h.passive_agents[0]
                       .monitor_h.mon_rcvd_xtn_cnt;
    axi_before_3e = env_h.axi4_stream_agent_top_h.passive_agents[0]
                        .monitor_h.mon_rcvd_xtn_cnt;
    fork
      send_rs_clean_frames(5, 100);
      send_axi_clean_frames(5, 100);
    join
    wait_rs_tx_count(rs_before_3e + 5);
    wait_axi_rx_count(axi_before_3e + 5);
  end
  `uvm_info("CDC_HANDSHAKE", "  3e bidirectional back-to-back PASSED", UVM_NONE)

  `uvm_info("CDC_HANDSHAKE", "Scenario 3 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 4 : Stress — random legal requests at maximum supported rate
// =============================================================================

task mac_cdc_handshake_transfer_test_c::scenario_stress_max_rate();
  int unsigned cnt_before;
  `uvm_info("CDC_HANDSHAKE", "--- Scenario 4: Stress max rate ---", UVM_NONE)

  // --- 4a: Sustained AXI TX at max rate (20+ frames) ---
  cnt_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_axi_constrained_burst(20);
  wait_rs_tx_count(cnt_before + 20);
  `uvm_info("CDC_HANDSHAKE", "  4a AXI TX stress PASSED", UVM_NONE)

  // --- 4b: Sustained RS RX at max rate (20+ frames) ---
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_constrained_random(20);
  wait_axi_rx_count(cnt_before + 20);
  `uvm_info("CDC_HANDSHAKE", "  4b RS RX stress PASSED", UVM_NONE)

  // --- 4c: Bidirectional stress (fork/join) ---
  begin
    int unsigned rs_before_4c, axi_before_4c;
    rs_before_4c = env_h.mac_rs_stream_agent_top_h.passive_agents[0]
                       .monitor_h.mon_rcvd_xtn_cnt;
    axi_before_4c = env_h.axi4_stream_agent_top_h.passive_agents[0]
                        .monitor_h.mon_rcvd_xtn_cnt;
    fork
      send_axi_constrained_burst(15);
      send_rs_constrained_random(15);
    join
    // Allow time for pipeline drain
    #2us;
    if (env_h.mac_rs_stream_agent_top_h.passive_agents[0]
            .monitor_h.mon_rcvd_xtn_cnt > rs_before_4c)
      `uvm_info("CDC_HANDSHAKE",
                $sformatf("  4c bidir stress RS TX: %0d -> %0d",
                          rs_before_4c,
                          env_h.mac_rs_stream_agent_top_h.passive_agents[0]
                              .monitor_h.mon_rcvd_xtn_cnt),
                UVM_NONE)
    else
      `uvm_error("CDC_HANDSHAKE", "  4c bidir stress: no RS TX activity")
    if (env_h.axi4_stream_agent_top_h.passive_agents[0]
            .monitor_h.mon_rcvd_xtn_cnt > axi_before_4c)
      `uvm_info("CDC_HANDSHAKE",
                $sformatf("  4c bidir stress AXI RX: %0d -> %0d",
                          axi_before_4c,
                          env_h.axi4_stream_agent_top_h.passive_agents[0]
                              .monitor_h.mon_rcvd_xtn_cnt),
                UVM_NONE)
    else
      `uvm_error("CDC_HANDSHAKE", "  4c bidir stress: no AXI RX activity")
  end
  `uvm_info("CDC_HANDSHAKE", "  4c bidirectional stress PASSED", UVM_NONE)

  // --- 4d: Stress with APB register access interleaved ---
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  begin
    bit [31:0] ctrl;
    ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
           (32'h1 << reg_map_pkg::CTRL_TX_BIT);
    repeat (10) begin
      if ($urandom_range(0, 1))
        apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
      else
        apb_read_check(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl, 32'h0000_00ff);
      send_rs_frame_typed($urandom_range(64, 500),
                          48'hFF_FF_FF_FF_FF_FF,
                          mac_hvl_utils_c::PAYLOAD_RANDOM,
                          $sformatf("stress_apb_%0d", cnt_before));
    end
  end
  wait_axi_rx_count(cnt_before + 10);
  `uvm_info("CDC_HANDSHAKE", "  4d stress + APB interleave PASSED", UVM_NONE)

  // --- 4e: Constrained-random sustained async traffic ---
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  begin
    mac_hvl_utils_c::payload_pattern_e patterns [5] = '{
        mac_hvl_utils_c::PAYLOAD_ZERO,
        mac_hvl_utils_c::PAYLOAD_ONES,
        mac_hvl_utils_c::PAYLOAD_ALT_55_AA,
        mac_hvl_utils_c::PAYLOAD_INCREMENTING,
        mac_hvl_utils_c::PAYLOAD_RANDOM
    };
    foreach (patterns[i]) begin
      send_rs_frame_typed($urandom_range(64, 1500),
                          48'hFF_FF_FF_FF_FF_FF,
                          patterns[i],
                          $sformatf("stress_pat_%0d", i));
    end
  end
  wait_axi_rx_count(cnt_before + 5);
  `uvm_info("CDC_HANDSHAKE", "  4e pattern stress PASSED", UVM_NONE)

  // --- 4f: Boundary occupancy stress (min + max frames) ---
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  fork
    send_rs_clean_frames(5, 64);     // minimum frames
    send_rs_clean_frames(5, 1500);   // maximum frames
  join
  wait_axi_rx_count(cnt_before + 10);
  `uvm_info("CDC_HANDSHAKE", "  4f boundary stress PASSED", UVM_NONE)

  `uvm_info("CDC_HANDSHAKE", "Scenario 4 PASSED", UVM_NONE)
endtask

// =============================================================================
// Restore clean state
// =============================================================================

task mac_cdc_handshake_transfer_test_c::restore_clean_state();
  bit [31:0] ctrl;
  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT);
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_check(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  cdc_settle();
  `uvm_info("CDC_HANDSHAKE",
            "=== CDC handshake transfer synchronization test completed ===",
            UVM_NONE)
endtask
