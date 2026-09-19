// MAC-APB-006: supported policy values, reserved fields, and capability report.
class mac_apb_capability_test_c extends mac_apb_config_cdc_test_c;
  `uvm_component_utils(mac_apb_capability_test_c)
  extern function new(string name = "mac_apb_capability_test_c", uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_apb_capability_test_c::new(
    string name = "mac_apb_capability_test_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

task mac_apb_capability_test_c::run_stimulus(uvm_phase phase);
  bit [15:0] policies [3] = '{16'd1518, 16'd1522, 16'd2000};
  foreach (policies[i]) begin
    apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, policies[i]);
    apb_read_check(reg_map_pkg::REG_MAX_FRAME_SIZE, policies[i], 32'h0000_ffff);
  end
  apb_write_check(reg_map_pkg::REG_MAC_SPEED_CONFIG, 32'hffff_fff8);
  apb_read_check(reg_map_pkg::REG_MAC_SPEED_CONFIG, 32'h0000_0008, 32'h0000_000f);
  apb_read_check(reg_map_pkg::REG_FRAME_SIZE_STATUS, '0, '0);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 16'd1518);
  cdc_settle();
  `uvm_info("APB_006_LIMITATION",
      "APB provides implementation-specific policy registers; Clause 30/45 standardized layer management is not exposed.",
      UVM_NONE)
endtask
