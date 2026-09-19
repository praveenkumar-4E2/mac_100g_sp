class mac_apb_access_rand_c extends uvm_object;
  `uvm_object_utils(mac_apb_access_rand_c)

  rand bit legal;
  rand bit [15:0] addr;
  rand bit [31:0] data;

  constraint c_addr {
    legal dist {1 := 3, 0 := 1};
    if (legal)
      addr inside {
        reg_map_pkg::REG_GLOBAL_CONTROL,
        reg_map_pkg::REG_MAC_ADDR_LOW,
        reg_map_pkg::REG_MAC_ADDR_HIGH,
        reg_map_pkg::REG_MAX_CLIENT_DATA,
        reg_map_pkg::REG_INTERRUPT_ENABLE,
        reg_map_pkg::REG_MAX_FRAME_SIZE,
        reg_map_pkg::REG_MIN_FRAME_SIZE
      };
    else
      addr inside {16'h0001, 16'h0002, 16'h004e, 16'h00a0, 16'hfffc};
  }

  function new(string name = "mac_apb_access_rand_c");
    super.new(name);
  endfunction
endclass

class mac_interrupt_test_c extends mac_register_access_test_c;
  `uvm_component_utils(mac_interrupt_test_c)

  localparam bit [31:0] INT_INVALID  = 32'h0000_0001;
  localparam bit [31:0] INT_OVERSIZE = 32'h0000_0004;
  localparam bit [31:0] INT_BOTH     = INT_INVALID | INT_OVERSIZE;

  extern function new(string name = "mac_interrupt_test_c", uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
  extern task apb_write_check(input bit [15:0] addr, input bit [31:0] data,
                               input bit expect_slverr = 1'b0);
  extern task apb_read_data(input bit [15:0] addr, output bit [31:0] data,
                            input bit expect_slverr = 1'b0);
  extern task read_status_snapshot(input bit [15:0] addr, output bit [31:0] data);
  extern task check_masked(input string check_name, input bit [31:0] actual,
                           input bit [31:0] expected, input bit [31:0] mask);
  extern task run_random_apb_accesses(input int unsigned count = 40);
endclass

function mac_interrupt_test_c::new(string name = "mac_interrupt_test_c",
                                   uvm_component parent = null);
  super.new(name, parent);
  num_rs_active_agents = 1;
endfunction

function void mac_interrupt_test_c::configure_test();
  super.configure_test();
  // This is a register/status test. Error-injected RX frames intentionally
  // do not have AXI payload expectations, so exclude them from E2E matching.
  env_cfg_h.has_scoreboard = 1'b0;
  // The APB monitor has no expected-error sideband. PSLVERR is checked by
  // apb_write_check/apb_read_data; leave the monitor-only checker permissive
  // for this test's deliberate invalid-address accesses.
  env_cfg_h.apb_active_agent_cfgs[0].m_fail_on_unexpected_slverr = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = 1600;
  env_cfg_h.rs_active_agent_cfgs[0].enable_error_injection = 1'b1;
endfunction

task mac_interrupt_test_c::apb_write_check(
    input bit [15:0] addr, input bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create($sformatf("irq_wr_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_wdata = data;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_interrupt_test_c::apb_read_data(
    input bit [15:0] addr, output bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("irq_rd_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = seq_h.m_rdata;
endtask

task mac_interrupt_test_c::read_status_snapshot(input bit [15:0] addr, output bit [31:0] data);
  bit [31:0] discard;
  apb_read_data(addr, discard);
  #300ns;
  apb_read_data(addr, data);
endtask

task mac_interrupt_test_c::check_masked(input string check_name, input bit [31:0] actual,
                                         input bit [31:0] expected, input bit [31:0] mask);
  if ((actual & mask) !== (expected & mask))
    `uvm_error("IRQ_W1C_CHECK", $sformatf("%s failed: got=%h expected=%h mask=%h",
                                            check_name, actual, expected, mask))
endtask

task mac_interrupt_test_c::run_random_apb_accesses(input int unsigned count = 40);
  mac_apb_access_rand_c item_h;
  item_h = mac_apb_access_rand_c::type_id::create("apb_access_item");
  repeat (count) begin
    bit [31:0] read_data;
    if (!item_h.randomize())
      `uvm_fatal("IRQ_RAND_APB", "APB access randomization failed")
    if ($urandom_range(0, 1))
      apb_write_check(item_h.addr, item_h.data, !item_h.legal);
    else
      apb_read_data(item_h.addr, read_data, !item_h.legal);
  end
endtask

task mac_interrupt_test_c::run_stimulus(uvm_phase phase);
  mac_irq_counter_stim_seq_c rx_stim_h;
  bit [31:0] data;
  bit [31:0] invalid_before;
  bit [31:0] oversize_before;
  bit [31:0] random_pattern;
  bit [31:0] single_masks [4] = '{INT_INVALID, 32'h0000_0002, INT_OVERSIZE, 32'h0000_0008};
  bit [31:0] patterns [5];

  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_0000);
  foreach (single_masks[i]) begin
    apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, single_masks[i]);
    apb_read_data(reg_map_pkg::REG_INTERRUPT_ENABLE, data);
    check_masked("single interrupt-enable readback", data, single_masks[i], 32'hffff_ffff);
  end

  random_pattern = $urandom;
  patterns = '{32'h0000_0000, 32'hffff_ffff, 32'haaaa_aaaa, 32'h5555_5555, random_pattern};
  foreach (patterns[i]) begin
    apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, patterns[i]);
    apb_read_data(reg_map_pkg::REG_INTERRUPT_ENABLE, data);
    check_masked("pattern interrupt-enable readback", data, patterns[i], 32'hffff_ffff);
  end

  apb_write_check(reg_map_pkg::REG_INTERRUPT_ENABLE, INT_BOTH);
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, invalid_before);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, oversize_before);
  apb_write_check(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  #300ns;

  rx_stim_h = mac_irq_counter_stim_seq_c::type_id::create("invalid_irq_stim_h");
  rx_stim_h.stimulus_kind = mac_irq_counter_stim_seq_c::INVALID_LENGTH;
  rx_stim_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  rx_stim_h = mac_irq_counter_stim_seq_c::type_id::create("oversize_irq_stim_h");
  rx_stim_h.stimulus_kind = mac_irq_counter_stim_seq_c::OVERSIZE;
  rx_stim_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("two interrupt sources set", data, INT_BOTH, INT_BOTH);
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, INT_INVALID);
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("single-bit W1C", data, INT_OVERSIZE, INT_BOTH);

  rx_stim_h = mac_irq_counter_stim_seq_c::type_id::create("invalid_irq_stim_reassert_h");
  rx_stim_h.stimulus_kind = mac_irq_counter_stim_seq_c::INVALID_LENGTH;
  rx_stim_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;
  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, INT_BOTH);
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("multi-bit W1C", data, 32'h0000_0000, INT_BOTH);

  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, data);
  check_masked("RX-invalid counter increment", data, invalid_before + 32'd2, 32'hffff_ffff);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, data);
  check_masked("RX-oversize counter increment", data, oversize_before + 32'd1, 32'hffff_ffff);

  apb_write_check(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0000);
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, data);
  check_masked("RX-invalid zero write", data, invalid_before + 32'd2, 32'hffff_ffff);
  apb_write_check(reg_map_pkg::REG_RX_INVALID_COUNT, 32'h0000_0001);
  apb_write_check(reg_map_pkg::REG_RX_OVERSIZE_COUNT, 32'h0000_0001);
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_RX_INVALID_COUNT, data);
  check_masked("RX-invalid W1C clear", data, 32'h0000_0000, 32'hffff_ffff);
  read_status_snapshot(reg_map_pkg::REG_RX_OVERSIZE_COUNT, data);
  check_masked("RX-oversize W1C clear", data, 32'h0000_0000, 32'hffff_ffff);

  apb_write_check(reg_map_pkg::REG_INTERRUPT_STATUS, 32'hffff_ff80);
  #300ns;
  read_status_snapshot(reg_map_pkg::REG_INTERRUPT_STATUS, data);
  check_masked("reserved interrupt-status bits", data, 32'h0000_0000, 32'h0000_007f);
  apb_write_check(16'h0002, 32'ha5a5_a5a5, 1'b1);
  apb_write_check(16'h00a0, 32'hffff_ffff, 1'b1);
  apb_read_data(16'h0001, data, 1'b1);
  apb_read_data(16'hfffc, data, 1'b1);
  run_random_apb_accesses(40);

  `uvm_info("IRQ_W1C_TEST", "Interrupt-enable, W1C, counter, and APB-random test completed",
            UVM_NONE)
endtask
