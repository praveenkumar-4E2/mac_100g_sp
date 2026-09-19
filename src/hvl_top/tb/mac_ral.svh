// Project-owned UVM RAL model for the MAC APB register boundary.  It models
// the published address map; register semantics remain the DUT's contract.
class mac_apb_reg_adapter_c extends uvm_reg_adapter;
  `uvm_object_utils(mac_apb_reg_adapter_c)
  extern function new(string name = "mac_apb_reg_adapter_c");
  extern virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
  extern virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
endclass

function mac_apb_reg_adapter_c::new(string name = "mac_apb_reg_adapter_c");
  super.new(name);
  provides_responses   = 1;
  supports_byte_enable = 0;
endfunction

function uvm_sequence_item mac_apb_reg_adapter_c::reg2bus(const ref uvm_reg_bus_op rw);
  apb_transfer_t request_h;
  request_h = apb_transfer_t::type_id::create("ral_apb_request");
  request_h.pwrite = (rw.kind == UVM_WRITE);
  request_h.addr = rw.addr[apb_transfer_t::ADDR_WIDTH-1:0];
  request_h.wdata = rw.data[apb_transfer_t::DATA_WIDTH-1:0];
  request_h.expect_slverr = 0;
  return request_h;
endfunction

function void mac_apb_reg_adapter_c::bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
  apb_transfer_t response_h;
  if (!$cast(response_h, bus_item)) begin
    rw.status = UVM_NOT_OK;
    `uvm_error("MAC_RAL_ADAPTER", $sformatf("Expected apb_transfer_t, got %s",
                                            bus_item.get_type_name()))
    return;
  end
  rw.kind   = response_h.pwrite ? UVM_WRITE : UVM_READ;
  rw.addr   = response_h.addr;
  rw.data   = response_h.pwrite ? response_h.wdata : response_h.rdata;
  rw.status = (response_h.status == APB_OK) ? UVM_IS_OK : UVM_NOT_OK;
endfunction

class mac_ral_reg_c extends uvm_reg;
  `uvm_object_utils(mac_ral_reg_c)
  uvm_reg_field  value;
  string         access_policy = "RW";
  uvm_reg_data_t reset_value   = '0;
  bit            is_volatile   = 0;
  extern function new(string name = "mac_ral_reg_c");
  extern function void configure_metadata(string access, uvm_reg_data_t reset = '0,
                                          bit volatile_value = 0);
  extern virtual function void build();
endclass

function mac_ral_reg_c::new(string name = "mac_ral_reg_c");
  super.new(name, 32, UVM_NO_COVERAGE);
endfunction

function void mac_ral_reg_c::configure_metadata(string access, uvm_reg_data_t reset = '0,
                                                bit volatile_value = 0);
  access_policy = access;
  reset_value   = reset;
  is_volatile   = volatile_value;
endfunction

function void mac_ral_reg_c::build();
  value = uvm_reg_field::type_id::create("value");
  value.configure(this, 32, 0, access_policy, is_volatile, reset_value, 1, 1, 1);
endfunction

class mac_ral_block_c extends uvm_reg_block;
  `uvm_object_utils(mac_ral_block_c)
  mac_ral_reg_c registers[string];

  extern function new(string name = "mac_ral_block_c");
  extern virtual function void build();
  extern function mac_ral_reg_c add_register(string name, uvm_reg_addr_t address,
                                             string access = "RW", uvm_reg_data_t reset = '0,
                                             bit volatile_value = 0);
endclass

function mac_ral_block_c::new(string name = "mac_ral_block_c");
  super.new(name, UVM_NO_COVERAGE);
endfunction

function mac_ral_reg_c mac_ral_block_c::add_register(
    string name, uvm_reg_addr_t address, string access = "RW", uvm_reg_data_t reset = '0,
    bit volatile_value = 0);
  mac_ral_reg_c reg_h;
  string map_access;
  reg_h = mac_ral_reg_c::type_id::create(name);
  reg_h.configure_metadata(access, reset, volatile_value);
  reg_h.build();
  reg_h.configure(this);
  // UVM 1.1d map rights are limited to RO/RW/WO even though a field may use
  // richer policies such as W1C. Keep the behavioral policy at field level
  // and expose W1C registers as writable through the transport map.
  map_access = (access == "W1C") ? "RW" : access;
  default_map.add_reg(reg_h, address, map_access);
  registers[name] = reg_h;
  return reg_h;
endfunction

function void mac_ral_block_c::build();
  default_map = create_map("apb_map", '0, 4, UVM_LITTLE_ENDIAN, 1);
  void'(add_register("version", reg_map_pkg::REG_VERSION, "RO", 32'h4150_4231));
  void'(add_register("global_control", reg_map_pkg::REG_GLOBAL_CONTROL, "RW", 32'h0000_0040));
  void'(add_register("mac_addr_low", reg_map_pkg::REG_MAC_ADDR_LOW));
  void'(add_register("mac_addr_high", reg_map_pkg::REG_MAC_ADDR_HIGH));
  void'(add_register("max_client_data", reg_map_pkg::REG_MAX_CLIENT_DATA, "RW", 32'd1500));
  void'(add_register("oversize_control", reg_map_pkg::REG_OVERSIZE_CONTROL, "RO", 32'h40));
  void'(add_register("pause_control", reg_map_pkg::REG_PAUSE_CONTROL, "RO"));
  void'(add_register("pause_status", reg_map_pkg::REG_PAUSE_STATUS, "RO", '0, 1));
  void'(add_register("rx_status", reg_map_pkg::REG_RX_STATUS, "RO", '0, 1));
  void'(add_register("tx_status", reg_map_pkg::REG_TX_STATUS, "RO", '0, 1));
  void'(add_register("interrupt_enable", reg_map_pkg::REG_INTERRUPT_ENABLE));
  void'(add_register("interrupt_status", reg_map_pkg::REG_INTERRUPT_STATUS, "W1C", '0, 1));
  void'(add_register("rx_invalid_count", reg_map_pkg::REG_RX_INVALID_COUNT, "RO", '0, 1));
  void'(add_register("rx_oversize_count", reg_map_pkg::REG_RX_OVERSIZE_COUNT, "RO", '0, 1));
  void'(add_register("rx_unsupported_count", reg_map_pkg::REG_RX_UNSUPPORTED_COUNT, "RO", '0, 1));
  void'(add_register("pause_tx_config", reg_map_pkg::REG_PAUSE_TX_CONFIG));
  void'(add_register("mac_speed_config", reg_map_pkg::REG_MAC_SPEED_CONFIG, "RW", 32'h0000_0004));
  void'(add_register("max_frame_size", reg_map_pkg::REG_MAX_FRAME_SIZE, "RW", 32'd1518));
  void'(add_register("min_frame_size", reg_map_pkg::REG_MIN_FRAME_SIZE, "RW", 32'd64));
  void'(add_register("frame_size_status", reg_map_pkg::REG_FRAME_SIZE_STATUS, "RO", '0, 1));
  for (int unsigned i = 0; i < 4; i++) begin
    void'(add_register($sformatf("group%0d_low", i), reg_map_pkg::group_low_addr(i)));
    void'(add_register($sformatf("group%0d_high", i), reg_map_pkg::group_high_addr(i)));
  end
  lock_model();
endfunction
