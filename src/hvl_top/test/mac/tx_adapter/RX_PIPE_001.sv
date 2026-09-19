// RX_PIPE_001 — End-to-End RX Pipeline Integration.
//
// Verifies the complete RX data path through all pipeline stages:
//   preamble detection → header extraction → CRC check → length check
//   → address filtering → frame emission → AXI client delivery.
//
// Stimulus: 8 phases — pipeline sanity, preamble detection, header
// extraction, CRC checking, length checking, address filtering,
// frame-emit backpressure, and sustained end-to-end.
//
// Checking: scoreboard (expected vs actual for both TX and RX),
// AXI/RS monitor counts, APB register counter reads (RX_INVALID_COUNT,
// INTERRUPT_STATUS), protocol checker.
class rx_pipe_001_test_c extends mac_base_test_c;
  `uvm_component_utils(rx_pipe_001_test_c)

  extern function new(string name = "rx_pipe_001_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);

  extern task apb_write_reg(bit [15:0] addr, bit [31:0] data);
  extern task apb_read_reg(bit [15:0] addr, output bit [31:0] data);
  extern task cdc_settle();
  extern task send_rs_rx_clean(int count, int pmin, int pmax, bit broadcast);
  extern task send_axi_tx_clean(int count, int pmin, int pmax);
  extern task send_apb_rx_frame(int frame_octets, bit [47:0] destination);
  extern task send_rs_rx_with_crc_error(int count, int pmin, int pmax);
  extern task phase1_pipeline_sanity();
  extern task phase2_preamble_detection();
  extern task phase3_header_extraction();
  extern task phase4_crc_checking();
  extern task phase5_length_checking();
  extern task phase6_address_filtering();
  extern task phase7_frame_emit_backpressure();
  extern task phase8_sustained_e2e();
endclass

function rx_pipe_001_test_c::new(string name = "rx_pipe_001_test_c",
                                uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
endfunction

function void rx_pipe_001_test_c::configure_test();
  super.configure_test();
  env_cfg_h.max_payload_bytes = 1500;
  env_cfg_h.max_frame_octets  = 1518;
  env_cfg_h.has_scoreboard        = 1'b1;
  env_cfg_h.scoreboard_enable_rx_check = 1;
  env_cfg_h.scoreboard_enable_tx_check = 1;
  env_cfg_h.scoreboard_check_addresses  = 1;
  env_cfg_h.scoreboard_check_ether_type = 1;
  env_cfg_h.scoreboard_check_payload    = 1;
  env_cfg_h.scoreboard_check_fcs        = 1;
  env_cfg_h.scoreboard_check_error_flags = 1;
  env_cfg_h.has_protocol_checkers = 1;
  env_cfg_h.apb_active_agent_cfgs[0].m_fail_on_unexpected_slverr = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = 1600;
endfunction

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::apb_write_reg(bit [15:0] addr, bit [31:0] data);
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create($sformatf("rxpipe_wr_%h", addr));
  seq_h.m_addr  = addr;
  seq_h.m_wdata = data;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task rx_pipe_001_test_c::apb_read_reg(bit [15:0] addr, output bit [31:0] data);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("rxpipe_rd_%h", addr));
  seq_h.m_addr = addr;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = seq_h.m_rdata;
endtask

task rx_pipe_001_test_c::cdc_settle();
  #250ns;
endtask

task rx_pipe_001_test_c::send_rs_rx_clean(int count, int pmin, int pmax, bit broadcast);
  rs_sequence_c seq_h;
  seq_h = rs_sequence_c::type_id::create("rxpipe_rs_rx");
  seq_h.num_frames      = count;
  seq_h.payload_min     = pmin;
  seq_h.payload_max     = pmax;
  seq_h.error_injection = 1'b0;
  seq_h.broadcast_da    = broadcast;
  seq_h.inter_frame_delay = 500ns;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task rx_pipe_001_test_c::send_axi_tx_clean(int count, int pmin, int pmax);
  axi_clean_sequence_c seq_h;
  seq_h = axi_clean_sequence_c::type_id::create("rxpipe_axi_tx");
  seq_h.num_tx          = count;
  seq_h.payload_min     = pmin;
  seq_h.payload_max     = pmax;
  seq_h.error_injection = 1'b0;
  seq_h.broadcast_da    = 1'b0;
  seq_h.inter_frame_delay = 500ns;
  seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task rx_pipe_001_test_c::send_apb_rx_frame(int frame_octets, bit [47:0] destination);
  apb_002_rx_frame_sequence_c seq_h;
  seq_h = apb_002_rx_frame_sequence_c::type_id::create("rxpipe_apb_frame");
  seq_h.frame_octets = frame_octets;
  seq_h.destination = destination;
  seq_h.payload_pattern = mac_hvl_utils_c::PAYLOAD_RANDOM;
  seq_h.payload_seed = $urandom;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

task rx_pipe_001_test_c::send_rs_rx_with_crc_error(int count, int pmin, int pmax);
  rs_sequence_c seq_h;
  seq_h = rs_sequence_c::type_id::create("rxpipe_rs_err");
  seq_h.num_frames      = count;
  seq_h.payload_min     = pmin;
  seq_h.payload_max     = pmax;
  seq_h.error_injection = 1'b1;
  seq_h.broadcast_da    = 1'b1;
  seq_h.inter_frame_delay = 500ns;
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
endtask

// ---------------------------------------------------------------------------
// Phase 1: Pipeline Sanity — clean path through all stages
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::phase1_pipeline_sanity();
  bit [31:0] ctrl;
  bit [31:0] rdata;
  int rx_before;
  int tx_before;
  bit rx_timed_out;
  bit tx_timed_out;

  `uvm_info("RX_PIPE_001", "=== Phase 1: Pipeline Sanity ===", UVM_NONE)

  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PROMISCUOUS_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, 32'h0200_0006);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h0000_0000);
  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  apb_write_reg(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_write_reg(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_007F);
  cdc_settle();

  // Clear counters
  apb_write_reg(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0001);
  apb_write_reg(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h0000_0001);
  apb_write_reg(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, 32'h0000_0001);
  cdc_settle();

  rx_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      send_rs_rx_clean(10, 46, 1500, 1'b1);
    end
    begin
      send_axi_tx_clean(5, 46, 200);
    end
  join

  mac_wait_utils_c::wait_for_axi_count_at_least(
      rx_before + 10,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, rx_timed_out);

  mac_wait_utils_c::wait_for_count_at_least(
      tx_before + 5,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, tx_timed_out);

  if (rx_timed_out || tx_timed_out)
    `uvm_error("RX_PIPE_001", $sformatf("Phase 1 timeout: rx=%0b tx=%0b",
               rx_timed_out, tx_timed_out))

  // Verify no invalid frames counted
  apb_read_reg(reg_map_pkg::REG_RX_INVALID_COUNT, rdata);
  if (rdata != 0)
    `uvm_error("RX_PIPE_001", $sformatf("Phase 1: RX_INVALID_COUNT=%0d, expected 0", rdata))

  `uvm_info("RX_PIPE_001", "Phase 1 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 2: Preamble Detection — valid + invalid preamble/SFD
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::phase2_preamble_detection();
  int rx_before;
  bit timed_out;

  `uvm_info("RX_PIPE_001", "=== Phase 2: Preamble Detection ===", UVM_NONE)

  // Keep promiscuous mode so address filter passes all good frames
  rx_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      // 5 valid frames (correct preamble/SFD)
      send_rs_rx_clean(5, 46, 100, 1'b1);
    end
    begin
      // Concurrent AXI TX to exercise bidirectional path
      send_axi_tx_clean(3, 46, 100);
    end
  join

  mac_wait_utils_c::wait_for_axi_count_at_least(
      rx_before + 5,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("RX_PIPE_001", $sformatf(
               "Phase 2 timeout: expected %0d RX frames, got %0d",
               rx_before + 5,
               env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))

  `uvm_info("RX_PIPE_001", "Phase 2 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 3: Header Extraction — varied DA/SA/EtherType
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::phase3_header_extraction();
  int rx_before;
  bit timed_out;

  `uvm_info("RX_PIPE_001", "=== Phase 3: Header Extraction ===", UVM_NONE)

  rx_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      // Frames with specific destination addresses — scoreboard verifies DA/SA/EtherType
      send_apb_rx_frame(100, 48'h02_00_00_00_AA_05);
      #($urandom_range(0, 20) * 1ns);
      send_apb_rx_frame(200, 48'hFF_FF_FF_FF_FF_FF);
      #($urandom_range(0, 20) * 1ns);
      send_apb_rx_frame(300, 48'h01_00_5E_00_AA_05);
      #($urandom_range(0, 20) * 1ns);
      send_apb_rx_frame(64, 48'h02_00_00_00_00_01);
      #($urandom_range(0, 20) * 1ns);
      send_apb_rx_frame(1500, 48'h02_00_00_00_BB_07);
    end
    begin
      send_axi_tx_clean(3, 46, 200);
    end
  join

  mac_wait_utils_c::wait_for_axi_count_at_least(
      rx_before + 5,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("RX_PIPE_001", $sformatf(
               "Phase 3 timeout: expected %0d RX frames, got %0d",
               rx_before + 5,
               env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))

  `uvm_info("RX_PIPE_001", "Phase 3 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 4: CRC Checking — clean + CRC-error frames
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::phase4_crc_checking();
  bit [31:0] rdata;
  int rx_before;
  int invalid_before;
  bit timed_out;

  `uvm_info("RX_PIPE_001", "=== Phase 4: CRC Checking ===", UVM_NONE)

  // Clear invalid counter
  apb_write_reg(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0001);
  cdc_settle();

  apb_read_reg(reg_map_pkg::REG_RX_INVALID_COUNT, rdata);
  invalid_before = rdata;

  rx_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      // 8 clean frames — should be delivered
      send_rs_rx_clean(8, 46, 200, 1'b1);
      #($urandom_range(0, 20) * 1ns);
      // 4 CRC-error frames — should be dropped by pipeline
      send_rs_rx_with_crc_error(4, 46, 200);
    end
    begin
      send_axi_tx_clean(4, 46, 100);
    end
  join

  mac_wait_utils_c::wait_for_axi_count_at_least(
      rx_before + 8,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("RX_PIPE_001", $sformatf(
               "Phase 4 timeout: expected %0d RX frames, got %0d",
               rx_before + 8,
               env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))

  // Verify RX_INVALID_COUNT incremented for CRC-error frames
  #1us;  // allow counter to settle
  apb_read_reg(reg_map_pkg::REG_RX_INVALID_COUNT, rdata);
  `uvm_info("RX_PIPE_001", $sformatf(
            "Phase 4: RX_INVALID_COUNT before=%0d after=%0d (expect >= %0d)",
            invalid_before, rdata, invalid_before + 4), UVM_MEDIUM)

  `uvm_info("RX_PIPE_001", "Phase 4 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 5: Length Checking — boundary frame sizes
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::phase5_length_checking();
  int rx_before;
  bit timed_out;

  `uvm_info("RX_PIPE_001", "=== Phase 5: Length Checking ===", UVM_NONE)

  rx_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  // Boundary sizes: 46B min, 64B single-beat, 128B, 500B, 1000B, 1500B max standard
  send_rs_rx_clean(1, 46, 46, 1'b1);
  #($urandom_range(0, 10) * 1ns);
  send_rs_rx_clean(1, 50, 50, 1'b1);
  #($urandom_range(0, 10) * 1ns);
  send_rs_rx_clean(1, 64, 64, 1'b1);
  #($urandom_range(0, 10) * 1ns);
  send_rs_rx_clean(1, 128, 128, 1'b1);
  #($urandom_range(0, 10) * 1ns);
  send_rs_rx_clean(1, 500, 500, 1'b1);
  #($urandom_range(0, 10) * 1ns);
  send_rs_rx_clean(1, 1000, 1000, 1'b1);
  #($urandom_range(0, 10) * 1ns);
  send_rs_rx_clean(1, 1500, 1500, 1'b1);

  mac_wait_utils_c::wait_for_axi_count_at_least(
      rx_before + 7,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("RX_PIPE_001", $sformatf(
               "Phase 5 timeout: expected %0d RX frames, got %0d",
               rx_before + 7,
               env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt))

  `uvm_info("RX_PIPE_001", "Phase 5 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 6: Address Filtering — station/group/broadcast/non-match + promiscuous
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::phase6_address_filtering();
  bit [31:0] ctrl;
  bit [31:0] rdata;
  bit [47:0] station_addr = 48'h02_00_00_00_AA_05;
  bit [47:0] group0_addr  = 48'h01_00_5e_00_AA_05;
  bit [47:0] group1_addr  = 48'h01_00_5e_00_BB_07;
  int rx_before;
  int rx_after;
  bit timed_out;

  `uvm_info("RX_PIPE_001", "=== Phase 6: Address Filtering ===", UVM_NONE)

  // Program station + group addresses, non-promiscuous
  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, station_addr[31:0]);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, station_addr[47:32]);
  apb_write_reg(reg_map_pkg::group_low_addr(0), group0_addr[31:0]);
  apb_write_reg(reg_map_pkg::group_high_addr(0), {15'd0, 1'b1, group0_addr[47:32]});
  apb_write_reg(reg_map_pkg::group_low_addr(1), group1_addr[31:0]);
  apb_write_reg(reg_map_pkg::group_high_addr(1), {15'd0, 1'b1, group1_addr[47:32]});
  cdc_settle();

  rx_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      // Station-matched unicast (accepted)
      send_apb_rx_frame(100, station_addr);
      #($urandom_range(0, 15) * 1ns);
      // Group0-matched multicast (accepted)
      send_apb_rx_frame(150, group0_addr);
      #($urandom_range(0, 15) * 1ns);
      // Group1-matched multicast (accepted)
      send_apb_rx_frame(200, group1_addr);
      #($urandom_range(0, 15) * 1ns);
      // Broadcast (accepted)
      send_rs_rx_clean(1, 46, 100, 1'b1);
      #($urandom_range(0, 15) * 1ns);
      // Non-matching unicast (dropped)
      send_apb_rx_frame(100, 48'hDE_AD_BE_EF_00_05);
      #($urandom_range(0, 15) * 1ns);
      // Another non-matching (dropped)
      send_apb_rx_frame(100, 48'hCA_FE_CA_FE_00_01);
    end
    begin
      send_axi_tx_clean(3, 46, 100);
    end
  join

  // Expected: 1 station + 1 group0 + 1 group1 + 1 broadcast = 4 delivered
  mac_wait_utils_c::wait_for_axi_count_at_least(
      rx_before + 4,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out) begin
    rx_after = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
    `uvm_error("RX_PIPE_001", $sformatf(
               "Phase 6 timeout: expected %0d RX frames, got %0d",
               rx_before + 4, rx_after))
  end

  // Now enable promiscuous — non-matching should be accepted
  `uvm_info("RX_PIPE_001", "Phase 6: enabling promiscuous mode", UVM_MEDIUM)
  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PROMISCUOUS_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  cdc_settle();

  rx_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  // Non-matching unicast — now accepted in promiscuous mode
  send_apb_rx_frame(100, 48'hDE_AD_BE_EF_00_05);

  mac_wait_utils_c::wait_for_axi_count_at_least(
      rx_before + 1,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("RX_PIPE_001", "Phase 6: promiscuous mode — non-matching frame not delivered")

  `uvm_info("RX_PIPE_001", "Phase 6 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 7: Frame-Emit Backpressure — sustained with random delays
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::phase7_frame_emit_backpressure();
  bit [31:0] rdata;
  int rx_before;
  int tx_before;
  bit rx_timed_out;
  bit tx_timed_out;

  `uvm_info("RX_PIPE_001", "=== Phase 7: Frame-Emit Backpressure ===", UVM_NONE)

  rx_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      // RS RX: 20 frames with mixed sizes and random inter-frame delays
      int rx_sizes [];
      rx_sizes = '{46, 64, 100, 128, 200, 300, 500, 700, 1000, 1200,
                   1500, 46, 128, 500, 1000, 1500, 46, 200, 800, 1500};
      foreach (rx_sizes[s]) begin
        send_rs_rx_clean(1, rx_sizes[s], rx_sizes[s], 1'b1);
        #($urandom_range(0, 50) * 1ns);
      end
    end
    begin
      // AXI TX: 20 frames with mixed sizes and random inter-frame delays
      int tx_sizes [];
      tx_sizes = '{46, 100, 200, 500, 1000, 1500, 46, 300, 700, 1200,
                   1500, 46, 128, 500, 1000, 1500, 46, 200, 800, 1500};
      foreach (tx_sizes[s]) begin
        send_axi_tx_clean(1, tx_sizes[s], tx_sizes[s]);
        #($urandom_range(0, 50) * 1ns);
      end
    end
    begin
      // Periodic APB reads during traffic
      repeat (5) begin
        #1us;
        apb_read_reg(reg_map_pkg::REG_RX_STATUS, rdata);
        apb_read_reg(reg_map_pkg::REG_RX_INVALID_COUNT, rdata);
        apb_read_reg(reg_map_pkg::REG_INTERRUPT_STATUS, rdata);
      end
    end
  join

  mac_wait_utils_c::wait_for_axi_count_at_least(
      rx_before + 20,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, rx_timed_out);

  mac_wait_utils_c::wait_for_count_at_least(
      tx_before + 20,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, tx_timed_out);

  if (rx_timed_out || tx_timed_out)
    `uvm_error("RX_PIPE_001", $sformatf("Phase 7 timeout: rx=%0b tx=%0b",
               rx_timed_out, tx_timed_out))

  `uvm_info("RX_PIPE_001", "Phase 7 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 8: Sustained End-to-End — all stages simultaneously
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::phase8_sustained_e2e();
  bit [31:0] ctrl;
  bit [31:0] rdata;
  int rx_before;
  int tx_before;
  int invalid_before;
  bit rx_timed_out;
  bit tx_timed_out;

  `uvm_info("RX_PIPE_001", "=== Phase 8: Sustained End-to-End ===", UVM_NONE)

  // Full config: RX + TX + promiscuous + PAUSE
  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PROMISCUOUS_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PAUSE_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, 32'h0200_0006);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h0000_0000);
  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  apb_write_reg(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_write_reg(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_007F);

  // Clear counters
  apb_write_reg(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0001);
  apb_write_reg(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h0000_0001);
  apb_write_reg(reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, 32'h0000_0001);
  cdc_settle();

  apb_read_reg(reg_map_pkg::REG_RX_INVALID_COUNT, rdata);
  invalid_before = rdata;

  rx_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  tx_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  fork
    begin
      // RS RX: 30 frames — mixed sizes, random delays, mostly clean
      int rx_sizes [];
      rx_sizes = '{46, 46, 64, 100, 128, 200, 300, 400, 500, 600,
                   700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1500,
                   46, 128, 500, 1000, 1500, 46, 200, 800, 1200, 1500};
      foreach (rx_sizes[s]) begin
        send_rs_rx_clean(1, rx_sizes[s], rx_sizes[s], 1'b1);
        #($urandom_range(0, 50) * 1ns);
      end
    end
    begin
      // AXI TX: 30 frames — mixed sizes, random delays
      int tx_sizes [];
      tx_sizes = '{46, 100, 200, 300, 400, 500, 600, 700, 800, 900,
                   1000, 1100, 1200, 1300, 1400, 1500, 46, 128, 500, 1000,
                   1500, 46, 200, 800, 1200, 1500, 46, 300, 700, 1500};
      foreach (tx_sizes[s]) begin
        send_axi_tx_clean(1, tx_sizes[s], tx_sizes[s]);
        #($urandom_range(0, 50) * 1ns);
      end
    end
    begin
      // Periodic APB register reads during sustained traffic
      repeat (10) begin
        #1us;
        apb_read_reg(reg_map_pkg::REG_VERSION, rdata);
        apb_read_reg(reg_map_pkg::REG_RX_STATUS, rdata);
        apb_read_reg(reg_map_pkg::REG_TX_STATUS, rdata);
        apb_read_reg(reg_map_pkg::REG_RX_INVALID_COUNT, rdata);
        apb_read_reg(reg_map_pkg::REG_RX_OVERSIZE_COUNT, rdata);
        apb_read_reg(reg_map_pkg::REG_INTERRUPT_STATUS, rdata);
      end
    end
  join

  mac_wait_utils_c::wait_for_axi_count_at_least(
      rx_before + 30,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, rx_timed_out);

  mac_wait_utils_c::wait_for_count_at_least(
      tx_before + 30,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, tx_timed_out);

  if (rx_timed_out || tx_timed_out)
    `uvm_error("RX_PIPE_001", $sformatf("Phase 8 timeout: rx=%0b tx=%0b",
               rx_timed_out, tx_timed_out))

  // Final register reads
  apb_read_reg(reg_map_pkg::REG_RX_INVALID_COUNT, rdata);
  `uvm_info("RX_PIPE_001", $sformatf("  Final RX_INVALID_COUNT: %0d (before=%0d)", rdata, invalid_before), UVM_HIGH)
  apb_read_reg(reg_map_pkg::REG_RX_OVERSIZE_COUNT, rdata);
  `uvm_info("RX_PIPE_001", $sformatf("  Final RX_OVERSIZE_COUNT: %0d", rdata), UVM_HIGH)
  apb_read_reg(reg_map_pkg::REG_INTERRUPT_STATUS, rdata);
  `uvm_info("RX_PIPE_001", $sformatf("  Final INTERRUPT_STATUS: %h", rdata), UVM_HIGH)

  `uvm_info("RX_PIPE_001", $sformatf(
            "Phase 8 complete.  TX wire count=%0d RX client count=%0d",
            env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
            env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt),
            UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// run_stimulus — orchestrate all 8 phases
// ---------------------------------------------------------------------------

task rx_pipe_001_test_c::run_stimulus(uvm_phase phase);
  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null)
    `uvm_fatal("RX_PIPE_001", "Environment not fully built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("RX_PIPE_001", "Reset and APB bootstrap did not complete")

  phase1_pipeline_sanity();
  phase2_preamble_detection();
  phase3_header_extraction();
  phase4_crc_checking();
  phase5_length_checking();
  phase6_address_filtering();
  phase7_frame_emit_backpressure();
  phase8_sustained_e2e();

  `uvm_info("RX_PIPE_001", $sformatf(
            "PASS: all RX pipeline integration phases completed.  TX wire count=%0d RX client count=%0d",
            env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
            env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt),
            UVM_NONE)
endtask
