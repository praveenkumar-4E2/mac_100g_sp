// MAC-APB-004: frame-limit, alias, and complete group-table management.
class mac_apb_limits_groups_test_c extends mac_apb_config_cdc_test_c;
  `uvm_component_utils(mac_apb_limits_groups_test_c)

  extern function new(string name = "mac_apb_limits_groups_test_c",
                      uvm_component parent = null);
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_apb_limits_groups_test_c::new(
    string name = "mac_apb_limits_groups_test_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

task mac_apb_limits_groups_test_c::run_stimulus(uvm_phase phase);
  bit [31:0] ctrl;
  bit [47:0] group_addr;

  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_OVERSIZE_BIT);
  apb_write_check(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_read_check(reg_map_pkg::REG_OVERSIZE_CONTROL,
                 (32'h1 << reg_map_pkg::CTRL_OVERSIZE_BIT), 32'h0000_0040);
  apb_read_check(reg_map_pkg::REG_PAUSE_CONTROL, ctrl, 32'h0000_0030);

  // Raised minimum boundary: 127 drops and 128 is delivered.  The standard
  // 64-octet boundary is exercised by APB-002.
  apb_write_check(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd128);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  cdc_settle();
  send_and_check(127, 48'hff_ff_ff_ff_ff_ff, mac_hvl_utils_c::PAYLOAD_ZERO, 1'b0,
                 "raised_minimum_127");
  send_and_check(128, 48'hff_ff_ff_ff_ff_ff, mac_hvl_utils_c::PAYLOAD_ONES, 1'b1,
                 "raised_minimum_128");

  // Program and functionally prove every address-filter entry, then disable
  // it and prove the same DA is rejected.
  for (int unsigned index = 0; index < 4; index++) begin
    group_addr = 48'h01_00_5e_10_00_00 + index;
    apb_write_check(reg_map_pkg::group_low_addr(index), group_addr[31:0]);
    apb_write_check(reg_map_pkg::group_high_addr(index), {15'd0, 1'b1, group_addr[47:32]});
    apb_read_check(reg_map_pkg::group_low_addr(index), group_addr[31:0]);
    apb_read_check(reg_map_pkg::group_high_addr(index), {15'd0, 1'b1, group_addr[47:32]},
                   32'h0001_ffff);
  end
  cdc_settle();
  for (int unsigned index = 0; index < 4; index++) begin
    group_addr = 48'h01_00_5e_10_00_00 + index;
    send_and_check(128, group_addr, mac_hvl_utils_c::PAYLOAD_RANDOM, 1'b1,
                   $sformatf("group_%0d_enabled", index));
    apb_write_check(reg_map_pkg::group_high_addr(index), {16'd0, group_addr[47:32]});
    cdc_settle();
    send_and_check(128, group_addr, mac_hvl_utils_c::PAYLOAD_ALT_55_AA, 1'b0,
                   $sformatf("group_%0d_disabled", index));
  end
  apb_write_check(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  cdc_settle();
  `uvm_info("APB_004", "Minimum-size, alias, and four-entry group-table scenario completed",
            UVM_NONE)
endtask
