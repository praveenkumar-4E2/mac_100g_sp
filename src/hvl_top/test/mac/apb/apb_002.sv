// MAC-APB-002: verify APB configuration bundles reach the MAC clock domain
// atomically and affect RX filtering/size admission as software programmed.
class mac_apb_config_cdc_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_apb_config_cdc_test_c)

  extern function new(string name = "mac_apb_config_cdc_test_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
  extern task apb_write_check(bit [15:0] addr, bit [31:0] data,
                               bit expect_slverr = 1'b0);
  extern task apb_read_check(bit [15:0] addr, bit [31:0] expected, bit [31:0] mask = '1,
                              bit expect_slverr = 1'b0);
  extern task cdc_settle();
  extern task send_and_check(int unsigned frame_octets, bit [47:0] destination,
                             apb_002_rx_frame_sequence_c::payload_pattern_e pattern,
                             bit expect_delivery, string check_name);
  extern task random_apb_accesses(int unsigned count = 24);
endclass

function mac_apb_config_cdc_test_c::new(string name = "mac_apb_config_cdc_test_c",
                                         uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents   = 1;
  num_axi_passive_agents = 1;
endfunction

function void mac_apb_config_cdc_test_c::configure_test();
  super.configure_test();
  // This test deliberately checks the monitor count for dropped RX frames;
  // the reference model observes APB writes before their CDC latency.
  env_cfg_h.has_scoreboard = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = 1600;
  env_cfg_h.apb_active_agent_cfgs[0].m_fail_on_unexpected_slverr = 1'b0;
endfunction

task mac_apb_config_cdc_test_c::apb_write_check(bit [15:0] addr, bit [31:0] data,
                                                  bit expect_slverr = 1'b0);
  apb_write_sequence_c write_h;
  write_h = apb_write_sequence_c::type_id::create($sformatf("apb_002_wr_%h", addr));
  write_h.m_addr = addr;
  write_h.m_wdata = data;
  write_h.m_expect_slverr = expect_slverr;
  write_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_apb_config_cdc_test_c::apb_read_check(bit [15:0] addr, bit [31:0] expected,
                                                 bit [31:0] mask = '1,
                                                 bit expect_slverr = 1'b0);
  apb_read_sequence_c read_h;
  read_h = apb_read_sequence_c::type_id::create($sformatf("apb_002_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.m_expect_slverr = expect_slverr;
  read_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  if (!expect_slverr && ((read_h.m_rdata & mask) !== (expected & mask)))
    `uvm_error("APB_002_READBACK", $sformatf("addr=%h got=%h expected=%h mask=%h",
                                               addr, read_h.m_rdata, expected, mask))
endtask

task mac_apb_config_cdc_test_c::cdc_settle();
  // Covers APB/MAC phase variation: the two asynchronous clocks advance
  // during the handshake; randomized legal APB-idle cycles vary write phase.
  repeat ($urandom_range(0, 3)) @(posedge tb_cfg_h.apb_vif.clk);
  #250ns;
endtask

task mac_apb_config_cdc_test_c::send_and_check(
    int unsigned frame_octets, bit [47:0] destination,
    apb_002_rx_frame_sequence_c::payload_pattern_e pattern, bit expect_delivery, string check_name);
  apb_002_rx_frame_sequence_c frame_seq_h;
  int unsigned before_count;
  bit timed_out;

  before_count = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  frame_seq_h = apb_002_rx_frame_sequence_c::type_id::create({"apb_002_", check_name});
  frame_seq_h.frame_octets = frame_octets;
  frame_seq_h.destination = destination;
  frame_seq_h.payload_pattern = pattern;
  frame_seq_h.payload_seed = $urandom;
  frame_seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  if (expect_delivery) begin
    mac_wait_utils_c::wait_for_axi_count_at_least(
        before_count + 1,
        env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
        axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
    if (timed_out)
      `uvm_error("APB_002_EFFECT", $sformatf("%s: expected %0d-byte frame delivery",
                                                check_name, frame_octets))
  end else begin
    #500ns;
    if (env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt != before_count)
      `uvm_error("APB_002_EFFECT", $sformatf("%s: unexpected %0d-byte frame delivery",
                                                check_name, frame_octets))
  end
endtask

task mac_apb_config_cdc_test_c::random_apb_accesses(int unsigned count = 24);
  bit [15:0] legal_addrs [5] = '{reg_map_pkg::REG_GLOBAL_CONTROL,
                                  reg_map_pkg::REG_MAX_FRAME_SIZE,
                                  reg_map_pkg::REG_MIN_FRAME_SIZE,
                                  reg_map_pkg::group_low_addr(0),
                                  reg_map_pkg::group_high_addr(0)};
  bit [15:0] invalid_addrs [3] = '{16'h0001, 16'h004e, 16'h00a0};
  repeat (count) begin
    if ($urandom_range(0, 3) == 0) begin
      if ($urandom_range(0, 1)) apb_write_check(invalid_addrs[$urandom_range(0, 2)], $urandom, 1'b1);
      else apb_read_check(invalid_addrs[$urandom_range(0, 2)], '0, '1, 1'b1);
    end else if ($urandom_range(0, 1)) begin
      apb_write_check(legal_addrs[$urandom_range(0, 4)], $urandom);
    end else begin
      // Legal reads are intentionally interleaved with writes.  Their value
      // is dynamic during this stress phase, so only the APB response is checked.
      apb_read_check(legal_addrs[$urandom_range(0, 4)], '0, '0);
    end
  end
endtask

task mac_apb_config_cdc_test_c::run_stimulus(uvm_phase phase);
  bit [31:0] patterns [5];
  bit [31:0] control_cfg;
  bit [47:0] group_addr = 48'h02_00_00_00_20_02;

  control_cfg = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
                (32'h1 << reg_map_pkg::CTRL_PAUSE_BIT);
  // RX/PAUSE enable plus default 64/1518 limits: APB readback and MAC-domain
  // effect are both checked below.
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, control_cfg);
  apb_write_check(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  apb_read_check(reg_map_pkg::REG_GLOBAL_CONTROL, control_cfg, 32'h0000_00ff);
  apb_read_check(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64, 32'h0000_ffff);
  apb_read_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518, 32'h0000_ffff);
  cdc_settle();
  send_and_check(64, 48'hff_ff_ff_ff_ff_ff, mac_hvl_utils_c::PAYLOAD_ZERO, 1'b1,
                 "minimum_64");
  send_and_check(1518, 48'hff_ff_ff_ff_ff_ff, mac_hvl_utils_c::PAYLOAD_ONES, 1'b1,
                 "limit_1518");

  // Change the MAC limit under varying APB/MAC phase, then verify both sides
  // of the new externally visible boundary.
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
  cdc_settle();
  send_and_check(1000, 48'hff_ff_ff_ff_ff_ff, mac_hvl_utils_c::PAYLOAD_ALT_AA_55, 1'b1,
                 "limit_1000");
  send_and_check(1001, 48'hff_ff_ff_ff_ff_ff, mac_hvl_utils_c::PAYLOAD_ALT_55_AA, 1'b0,
                 "oversize_1001");

  // Group-valid is part of the same CDC bundle as its address.  A group DA
  // must pass only while its valid bit is set.
  apb_write_check(reg_map_pkg::group_low_addr(0), group_addr[31:0]);
  apb_write_check(reg_map_pkg::group_high_addr(0), {15'd0, 1'b1, group_addr[47:32]});
  apb_read_check(reg_map_pkg::group_high_addr(0), {15'd0, 1'b1, group_addr[47:32]}, 32'h0001_ffff);
  cdc_settle();
  send_and_check(1000, group_addr, mac_hvl_utils_c::PAYLOAD_RANDOM, 1'b1, "group_valid_1");
  apb_write_check(reg_map_pkg::group_high_addr(0), {16'd0, group_addr[47:32]});
  cdc_settle();
  send_and_check(1000, group_addr, mac_hvl_utils_c::PAYLOAD_ZERO, 1'b0, "group_valid_0");

  // Back-to-back APB updates exercise the bridge's snapshot semantics: only
  // the final 1200-byte bundle may be visible to subsequent RX traffic.
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1200);
  cdc_settle();
  send_and_check(1100, 48'hff_ff_ff_ff_ff_ff, mac_hvl_utils_c::PAYLOAD_ONES, 1'b1,
                 "back_to_back_1100");
  send_and_check(1201, 48'hff_ff_ff_ff_ff_ff, mac_hvl_utils_c::PAYLOAD_RANDOM, 1'b0,
                 "back_to_back_1201");

  patterns = '{32'h0000_0000, 32'hffff_ffff, 32'haaaa_aaaa, 32'h5555_5555, $urandom};
  foreach (patterns[i]) begin
    apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, patterns[i]);
    apb_read_check(reg_map_pkg::REG_GLOBAL_CONTROL, patterns[i], 32'h0000_00ff);
  end
  random_apb_accesses();
  // Restore a known legal configuration for clean end-of-test state.
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, control_cfg);
  apb_write_check(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  cdc_settle();
  `uvm_info("APB_002", "APB configuration CDC/readback/effect scenario completed", UVM_NONE)
endtask
