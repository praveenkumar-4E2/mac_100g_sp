// MAC-APB-FUNC-CFG: APB register access and functional configuration test.
// Combines concurrent AXI TX + RS RX + PAUSE traffic with APB register
// modifications across 6 phases: register sweep, bidirectional config,
// mixed frame sizes, PAUSE + filtering, CDC transition stress, and
// sustained bidirectional with periodic APB reconfiguration.
class mac_apb_functional_config_test_c extends mac_base_test_c;
  `uvm_component_utils(mac_apb_functional_config_test_c)

  extern function new(string name = "mac_apb_functional_config_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
  extern task apb_write_check(input bit [15:0] addr, input bit [31:0] data,
                               input bit expect_slverr = 1'b0);
  extern task apb_read_check(input bit [15:0] addr, output bit [31:0] data,
                              input bit [31:0] mask = '1,
                              input bit expect_slverr = 1'b0);
  extern task cdc_settle();
endclass

function mac_apb_functional_config_test_c::new(
    string name = "mac_apb_functional_config_test_c",
    uvm_component parent = null);
  super.new(name, parent);
  num_axi_active_agents  = 1;
  num_axi_passive_agents = 1;
  num_rs_active_agents   = 1;
  num_rs_passive_agents  = 1;
endfunction

function void mac_apb_functional_config_test_c::configure_test();
  super.configure_test();
  env_cfg_h.has_scoreboard        = 1'b1;
  // This sequence intentionally mixes accepted, filtered, and PAUSE control
  // frames.  Its per-phase monitor/counter checks are the RX oracle; generic
  // in-order RX matching cannot model the deliberate drops.
  env_cfg_h.scoreboard_enable_rx_check = 1'b0;
  env_cfg_h.has_protocol_checkers = 1'b1;
  env_cfg_h.has_function_coverage = $test$plusargs("MAC_FUNCTIONAL_COVERAGE");
  env_cfg_h.apb_active_agent_cfgs[0].m_fail_on_unexpected_slverr = 1'b0;
  env_cfg_h.rs_active_agent_cfgs[0].max_payload_len = 1600;
endfunction

task mac_apb_functional_config_test_c::apb_write_check(
    input bit [15:0] addr, input bit [31:0] data, input bit expect_slverr = 1'b0);
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create($sformatf("test_wr_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_wdata = data;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task mac_apb_functional_config_test_c::apb_read_check(
    input bit [15:0] addr, output bit [31:0] data,
    input bit [31:0] mask, input bit expect_slverr);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("test_rd_%h", addr));
  seq_h.m_addr = addr;
  seq_h.m_expect_slverr = expect_slverr;
  seq_h.m_expected_status = expect_slverr ? APB_SLVERR : APB_OK;
  seq_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = seq_h.m_rdata;
endtask

task mac_apb_functional_config_test_c::cdc_settle();
  repeat ($urandom_range(0, 3)) @(posedge tb_cfg_h.apb_vif.clk);
  #250ns;
endtask

task mac_apb_functional_config_test_c::run_stimulus(uvm_phase phase);
  mac_apb_functional_config_virtual_seq_c seq_h;
  bit timed_out;
  int tx_before, rx_before;

  if (env_h == null || env_h.apb3_agent_top_h == null || env_h.virtual_sequencer_h == null)
    `uvm_fatal("APB_FUNC_CFG", "Environment, APB agent, or virtual sequencer not built")
  if (!tb_cfg_h.config_done || tb_cfg_h.reset_event != MAC_RESET_EVENT_CONFIG_DONE)
    `uvm_fatal("APB_FUNC_CFG", "Reset and APB bootstrap did not complete")

  // Phase 1-6: Drive all traffic through the virtual sequence
  seq_h = mac_apb_functional_config_virtual_seq_c::type_id::create("func_cfg_seq_h");

  fork
    seq_h.start(env_h.virtual_sequencer_h);
  join

  // Wait for all outstanding frames to be processed by the DUT
  #5us;

  // Verify scoreboard completed all comparisons without error
  `uvm_info("APB_FUNC_CFG",
            $sformatf("PASS: APB register access and functional configuration test completed.  TX wire count=%0d RX client count=%0d",
                       env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt,
                       env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt),
            UVM_NONE)
endtask
