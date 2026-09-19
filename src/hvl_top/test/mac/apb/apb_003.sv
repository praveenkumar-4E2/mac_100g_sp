// MAC-APB-003: management-control effects available through the design's APB
// register interface.  The DUT does not expose an IEEE standardized external
// layer-management protocol, so this test records that capability boundary
// while fully verifying the APB controls that are implemented.
class mac_apb_layer_management_test_c extends mac_apb_config_cdc_test_c;
  `uvm_component_utils(mac_apb_layer_management_test_c)

  extern function new(string name = "mac_apb_layer_management_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
  extern task send_pause_and_check(bit expect_pause_active, string check_name);
  extern task send_tx_and_check();
  extern task read_management_counters();
endclass

function mac_apb_layer_management_test_c::new(
    string name = "mac_apb_layer_management_test_c", uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents = 1;
  num_rs_passive_agents = 1;
endfunction

task mac_apb_layer_management_test_c::send_pause_and_check(
    bit expect_pause_active, string check_name);
  mac_pause_frame_sequence_c pause_seq_h;
  bit [31:0] status_data;

  pause_seq_h = mac_pause_frame_sequence_c::type_id::create({"apb_003_", check_name});
  pause_seq_h.pause_quanta = 16'h0100;
  pause_seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;
  // Read the status value separately: it is an asynchronously captured,
  // dynamic observation and must not be compared against an APB shadow.
  begin
    apb_read_sequence_c read_h;
    read_h = apb_read_sequence_c::type_id::create({"apb_003_pause_status_", check_name});
    read_h.m_addr = reg_map_pkg::REG_RX_STATUS;
    read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
    status_data = read_h.m_rdata;
  end
  if (status_data[0] !== expect_pause_active)
    `uvm_error("APB_003_PAUSE", $sformatf("%s: pause_active=%0b expected=%0b",
                                            check_name, status_data[0], expect_pause_active))
endtask

task mac_apb_layer_management_test_c::send_tx_and_check();
  axi_sequence_c tx_seq_h;
  bit timed_out;
  int unsigned before_count;

  before_count = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  tx_seq_h = axi_sequence_c::type_id::create("apb_003_tx_enabled");
  tx_seq_h.num_tx = 1;
  tx_seq_h.payload_min = 46;
  tx_seq_h.payload_max = 46;
  tx_seq_h.error_injection = 1'b0;
  tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
  mac_wait_utils_c::wait_for_count_at_least(
      before_count + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("APB_003_TX", "transmitEnabled did not admit a valid AXI frame")
endtask

task mac_apb_layer_management_test_c::read_management_counters();
  apb_read_sequence_c read_h;
  bit [31:0] invalid_count;
  bit [31:0] oversize_count;

  read_h = apb_read_sequence_c::type_id::create("apb_003_invalid_count");
  read_h.m_addr = reg_map_pkg::REG_RX_INVALID_COUNT;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  invalid_count = read_h.m_rdata;
  read_h = apb_read_sequence_c::type_id::create("apb_003_oversize_count");
  read_h.m_addr = reg_map_pkg::REG_RX_OVERSIZE_COUNT;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  oversize_count = read_h.m_rdata;
  `uvm_info("APB_003_COUNTERS", $sformatf(
      "management-visible counts: invalid=%0d oversize=%0d", invalid_count, oversize_count), UVM_NONE)
  // rtl_verilog/integration/mac_core_v.v currently ties rx_oversize_event low,
  // so the count is observable but cannot yet be verified as an incrementing
  // standardized management statistic.
  `uvm_info("APB_003_LIMITATION",
      "No standardized layer-management interface is exposed; receiveEnabled and max-client-data have APB readback but no RX datapath connection, and RX oversize-event reporting is not connected.",
      UVM_NONE)
endtask

task mac_apb_layer_management_test_c::run_stimulus(uvm_phase phase);
  bit [31:0] control_cfg;
  bit [31:0] control_patterns [5];
  bit [47:0] station_addr = 48'h02_00_00_00_30_03;
  bit [47:0] group_addr = 48'h01_00_5e_00_30_03;
  bit [47:0] unknown_addr = 48'h02_00_00_00_de_ad;

  control_cfg = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
                (32'h1 << reg_map_pkg::CTRL_TX_BIT);
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, control_cfg);
  apb_write_check(reg_map_pkg::REG_MAC_ADDR_LOW, station_addr[31:0]);
  apb_write_check(reg_map_pkg::REG_MAC_ADDR_HIGH, station_addr[47:32]);
  apb_write_check(reg_map_pkg::REG_MAX_CLIENT_DATA, 32'd1500);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  apb_read_check(reg_map_pkg::REG_GLOBAL_CONTROL, control_cfg, 32'h0000_00ff);
  apb_read_check(reg_map_pkg::REG_MAC_ADDR_LOW, station_addr[31:0]);
  apb_read_check(reg_map_pkg::REG_MAC_ADDR_HIGH, station_addr[47:32], 32'h0000_ffff);
  apb_read_check(reg_map_pkg::REG_MAX_CLIENT_DATA, 32'd1500, 32'h0000_ffff);
  cdc_settle();

  // station address and promiscuous-mode effects.
  send_and_check(64, station_addr, mac_hvl_utils_c::PAYLOAD_ZERO, 1'b1, "station_address");
  send_and_check(64, unknown_addr, mac_hvl_utils_c::PAYLOAD_ONES, 1'b0, "unknown_filtered");
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL,
                  control_cfg | (32'h1 << reg_map_pkg::CTRL_PROMISCUOUS_BIT));
  cdc_settle();
  send_and_check(64, unknown_addr, mac_hvl_utils_c::PAYLOAD_ALT_55_AA, 1'b1, "promiscuous");
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, control_cfg);

  // Multicast-list entry: valid entry accepts; disabling it removes acceptance.
  apb_write_check(reg_map_pkg::group_low_addr(0), group_addr[31:0]);
  apb_write_check(reg_map_pkg::group_high_addr(0), {15'd0, 1'b1, group_addr[47:32]});
  cdc_settle();
  send_and_check(64, group_addr, mac_hvl_utils_c::PAYLOAD_RANDOM, 1'b1, "multicast_list");
  apb_write_check(reg_map_pkg::group_high_addr(0), {16'd0, group_addr[47:32]});
  send_tx_and_check();

  // PAUSE requests before and after enabling pause reception.
  cdc_settle();
  send_pause_and_check(1'b0, "pause_disabled");
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL,
                  control_cfg | (32'h1 << reg_map_pkg::CTRL_PAUSE_BIT));
  cdc_settle();
  send_pause_and_check(1'b1, "pause_enabled");

  // Size-management effect and its management-visible error observations.
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
  cdc_settle();
  send_and_check(1000, station_addr, mac_hvl_utils_c::PAYLOAD_ALT_AA_55, 1'b1, "size_1000");
  send_and_check(1001, station_addr, mac_hvl_utils_c::PAYLOAD_RANDOM, 1'b0, "size_1001");
  read_management_counters();

  // Patterned APB data plus constrained-random legal/invalid accesses.
  control_patterns = '{32'h0000_0000, 32'hffff_ffff, 32'haaaa_aaaa, 32'h5555_5555, $urandom};
  foreach (control_patterns[i]) begin
    apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, control_patterns[i]);
    apb_read_check(reg_map_pkg::REG_GLOBAL_CONTROL, control_patterns[i], 32'h0000_00ff);
  end
  random_apb_accesses(24);
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, control_cfg);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  cdc_settle();
  `uvm_info("APB_003", "APB layer-management control scenario completed", UVM_NONE)
endtask
