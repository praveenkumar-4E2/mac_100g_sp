`ifndef MAC_REGISTER_ACCESS_TEST_SVH
`define MAC_REGISTER_ACCESS_TEST_SVH

// APB register-access and semantic readback test.  It first verifies every
// legal map location, then checks the configuration registers that have
// architectural readback.  Status/counter values are intentionally not
// forced: they are dynamic DUT observations, not software-owned storage.
class mac_register_access_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_register_access_test_c)

  extern function new(string name = "mac_register_access_test_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr, bit expect_slverr = 1'b0);
  extern task apb_read_expect(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                              bit [apb_transfer_t::DATA_WIDTH-1:0] expected,
                              bit [apb_transfer_t::DATA_WIDTH-1:0] mask = '1);
endclass

function mac_register_access_test_c::new(string name = "mac_register_access_test_c",
                                         uvm_component parent = null);
  super.new(name, parent);
endfunction

function void mac_register_access_test_c::configure_test();
  super.configure_test();
  // The APB agent's monitor-only checker has no expected-error sideband;
  // retain normal protocol checking for this legal-address access sweep.
endfunction

task mac_register_access_test_c::apb_write(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                           input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create($sformatf("reg_wr_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_wdata = data;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_register_access_test_c::apb_read(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                          input bit expect_slverr = 1'b0);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("reg_rd_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_register_access_test_c::apb_read_expect(
    input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
    input bit [apb_transfer_t::DATA_WIDTH-1:0] expected,
    input bit [apb_transfer_t::DATA_WIDTH-1:0] mask = '1);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("reg_rd_check_%h", addr));
  seq_h.m_addr = addr;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  if ((seq_h.m_rdata & mask) !== (expected & mask))
    `uvm_error("MAC_RAL_READBACK", $sformatf(
               "APB readback mismatch addr=%h got=%h expected=%h mask=%h",
               addr,
               seq_h.m_rdata,
               expected,
               mask
               ))
endtask

task mac_register_access_test_c::run_stimulus(uvm_phase phase);
  uvm_status_e ral_status;
  uvm_reg_data_t ral_data;
  bit [15:0] fixed_addrs[$] = '{
      reg_map_pkg::REG_VERSION,
      reg_map_pkg::REG_GLOBAL_CONTROL,
      reg_map_pkg::REG_MAC_ADDR_LOW,
      reg_map_pkg::REG_MAC_ADDR_HIGH,
      reg_map_pkg::REG_MAX_CLIENT_DATA,
      reg_map_pkg::REG_OVERSIZE_CONTROL,
      reg_map_pkg::REG_PAUSE_CONTROL,
      reg_map_pkg::REG_PAUSE_STATUS,
      reg_map_pkg::REG_RX_STATUS,
      reg_map_pkg::REG_TX_STATUS,
      reg_map_pkg::REG_INTERRUPT_ENABLE,
      reg_map_pkg::REG_INTERRUPT_STATUS,
      reg_map_pkg::REG_RX_INVALID_COUNT,
      reg_map_pkg::REG_RX_OVERSIZE_COUNT,
      reg_map_pkg::REG_RX_UNSUPPORTED_COUNT,
      reg_map_pkg::REG_PAUSE_TX_CONFIG,
      reg_map_pkg::REG_MAC_SPEED_CONFIG,
      reg_map_pkg::REG_MAX_FRAME_SIZE,
      reg_map_pkg::REG_MIN_FRAME_SIZE,
      reg_map_pkg::REG_FRAME_SIZE_STATUS
  };

  foreach (fixed_addrs[i]) begin
    apb_write(fixed_addrs[i], 32'h0000_0000);
    apb_read(fixed_addrs[i]);
  end
  for (int unsigned i = 0; i < 4; i++) begin
    apb_write(reg_map_pkg::group_low_addr(i), 32'h1122_0000 + i);
    apb_write(reg_map_pkg::group_high_addr(i), 32'h0001_0000 + i);
    apb_read(reg_map_pkg::group_low_addr(i));
    apb_read(reg_map_pkg::group_high_addr(i));
  end

  // Immutable identification register and reset-visible configuration.
  apb_read_expect(reg_map_pkg::REG_VERSION, 32'h4150_4231);
  // Confirm the RAL frontdoor is bound to the MAC APB sequencer, rather than
  // merely constructing an address map that no test can execute.
  ral_h.registers["version"].read(ral_status, ral_data, UVM_FRONTDOOR, ral_h.default_map);
  if (ral_status != UVM_IS_OK || ral_data != 32'h4150_4231)
    `uvm_error("MAC_RAL_FRONTDOOR", $sformatf(
               "RAL version read failed status=%s data=%h", ral_status.name(), ral_data))

  // Architecturally writable configuration registers.  Check only defined
  // fields where the implementation deliberately reserves upper bits.
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_00D5);
  apb_read_expect(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_00D5);
  apb_read_expect(reg_map_pkg::REG_OVERSIZE_CONTROL, 32'h0000_0040, 32'h0000_0040);
  apb_read_expect(reg_map_pkg::REG_PAUSE_CONTROL, 32'h0000_0010, 32'h0000_0030);

  apb_write(reg_map_pkg::REG_MAC_ADDR_LOW, 32'h89AB_CDEF);
  apb_write(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h0000_4567);
  apb_read_expect(reg_map_pkg::REG_MAC_ADDR_LOW, 32'h89AB_CDEF);
  apb_read_expect(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h0000_4567, 32'h0000_FFFF);

  apb_write(reg_map_pkg::REG_MAX_CLIENT_DATA, 32'h0000_05DC);
  apb_read_expect(reg_map_pkg::REG_MAX_CLIENT_DATA, 32'h0000_05DC, 32'h0000_FFFF);
  apb_write(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'h0000_0600);
  apb_read_expect(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'h0000_0600, 32'h0000_FFFF);
  apb_write(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'h0000_0040);
  apb_read_expect(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'h0000_0040, 32'h0000_FFFF);

  // Bits [2:0] are programmed speed and bit [3] enables the override; the
  // effective-speed field [6:4] crosses into the TX clock domain, so the
  // test does not impose an unsafe same-cycle expectation on that field.
  apb_write(reg_map_pkg::REG_MAC_SPEED_CONFIG, 32'h0000_000C);
  apb_read_expect(reg_map_pkg::REG_MAC_SPEED_CONFIG, 32'h0000_000C, 32'h0000_000F);

  // PAUSE configuration reads back through the dedicated control register.
  // Keep SOFT_REQ clear in this register-only test; a set request correctly
  // creates a DUT PAUSE frame and belongs to mac_pause_tx_test_c.
  apb_write(reg_map_pkg::REG_PAUSE_TX_CONFIG, 32'h0000_0121);
  apb_read_expect(reg_map_pkg::REG_PAUSE_TX_CONFIG, 32'h0000_0121, 32'h0000_FFFF);

  for (int unsigned i = 0; i < 4; i++) begin
    apb_write(reg_map_pkg::group_low_addr(i), 32'hA5A5_0000 + i);
    apb_write(reg_map_pkg::group_high_addr(i), 32'h0001_0000 + i);
    apb_read_expect(reg_map_pkg::group_low_addr(i), 32'hA5A5_0000 + i);
    apb_read_expect(reg_map_pkg::group_high_addr(i), 32'h0001_0000 + i, 32'h0001_FFFF);
  end
  `uvm_info("MAC_RAL_ACCESS", "PASS: legal APB map sweep completed", UVM_NONE)
endtask

`endif  // MAC_REGISTER_ACCESS_TEST_SVH
