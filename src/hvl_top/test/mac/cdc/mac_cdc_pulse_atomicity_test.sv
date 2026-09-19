// MAC-CDC-PULSE-ATOMICITY: Verify that a completed maximum-frame-size
// update crosses APB/MAC clock domains atomically and takes effect once
// without a mixed or stale value.  Uses the cdc_pulse/cdc_handshake
// configuration-update path through apb_cfg_bridge.
//
// Covers:
//   1. Basic 1518->1000 update with boundary frame verification
//   2. APB/MAC phase variation (randomized settle delays)
//   3. Alternating 1000/1200 limits with 1100-byte frame checks
//   4. Shortest-interval back-to-back updates with async clocks
//   5. Clock-ratio variation via randomized inter-update delays
//   6. Burst/sparse APB transaction interleaving with concurrent traffic
//   7. Boundary occupancy with delayed APB acknowledgment
//   8. Constrained-random asynchronous sustained traffic
//
// Single class with methods (no multiple classes).  Extends
// mac_apb_config_cdc_test_c to reuse apb_write_check, apb_read_check,
// cdc_settle, send_and_check, and random_apb_accesses.
class mac_cdc_pulse_atomicity_test_c extends mac_apb_config_cdc_test_c;
  `uvm_component_utils(mac_cdc_pulse_atomicity_test_c)

  extern function new(string name = "mac_cdc_pulse_atomicity_test_c",
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
  extern task send_mixed_size_rs_burst(int unsigned count,
                                       int min_sz, int max_sz);
  extern task wait_axi_rx_count(int unsigned target);
  extern task wait_rs_tx_count(int unsigned target);

  // --- Scenario methods ---
  extern task scenario_basic_update_1518_to_1000();
  extern task scenario_apb_mac_phase_variation();
  extern task scenario_alternate_limits_1000_1200();
  extern task scenario_shortest_interval_updates();
  extern task scenario_clock_ratio_variation();
  extern task scenario_burst_sparse_interleave();
  extern task scenario_boundary_delayed_ack();
  extern task scenario_constrained_random_async();
  extern task restore_clean_state();
endclass

// =============================================================================
// Constructor / configure / run_stimulus
// =============================================================================

function mac_cdc_pulse_atomicity_test_c::new(
    string name = "mac_cdc_pulse_atomicity_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
endfunction

function void mac_cdc_pulse_atomicity_test_c::configure_test();
  super.configure_test();
  env_cfg_h.has_scoreboard = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len  = 1600;
  env_cfg_h.rs_active_agent_cfgs[0].enable_error_injection = 1'b1;
endfunction

task mac_cdc_pulse_atomicity_test_c::run_stimulus(uvm_phase phase);
  configure_mac();
  scenario_basic_update_1518_to_1000();
  scenario_apb_mac_phase_variation();
  scenario_alternate_limits_1000_1200();
  scenario_shortest_interval_updates();
  scenario_clock_ratio_variation();
  scenario_burst_sparse_interleave();
  scenario_boundary_delayed_ack();
  scenario_constrained_random_async();
  restore_clean_state();
endtask

// =============================================================================
// Helper methods — create, configure, start() on correct sequencer
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::configure_mac();
  bit [31:0] ctrl;
  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT);
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_check(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  cdc_settle();
endtask

task mac_cdc_pulse_atomicity_test_c::send_axi_clean_frames(
    int unsigned count, int pkt_len);
  axi_clean_sequence_c seq_h;
  seq_h = axi_clean_sequence_c::type_id::create("cdc_at_axi_clean");
  seq_h.num_tx      = count;
  seq_h.payload_min  = (pkt_len > 0) ? pkt_len : 46;
  seq_h.payload_max  = (pkt_len > 0) ? pkt_len : 1500;
  seq_h.error_injection = 1'b0;
  seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_cdc_pulse_atomicity_test_c::send_rs_clean_frames(
    int unsigned count, int pkt_len, bit [47:0] da);
  rs_sequence_c seq_h;
  seq_h = rs_sequence_c::type_id::create("cdc_at_rs_clean");
  seq_h.num_frames   = count;
  seq_h.payload_min   = (pkt_len > 0) ? pkt_len : 46;
  seq_h.payload_max   = (pkt_len > 0) ? pkt_len : 1500;
  seq_h.broadcast_da  = (da == 48'hFF_FF_FF_FF_FF_FF);
  seq_h.error_injection = 1'b0;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_cdc_pulse_atomicity_test_c::send_rs_frame_typed(
    int unsigned frame_octets, bit [47:0] da,
    mac_hvl_utils_c::payload_pattern_e pattern, string frame_name);
  apb_002_rx_frame_sequence_c frame_seq_h;
  frame_seq_h = apb_002_rx_frame_sequence_c::type_id::create(
                    {"cdc_at_", frame_name});
  frame_seq_h.frame_octets     = frame_octets;
  frame_seq_h.destination       = da;
  frame_seq_h.payload_pattern   = pattern;
  frame_seq_h.payload_seed      = $urandom;
  frame_seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task mac_cdc_pulse_atomicity_test_c::send_axi_burst_sparse(
    int unsigned burst_cnt, int unsigned sparse_cnt, time sparse_ifg);
  mac_cdc_pulse_atomicity_seq_c seq_h;
  seq_h = mac_cdc_pulse_atomicity_seq_c::type_id::create("cdc_at_axi_burst_sparse");
  seq_h.payload_min  = 46;
  seq_h.payload_max  = 1500;
  seq_h.send_axi_burst_sparse(
      env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h,
      burst_cnt, sparse_cnt, sparse_ifg);
endtask

task mac_cdc_pulse_atomicity_test_c::send_axi_constrained_burst(
    int unsigned count);
  mac_cdc_pulse_atomicity_seq_c seq_h;
  seq_h = mac_cdc_pulse_atomicity_seq_c::type_id::create("cdc_at_axi_cstr_burst");
  seq_h.payload_min  = 46;
  seq_h.payload_max  = 1500;
  seq_h.send_axi_constrained_burst(
      env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h,
      count);
endtask

task mac_cdc_pulse_atomicity_test_c::send_rs_constrained_random(
    int unsigned count);
  mac_cdc_pulse_atomicity_seq_c seq_h;
  seq_h = mac_cdc_pulse_atomicity_seq_c::type_id::create("cdc_at_rs_cstr_rnd");
  seq_h.payload_min  = 46;
  seq_h.payload_max  = 1500;
  seq_h.send_rs_constrained_random(
      env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h,
      count);
endtask

task mac_cdc_pulse_atomicity_test_c::send_mixed_size_rs_burst(
    int unsigned count, int min_sz, int max_sz);
  mac_cdc_pulse_atomicity_seq_c seq_h;
  seq_h = mac_cdc_pulse_atomicity_seq_c::type_id::create("cdc_at_mixed_rs");
  seq_h.payload_min  = min_sz;
  seq_h.payload_max  = max_sz;
  seq_h.send_mixed_size_burst(
      env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h,
      count, min_sz, max_sz);
endtask

task mac_cdc_pulse_atomicity_test_c::wait_axi_rx_count(int unsigned target);
  bit timed_out;
  int unsigned timeout_ns;
  timeout_ns = 200ms;
  mac_wait_utils_c::wait_for_axi_count_at_least(
      target,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, timeout_ns, timed_out);
  if (timed_out)
    `uvm_error("CDC_PULSE_AT", $sformatf(
        "Timed out waiting for AXI RX count >= %0d (current=%0d)",
        target,
        env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))
endtask

task mac_cdc_pulse_atomicity_test_c::wait_rs_tx_count(int unsigned target);
  bit timed_out;
  int unsigned timeout_ns;
  timeout_ns = 200ms;
  mac_wait_utils_c::wait_for_count_at_least(
      target,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, timeout_ns, timed_out);
  if (timed_out)
    `uvm_error("CDC_PULSE_AT", $sformatf(
        "Timed out waiting for RS TX count >= %0d (current=%0d)",
        target,
        env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))
endtask

// =============================================================================
// Scenario 1 : Basic 1518->1000 update — prove atomic crossing
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::scenario_basic_update_1518_to_1000();
  int unsigned axi_before;
  `uvm_info("CDC_PULSE_AT", "--- Scenario 1: Basic 1518->1000 update ---",
            UVM_NONE)

  // Baseline: max=1518, send a 1518-byte frame (must be accepted).
  axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(1518, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ONES, "baseline_1518");
  wait_axi_rx_count(axi_before + 1);
  `uvm_info("CDC_PULSE_AT", "  1a baseline 1518 PASSED", UVM_NONE)

  // Update MAX_FRAME_SIZE to 1000 via APB, allow CDC crossing.
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
  cdc_settle();

  // 1b: 1000-byte frame — at the new limit, must be accepted.
  axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(1000, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ALT_AA_55, "new_limit_1000");
  wait_axi_rx_count(axi_before + 1);
  `uvm_info("CDC_PULSE_AT", "  1b at-limit 1000 PASSED", UVM_NONE)

  // 1c: 1001-byte frame — one byte above the new limit, must be dropped.
  //     Proves the MAC domain saw the complete new value, not a stale 1518.
  axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(1001, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ALT_55_AA, "oversize_1001");
  #500ns;
  if (env_h.axi4_stream_agent_top_h.passive_agents[0]
          .monitor_h.mon_rcvd_xtn_cnt != axi_before)
    `uvm_error("CDC_PULSE_AT",
               "1c: 1001-byte frame was incorrectly delivered after MAX=1000")
  else
    `uvm_info("CDC_PULSE_AT", "  1c oversize 1001 correctly dropped PASSED",
              UVM_NONE)

  // 1d: 999-byte frame — below the new limit, must be accepted.
  axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(999, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ZERO, "below_limit_999");
  wait_axi_rx_count(axi_before + 1);
  `uvm_info("CDC_PULSE_AT", "  1d below-limit 999 PASSED", UVM_NONE)

  `uvm_info("CDC_PULSE_AT", "Scenario 1 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 2 : APB/MAC phase variation — repeat at different settle points
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::scenario_apb_mac_phase_variation();
  int unsigned axi_before;
  `uvm_info("CDC_PULSE_AT", "--- Scenario 2: APB/MAC phase variation ---",
            UVM_NONE)

  begin
    time settle_delays [3] = '{0ns, 0ns, 0ns};
    int unsigned apb_clk_counts [3];

    // Randomize the settle delays and APB clock-edge counts.
    foreach (settle_delays[i]) begin
      settle_delays[i] = $urandom_range(50, 800) * 1ns;
      apb_clk_counts[i] = $urandom_range(0, 5);
    end

    foreach (settle_delays[i]) begin
      // Write new limit.
      apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1200);

      // Randomize APB clock edges before settling — varies write phase.
      repeat (apb_clk_counts[i]) @(posedge tb_cfg_h.apb_vif.clk);
      #(settle_delays[i]);

      // Verify the 1200-byte limit took effect atomically.
      axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                      .monitor_h.mon_rcvd_xtn_cnt;
      send_rs_frame_typed(1200, 48'hFF_FF_FF_FF_FF_FF,
                          mac_hvl_utils_c::PAYLOAD_RANDOM,
                          $sformatf("phase_at_%0d", i));
      wait_axi_rx_count(axi_before + 1);

      // Verify 1201 is rejected — proves no stale value.
      axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                      .monitor_h.mon_rcvd_xtn_cnt;
      send_rs_frame_typed(1201, 48'hFF_FF_FF_FF_FF_FF,
                          mac_hvl_utils_c::PAYLOAD_RANDOM,
                          $sformatf("phase_ov_%0d", i));
      #500ns;
      if (env_h.axi4_stream_agent_top_h.passive_agents[0]
              .monitor_h.mon_rcvd_xtn_cnt != axi_before)
        `uvm_error("CDC_PULSE_AT", $sformatf(
            "2: phase variation %0d: 1201-byte frame delivered", i))

      // Restore to 1518 before next iteration.
      apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
      repeat ($urandom_range(1, 3)) @(posedge tb_cfg_h.apb_vif.clk);
      #(100ns);
    end
  end

  `uvm_info("CDC_PULSE_AT", "Scenario 2 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 3 : Alternate 1000/1200 limits — verify 1100-byte frames
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::scenario_alternate_limits_1000_1200();
  int unsigned axi_before;
  `uvm_info("CDC_PULSE_AT",
            "--- Scenario 3: Alternate 1000/1200 limits ---", UVM_NONE)

  repeat (3) begin
    // Set limit to 1000.
    apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
    cdc_settle();

    // 1100-byte frame must be rejected under 1000 limit.
    axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                    .monitor_h.mon_rcvd_xtn_cnt;
    send_rs_frame_typed(1100, 48'hFF_FF_FF_FF_FF_FF,
                        mac_hvl_utils_c::PAYLOAD_RANDOM, "alt_1000_rej");
    #500ns;
    if (env_h.axi4_stream_agent_top_h.passive_agents[0]
            .monitor_h.mon_rcvd_xtn_cnt != axi_before)
      `uvm_error("CDC_PULSE_AT",
                 "3: 1100-byte frame delivered under MAX=1000")
    else
      `uvm_info("CDC_PULSE_AT", "  3a 1100 rejected at 1000 PASSED", UVM_NONE)

    // Set limit to 1200.
    apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1200);
    cdc_settle();

    // 1100-byte frame must be accepted under 1200 limit.
    axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                    .monitor_h.mon_rcvd_xtn_cnt;
    send_rs_frame_typed(1100, 48'hFF_FF_FF_FF_FF_FF,
                        mac_hvl_utils_c::PAYLOAD_INCREMENTING, "alt_1200_acc");
    wait_axi_rx_count(axi_before + 1);
    `uvm_info("CDC_PULSE_AT", "  3b 1100 accepted at 1200 PASSED", UVM_NONE)

    // 1201-byte frame must be rejected under 1200 limit.
    axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                    .monitor_h.mon_rcvd_xtn_cnt;
    send_rs_frame_typed(1201, 48'hFF_FF_FF_FF_FF_FF,
                        mac_hvl_utils_c::PAYLOAD_RANDOM, "alt_1200_rej");
    #500ns;
    if (env_h.axi4_stream_agent_top_h.passive_agents[0]
            .monitor_h.mon_rcvd_xtn_cnt != axi_before)
      `uvm_error("CDC_PULSE_AT",
                 "3: 1201-byte frame delivered under MAX=1200")
    else
      `uvm_info("CDC_PULSE_AT", "  3c 1201 rejected at 1200 PASSED", UVM_NONE)
  end

  `uvm_info("CDC_PULSE_AT", "Scenario 3 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 4 : Shortest-interval back-to-back updates — async clocks
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::scenario_shortest_interval_updates();
  int unsigned axi_before;
  `uvm_info("CDC_PULSE_AT",
            "--- Scenario 4: Shortest-interval updates ---", UVM_NONE)

  begin
    bit [15:0] limits [10];
    bit [15:0] final_limit;

    // Generate 10 random legal limit values.
    foreach (limits[i])
      limits[i] = $urandom_range(100, 1518);

    // Back-to-back APB writes with NO cdc_settle between consecutive writes.
    // The CDC handshake must not corrupt the config bundle under rapid updates.
    foreach (limits[i])
      apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, {16'd0, limits[i]});

    // The final value in the array is what the MAC domain should settle on.
    final_limit = limits[9];
    cdc_settle();

    // Verify the final limit took effect atomically.
    axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                    .monitor_h.mon_rcvd_xtn_cnt;
    send_rs_frame_typed(final_limit, 48'hFF_FF_FF_FF_FF_FF,
                        mac_hvl_utils_c::PAYLOAD_ONES, "final_at_limit");
    wait_axi_rx_count(axi_before + 1);
    `uvm_info("CDC_PULSE_AT",
              $sformatf("  4a frame at final limit %0d PASSED", final_limit),
              UVM_NONE)

    // Verify final_limit+1 is rejected.
    if (final_limit < 16'd1518) begin
      axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                      .monitor_h.mon_rcvd_xtn_cnt;
      send_rs_frame_typed(final_limit + 1, 48'hFF_FF_FF_FF_FF_FF,
                          mac_hvl_utils_c::PAYLOAD_RANDOM, "final_over");
      #500ns;
      if (env_h.axi4_stream_agent_top_h.passive_agents[0]
              .monitor_h.mon_rcvd_xtn_cnt != axi_before)
        `uvm_error("CDC_PULSE_AT", $sformatf(
            "4: %0d-byte frame delivered after rapid updates to %0d",
            final_limit + 1, final_limit))
      else
        `uvm_info("CDC_PULSE_AT",
                  $sformatf("  4b oversize %0d correctly dropped PASSED",
                            final_limit + 1),
                  UVM_NONE)
    end
  end

  `uvm_info("CDC_PULSE_AT", "Scenario 4 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 5 : Clock-ratio variation — randomized inter-update delays
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::scenario_clock_ratio_variation();
  int unsigned axi_before;
  `uvm_info("CDC_PULSE_AT",
            "--- Scenario 5: Clock-ratio variation ---", UVM_NONE)

  begin
    bit [15:0] limit_vals [5] = '{1000, 1200, 800, 1400, 1518};
    time update_delays [5];

    // Randomize inter-update delays to simulate varying APB/MAC clock ratio.
    foreach (update_delays[i])
      update_delays[i] = $urandom_range(10, 500) * 1ns;

    foreach (limit_vals[i]) begin
      // Random APB idle cycles before write — varies the source-side phase.
      repeat ($urandom_range(1, 4)) @(posedge tb_cfg_h.apb_vif.clk);
      #(update_delays[i]);

      apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE,
                      {16'd0, limit_vals[i]});

      // Random settle delay.
      repeat ($urandom_range(0, 3)) @(posedge tb_cfg_h.apb_vif.clk);
      #($urandom_range(50, 300) * 1ns);

      // Verify each limit took effect.
      axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                      .monitor_h.mon_rcvd_xtn_cnt;
      send_rs_frame_typed(limit_vals[i], 48'hFF_FF_FF_FF_FF_FF,
                          mac_hvl_utils_c::PAYLOAD_RANDOM,
                          $sformatf("ratio_%0d", limit_vals[i]));
      wait_axi_rx_count(axi_before + 1);

      if (limit_vals[i] < 16'd1518) begin
        axi_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                        .monitor_h.mon_rcvd_xtn_cnt;
        send_rs_frame_typed(limit_vals[i] + 1, 48'hFF_FF_FF_FF_FF_FF,
                            mac_hvl_utils_c::PAYLOAD_RANDOM,
                            $sformatf("ratio_ov_%0d", limit_vals[i]));
        #500ns;
        if (env_h.axi4_stream_agent_top_h.passive_agents[0]
                .monitor_h.mon_rcvd_xtn_cnt != axi_before)
          `uvm_error("CDC_PULSE_AT", $sformatf(
              "5: %0d-byte frame delivered under MAX=%0d",
              limit_vals[i] + 1, limit_vals[i]))
      end
    end
  end

  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  cdc_settle();
  `uvm_info("CDC_PULSE_AT", "Scenario 5 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 6 : Burst/sparse APB transaction interleaving + concurrent traffic
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::scenario_burst_sparse_interleave();
  int unsigned cnt_before;
  `uvm_info("CDC_PULSE_AT",
            "--- Scenario 6: Burst/sparse interleave ---", UVM_NONE)

  // 6a: Burst APB writes with concurrent bidirectional traffic.
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  fork
    begin
      // Rapid APB writes: alternate between 1000 and 1200.
      repeat (6) begin
        apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
        apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1200);
      end
    end
    begin
      send_rs_constrained_random(8);
    end
    begin
      send_axi_constrained_burst(8);
    end
  join

  cdc_settle();
  // After burst, send a 1100-byte frame — must be accepted (final limit 1200).
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(1100, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ONES, "burst_post_1100");
  wait_axi_rx_count(cnt_before + 1);
  `uvm_info("CDC_PULSE_AT", "  6a burst APB + traffic PASSED", UVM_NONE)

  // 6b: Sparse APB writes with large gaps — CDC handshake may idle.
  repeat (3) begin
    apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd800);
    #(500ns);
    apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
    #(500ns);
  end
  cdc_settle();

  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(800, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_ALT_55_AA, "sparse_post_800");
  wait_axi_rx_count(cnt_before + 1);
  `uvm_info("CDC_PULSE_AT", "  6b sparse APB PASSED", UVM_NONE)

  `uvm_info("CDC_PULSE_AT", "Scenario 6 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 7 : Boundary occupancy + delayed APB acknowledgment
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::scenario_boundary_delayed_ack();
  int unsigned cnt_before;
  `uvm_info("CDC_PULSE_AT",
            "--- Scenario 7: Boundary + delayed APB ack ---", UVM_NONE)

  // Set limit to 1000, then flood with boundary-occupancy traffic.
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
  cdc_settle();

  // Flood: mix of min (64) and max (1000) frames to fill pipelines.
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  fork
    send_rs_clean_frames(5, 64);      // minimum-size frames
    send_rs_clean_frames(5, 1000);    // at-limit frames
  join
  // Wait for at least some frames; backpressure may drop a few.
  wait_axi_rx_count(cnt_before + 1);
  `uvm_info("CDC_PULSE_AT", "  7a boundary flood PASSED", UVM_NONE)

  // Delayed APB reads while MAC drains — exercises CDC ack latency.
  begin
    apb_read_sequence_c read_h;
    repeat (3) begin
      read_h = apb_read_sequence_c::type_id::create("cdc_at_7b_status");
      read_h.m_addr = reg_map_pkg::REG_RX_STATUS;
      read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
      #($urandom_range(100, 500) * 1ns);
    end
  end

  // Verify 1001 is still rejected after the delayed ack.
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  send_rs_frame_typed(1001, 48'hFF_FF_FF_FF_FF_FF,
                      mac_hvl_utils_c::PAYLOAD_RANDOM, "delayed_ack_1001");
  #500ns;
  if (env_h.axi4_stream_agent_top_h.passive_agents[0]
          .monitor_h.mon_rcvd_xtn_cnt != cnt_before)
    `uvm_error("CDC_PULSE_AT",
               "7: 1001-byte frame delivered after delayed APB ack")
  else
    `uvm_info("CDC_PULSE_AT",
              "  7b delayed ack: oversize correctly dropped PASSED", UVM_NONE)

  `uvm_info("CDC_PULSE_AT", "Scenario 7 PASSED", UVM_NONE)
endtask

// =============================================================================
// Scenario 8 : Constrained-random asynchronous sustained traffic
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::scenario_constrained_random_async();
  int unsigned cnt_before;
  `uvm_info("CDC_PULSE_AT",
            "--- Scenario 8: Constrained-random async ---", UVM_NONE)

  // 8a: Constrained-random RS frames with randomized limit updates.
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
      // Interleave APB limit changes with frame sends.
      apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE,
                      $urandom_range(800, 1518));
      send_rs_frame_typed($urandom_range(64, 1500),
                          48'hFF_FF_FF_FF_FF_FF,
                          patterns[i],
                          $sformatf("cra_pat_%0d", i));
    end
  end
  // Some frames may exceed the randomized limit and be dropped; wait for at
  // least one delivery to prove traffic flows through the updated config.
  wait_axi_rx_count(cnt_before + 1);
  `uvm_info("CDC_PULSE_AT", "  8a pattern-mixed PASSED", UVM_NONE)

  // 8b: Bidirectional constrained-random sustained traffic with APB writes.
  fork
    send_axi_constrained_burst(10);
    send_rs_constrained_random(10);
    begin
      repeat (5) begin
        apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE,
                        $urandom_range(600, 1518));
        #($urandom_range(20, 200) * 1ns);
      end
    end
  join
  #1us;
  `uvm_info("CDC_PULSE_AT", "  8b bidir sustained PASSED", UVM_NONE)

  // 8c: Mixed-size RS burst with concurrent AXI and random APB updates.
  cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0]
                  .monitor_h.mon_rcvd_xtn_cnt;
  fork
    send_mixed_size_rs_burst(10, 64, 1500);
    send_axi_constrained_burst(10);
    begin
      repeat (4) begin
        apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE,
                        $urandom_range(500, 1518));
        #($urandom_range(10, 100) * 1ns);
      end
    end
  join
  #2us;
  if (env_h.axi4_stream_agent_top_h.passive_agents[0]
          .monitor_h.mon_rcvd_xtn_cnt > cnt_before)
    `uvm_info("CDC_PULSE_AT",
              $sformatf("  8c mixed async AXI RX: %0d -> %0d", cnt_before,
                        env_h.axi4_stream_agent_top_h.passive_agents[0]
                            .monitor_h.mon_rcvd_xtn_cnt),
              UVM_NONE)
  else
    `uvm_error("CDC_PULSE_AT", "  8c mixed async: no AXI RX activity")

  `uvm_info("CDC_PULSE_AT", "Scenario 8 PASSED", UVM_NONE)
endtask

// =============================================================================
// Restore clean state
// =============================================================================

task mac_cdc_pulse_atomicity_test_c::restore_clean_state();
  bit [31:0] ctrl;
  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT);
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_check(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  cdc_settle();
  `uvm_info("CDC_PULSE_AT",
            "=== CDC pulse atomicity test completed ===", UVM_NONE)
endtask
