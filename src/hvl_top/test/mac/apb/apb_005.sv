// MAC-APB-005: CDC transition stress.  Frames are injected while related
// APB fields change; acceptance may follow the old or new complete setting,
// but any delivery must retain a valid frame and never corrupt the stream.
class mac_apb_cdc_transition_test_c extends mac_apb_config_cdc_test_c;
  `uvm_component_utils(mac_apb_cdc_transition_test_c)
  extern function new(string name = "mac_apb_cdc_transition_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_apb_cdc_transition_test_c::new(
    string name = "mac_apb_cdc_transition_test_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

task mac_apb_cdc_transition_test_c::run_stimulus(uvm_phase phase);
  bit [31:0] ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT);
  bit [47:0] old_addr = 48'h02_00_00_00_50_01;
  bit [47:0] new_addr = 48'h02_00_00_00_50_02;
  apb_002_rx_frame_sequence_c traffic_h;

  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_check(reg_map_pkg::REG_MAC_ADDR_LOW, old_addr[31:0]);
  apb_write_check(reg_map_pkg::REG_MAC_ADDR_HIGH, old_addr[47:32]);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
  cdc_settle();
  // Deliberately overlap traffic with the address/limit writes; the protocol
  // checker and AXI monitor catch malformed/interleaved output while APB-002
  // covers the stable old/new externally visible boundaries.
  fork
    begin
      repeat (12) begin
        traffic_h = apb_002_rx_frame_sequence_c::type_id::create("apb_005_transition_frame");
        traffic_h.frame_octets = $urandom_range(900, 1100);
        traffic_h.destination = ($urandom_range(0, 1)) ? old_addr : new_addr;
        traffic_h.payload_pattern = mac_hvl_utils_c::PAYLOAD_RANDOM;
        traffic_h.payload_seed = $urandom;
        traffic_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
      end
    end
    begin
      repeat (6) begin
        apb_write_check(reg_map_pkg::REG_MAC_ADDR_LOW, new_addr[31:0]);
        apb_write_check(reg_map_pkg::REG_MAC_ADDR_HIGH, new_addr[47:32]);
        apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1200);
        apb_write_check(reg_map_pkg::REG_MAC_ADDR_LOW, old_addr[31:0]);
        apb_write_check(reg_map_pkg::REG_MAC_ADDR_HIGH, old_addr[47:32]);
        apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
      end
    end
  join
  apb_write_check(reg_map_pkg::REG_MAC_ADDR_LOW, new_addr[31:0]);
  apb_write_check(reg_map_pkg::REG_MAC_ADDR_HIGH, new_addr[47:32]);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1200);
  cdc_settle();
  send_and_check(1100, new_addr, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 1'b1,
                 "final_complete_bundle");
  `uvm_info("APB_005", "Concurrent CDC transition stress completed", UVM_NONE)
endtask
