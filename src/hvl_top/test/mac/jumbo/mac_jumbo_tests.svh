`ifndef MAC_JUMBO_TESTS_SVH
`define MAC_JUMBO_TESTS_SVH

// End-to-end profile test.  The same test class is specialized below for the
// 9,000-octet jumbo and 16,384-octet super-jumbo frame limits.
class mac_large_axi_sequence_c extends axi_sequence_base_c;
  `uvm_object_utils(mac_large_axi_sequence_c)
  function new(string name = "mac_large_axi_sequence_c"); super.new(name); endfunction
  task body();
    resolve_config();
    send_clean_item(payload_min, 48'hff_ffff_ffff_ff, 1'b0);
  endtask
endclass

class mac_large_rs_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_large_rs_sequence_c)
  function new(string name = "mac_large_rs_sequence_c"); super.new(name); endfunction
  task body();
    resolve_config();
    send_clean_frame(payload_min, 48'hff_ffff_ffff_ff, 1'b1);
  endtask
endclass

class mac_large_frame_test_base_c extends mac_base_test_c;
  int unsigned frame_octets;
  int unsigned payload_octets;

  extern function new(string name = "mac_large_frame_test_base_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
  extern task write_max_frame_size();
endclass

function mac_large_frame_test_base_c::new(string name = "mac_large_frame_test_base_c",
                                           uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents = 1;
  num_axi_passive_agents = 1;
  num_rs_active_agents = 1;
  num_rs_passive_agents = 1;
endfunction

function void mac_large_frame_test_base_c::configure_test();
  super.configure_test();
  env_cfg_h.max_frame_octets = frame_octets;
  env_cfg_h.max_payload_bytes = payload_octets;
  env_cfg_h.axi_active_agent_cfgs[0].max_payload_len = payload_octets;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = payload_octets;
endfunction

task mac_large_frame_test_base_c::write_max_frame_size();
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create("large_frame_max_size_write");
  seq_h.m_addr = reg_map_pkg::REG_MAX_FRAME_SIZE;
  seq_h.m_wdata = frame_octets;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  #100ns;  // APB-to-MAC clock-domain configuration bridge
endtask

task mac_large_frame_test_base_c::run_stimulus(uvm_phase phase);
  mac_large_axi_sequence_c tx_seq_h;
  mac_large_rs_sequence_c rx_seq_h;
  bit tx_timed_out;
  bit rx_timed_out;

  write_max_frame_size();
  tx_seq_h = mac_large_axi_sequence_c::type_id::create("large_frame_tx_seq");
  tx_seq_h.error_injection = 0;
  tx_seq_h.num_tx = 1;
  tx_seq_h.payload_min = payload_octets;
  tx_seq_h.payload_max = payload_octets;
  tx_seq_h.num_tx.rand_mode(0);
  tx_seq_h.payload_min.rand_mode(0);
  tx_seq_h.payload_max.rand_mode(0);
  tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
  mac_wait_utils_c::wait_for_count_at_least(
      1, env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      mac_tx_vif, MAC_COMPLETION_TIMEOUT_NS, tx_timed_out);

  rx_seq_h = mac_large_rs_sequence_c::type_id::create("large_frame_rx_seq");
  rx_seq_h.error_injection = 0;
  rx_seq_h.broadcast_da = 1;
  rx_seq_h.num_frames = 1;
  rx_seq_h.payload_min = payload_octets;
  rx_seq_h.payload_max = payload_octets;
  rx_seq_h.num_frames.rand_mode(0);
  rx_seq_h.payload_min.rand_mode(0);
  rx_seq_h.payload_max.rand_mode(0);
  rx_seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  mac_wait_utils_c::wait_for_axi_count_at_least(
      1, env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
      axi_rx_vif, MAC_COMPLETION_TIMEOUT_NS, rx_timed_out);

  if (tx_timed_out || rx_timed_out)
    `uvm_error(get_type_name(), $sformatf("%0d-octet frame completion timed out: tx=%0b rx=%0b",
                                          frame_octets, tx_timed_out, rx_timed_out))
  else
    `uvm_info(get_type_name(), $sformatf("PASS: %0d-octet frame profile completed in TX and RX",
                                         frame_octets), UVM_NONE)
endtask

class mac_jumbo_frame_test_c extends mac_large_frame_test_base_c;
  `uvm_component_utils(mac_jumbo_frame_test_c)
  function new(string name = "mac_jumbo_frame_test_c", uvm_component parent = null);
    super.new(name, parent);
    frame_octets = MAC_JUMBO_FRAME_OCTETS;
    payload_octets = MAC_JUMBO_FRAME_OCTETS - RS_HDR_BYTES - RS_FCS_BYTES;
  endfunction
endclass

class mac_super_jumbo_frame_test_c extends mac_large_frame_test_base_c;
  `uvm_component_utils(mac_super_jumbo_frame_test_c)
  function new(string name = "mac_super_jumbo_frame_test_c", uvm_component parent = null);
    super.new(name, parent);
    frame_octets = MAC_SUPER_JUMBO_FRAME_OCTETS;
    payload_octets = MAC_SUPER_JUMBO_PAYLOAD_BYTES;
  endfunction
endclass

`endif
