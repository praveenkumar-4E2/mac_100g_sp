class mac_rx_crc_002_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_rx_crc_002_test_c)


  extern function new(string name = "mac_rx_crc_002_test_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern task run_stimulus(uvm_phase phase);
endclass

function mac_rx_crc_002_test_c::new(string name = "mac_rx_crc_002_test_c",
                                    uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
endfunction


function void mac_rx_crc_002_test_c::configure_test();
  super.configure_test();
  env_cfg_h.max_payload_bytes = MAC_SUPER_JUMBO_PAYLOAD_BYTES;
  env_cfg_h.max_frame_octets = MAC_SUPER_JUMBO_FRAME_OCTETS;

  env_cfg_h.has_protocol_checkers = 1;
  env_cfg_h.scoreboard_check_error_flags = 1;
  env_cfg_h.rs_active_agent_cfgs[0].min_payload_len = 1;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = MAC_SUPER_JUMBO_PAYLOAD_BYTES;
endfunction

task mac_rx_crc_002_test_c::run_stimulus(uvm_phase phase);
  mac_rx_crc_sequence_c seq_h;
  apb_write_sequence_c cfg_h;
  bit timed_out;

  cfg_h = apb_write_sequence_c::type_id::create("rx_crc_002_mac_frame_size");
  cfg_h.m_addr = reg_map_pkg::REG_MAX_FRAME_SIZE;
  cfg_h.m_wdata = MAC_SUPER_JUMBO_FRAME_OCTETS;
  cfg_h.start(env_h.virtual_sequencer_h.apb_seqr_h);

  #100ns;

  seq_h = mac_rx_crc_sequence_c::type_id::create("rx_crc_002_seq");
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  mac_wait_utils_c::wait_for_count_at_least(
      seq_h.expected_rx_frames,
      env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt, mac_rx_vif,
      MAC_COMPLETION_TIMEOUT_NS, timed_out);

  if (timed_out) `uvm_error("RX_CRC_002", "Timed out waiting for the RX CRC/FCS scenario burst")
  else `uvm_info("RX_CRC_002", "PASS: all RX CRC/FCS scenarios completed", UVM_NONE)
endtask
