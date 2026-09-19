`ifndef MAC_TX_CRC_001_TEST_SV
`define MAC_TX_CRC_001_TEST_SV

// TX_CRC_001 configures and runs the directed AXI CRC/FCS sequence.
class mac_tx_crc_001_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_tx_crc_001_test_c)

  localparam int unsigned TX_CRC_001_FRAME_COUNT = 20;
  extern function new(string name = "mac_tx_crc_001_test_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_tx_crc_001_test_c::new(string name = "mac_tx_crc_001_test_c",
                                     uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
endfunction

function void mac_tx_crc_001_test_c::configure_test();
  super.configure_test();
  env_cfg_h.max_payload_bytes = MAC_SUPER_JUMBO_PAYLOAD_BYTES;
  env_cfg_h.max_frame_octets  = MAC_SUPER_JUMBO_FRAME_OCTETS;
  // The sequence intentionally drives a 1-byte payload, while the reference
  // model retains its 46-byte minimum to predict TX zero padding correctly.
  env_cfg_h.has_protocol_checkers = 0;
  // The reference model does not predict monitor-derived error status bits
  // for the intentionally corrupted protected fields.
  env_cfg_h.scoreboard_check_error_flags = 0;
  env_cfg_h.axi_active_agent_cfgs[0].min_payload_len = 1;
  env_cfg_h.axi_active_agent_cfgs[0].max_payload_len = MAC_SUPER_JUMBO_PAYLOAD_BYTES;
endfunction

task mac_tx_crc_001_test_c::run_stimulus(uvm_phase phase);
  mac_tx_crc_001_sequence_c seq_h;
  apb_write_sequence_c cfg_h;
  bit timed_out;

  cfg_h = apb_write_sequence_c::type_id::create("tx_crc_001_max_frame_size");
  cfg_h.m_addr = reg_map_pkg::REG_MAX_FRAME_SIZE;
  cfg_h.m_wdata = MAC_SUPER_JUMBO_FRAME_OCTETS;
  cfg_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  #100ns;

  seq_h = mac_tx_crc_001_sequence_c::type_id::create("tx_crc_001_seq");
  seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
  mac_wait_utils_c::wait_for_count_at_least(
      TX_CRC_001_FRAME_COUNT,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out)
    `uvm_error("TX_CRC_001", "Timed out waiting for the TX CRC/FCS scenario burst")
  else
    `uvm_info("TX_CRC_001", "PASS: all TX CRC/FCS scenarios completed", UVM_NONE)
endtask

`endif  // MAC_TX_CRC_001_TEST_SV
