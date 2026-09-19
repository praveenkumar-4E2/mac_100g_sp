`ifndef MAC_BASE_TEST_SVH
`define MAC_BASE_TEST_SVH

//------------------------------------------------------------------------------
// Class: mac_base_test_c
// Shared MAC test setup.  Derived tests configure only their agent topology
// and scenario; reset, APB bootstrap, configuration publication, objections,
// and standard reporting remain here.
//------------------------------------------------------------------------------
class mac_base_test_c extends uvm_test;
  `uvm_component_utils(mac_base_test_c)

  mac_env_c                env_h;
  mac_env_cfg_c            env_cfg_h;
  mac_tb_cfg_c             tb_cfg_h;
  mac_ral_block_c          ral_h;
  mac_apb_reg_adapter_c    ral_adapter_h;
  int                      num_axi_active_agents  = 0;
  int                      num_axi_passive_agents = 0;
  int                      num_rs_active_agents   = 0;
  int                      num_rs_passive_agents  = 0;
  int                      num_tx_frames          = 1;
  int                      num_rs_frames          = 1;

  virtual axi4_stream_if   axi_tx_vif;
  virtual axi4_stream_if   axi_rx_vif;
  virtual mac_rs_stream_if mac_rx_vif;
  virtual mac_rs_stream_if mac_tx_vif;
  virtual mac_reset_if     mac_reset_vif;
  virtual mac_reset_if     apb_reset_vif;

  extern function new(string name = "mac_base_test_c", uvm_component parent = null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void end_of_elaboration_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
endclass

function mac_base_test_c::new(string name = "mac_base_test_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

function void mac_base_test_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_tb_cfg_c)::get(this, "", "mac_tb_cfg", tb_cfg_h))
    `uvm_fatal("MAC_TEST_CFG", "mac_tb_cfg was not published by mac_tb_top")
  tb_cfg_h.validate();
  axi_tx_vif                       = tb_cfg_h.axi_tx_vif;
  axi_rx_vif                       = tb_cfg_h.axi_rx_vif;
  mac_rx_vif                       = tb_cfg_h.mac_rx_vif;
  mac_tx_vif                       = tb_cfg_h.mac_tx_vif;
  mac_reset_vif                    = tb_cfg_h.mac_reset_vif;
  apb_reset_vif                    = tb_cfg_h.apb_reset_vif;

  env_cfg_h                        = mac_env_cfg_c::type_id::create("env_cfg_h");
  env_cfg_h.has_function_coverage  = $test$plusargs("MAC_FUNCTIONAL_COVERAGE");
  env_cfg_h.num_axi_active_agents  = num_axi_active_agents;
  env_cfg_h.num_axi_passive_agents = num_axi_passive_agents;
  env_cfg_h.num_rs_active_agents   = num_rs_active_agents;
  env_cfg_h.num_rs_passive_agents  = num_rs_passive_agents;
  env_cfg_h.num_apb_active_agents  = 1;
  env_cfg_h.num_apb_passive_agents = 0;
  env_cfg_h.num_reset_agents       = 2;
  env_cfg_h.axi_active_agent_cfgs  = new[num_axi_active_agents];
  env_cfg_h.axi_passive_agent_cfgs = new[num_axi_passive_agents];
  env_cfg_h.rs_active_agent_cfgs   = new[num_rs_active_agents];
  env_cfg_h.rs_passive_agent_cfgs  = new[num_rs_passive_agents];
  env_cfg_h.apb_active_agent_cfgs  = new[1];
  env_cfg_h.apb_passive_agent_cfgs = new[0];
  env_cfg_h.reset_agent_cfgs       = new[2];
  configure_test();
  env_cfg_h.validate();
  uvm_config_db#(mac_env_cfg_c)::set(this, "env_h*", "mac_env_cfg", env_cfg_h);
  `uvm_info(get_type_name(), $sformatf("MAC_ENV_CONFIG\n%s", env_cfg_h.sprint()), UVM_LOW)
  env_h = mac_env_c::type_id::create("env_h", this);
endfunction

function void mac_base_test_c::configure_test();
  apb_agent_cfg_c apb_cfg;
  apb_cfg = apb_agent_cfg_c::type_id::create("apb_active_cfg[0]");
  apb_cfg.m_is_active = UVM_ACTIVE;
  apb_cfg.m_vif = tb_cfg_h.apb_vif;
  apb_cfg.m_agent_id = 0;
  apb_cfg.m_instance_label = "mac_register_master";
  env_cfg_h.apb_active_agent_cfgs[0] = apb_cfg;
  ral_h = mac_ral_block_c::type_id::create("ral_h");
  ral_h.build();
  ral_adapter_h = mac_apb_reg_adapter_c::type_id::create("ral_adapter_h");
  env_cfg_h.ral_h = ral_h;
  env_cfg_h.ral_adapter_h = ral_adapter_h;

  foreach (env_cfg_h.reset_agent_cfgs[i]) begin
    env_cfg_h.reset_agent_cfgs[i] =
        mac_reset_agent_cfg_c::type_id::create($sformatf("reset_cfg[%0d]", i));
    env_cfg_h.reset_agent_cfgs[i].is_active = UVM_ACTIVE;
    env_cfg_h.reset_agent_cfgs[i].reset_id = i;
    env_cfg_h.reset_agent_cfgs[i].vif = (i == 0) ? mac_reset_vif : apb_reset_vif;
  end
  foreach (env_cfg_h.axi_active_agent_cfgs[i]) begin
    env_cfg_h.axi_active_agent_cfgs[i] =
        axi_agent_cfg_c::type_id::create($sformatf("axi_active_cfg[%0d]", i));
    env_cfg_h.axi_active_agent_cfgs[i].is_active = UVM_ACTIVE;
    env_cfg_h.axi_active_agent_cfgs[i].vif = axi_tx_vif;
    env_cfg_h.axi_active_agent_cfgs[i].num_tx_default = num_tx_frames;
  end
  foreach (env_cfg_h.axi_passive_agent_cfgs[i]) begin
    env_cfg_h.axi_passive_agent_cfgs[i] =
        axi_agent_cfg_c::type_id::create($sformatf("axi_passive_cfg[%0d]", i));
    env_cfg_h.axi_passive_agent_cfgs[i].is_active = UVM_PASSIVE;
    env_cfg_h.axi_passive_agent_cfgs[i].vif = axi_rx_vif;
  end
  foreach (env_cfg_h.rs_active_agent_cfgs[i]) begin
    env_cfg_h.rs_active_agent_cfgs[i] =
        rs_agent_cfg_c::type_id::create($sformatf("rs_active_cfg[%0d]", i));
    env_cfg_h.rs_active_agent_cfgs[i].is_active = UVM_ACTIVE;
    env_cfg_h.rs_active_agent_cfgs[i].vif = mac_rx_vif;
    env_cfg_h.rs_active_agent_cfgs[i].num_frames_default = num_rs_frames;
    env_cfg_h.rs_active_agent_cfgs[i].enable_ipg_check = 1'b0;
  end
  foreach (env_cfg_h.rs_passive_agent_cfgs[i]) begin
    env_cfg_h.rs_passive_agent_cfgs[i] =
        rs_agent_cfg_c::type_id::create($sformatf("rs_passive_cfg[%0d]", i));
    env_cfg_h.rs_passive_agent_cfgs[i].is_active = UVM_PASSIVE;
    env_cfg_h.rs_passive_agent_cfgs[i].vif = mac_tx_vif;
    env_cfg_h.rs_passive_agent_cfgs[i].enable_ipg_check = 1'b0;
  end
endfunction

function void mac_base_test_c::end_of_elaboration_phase(uvm_phase phase);
  super.end_of_elaboration_phase(phase);
  if (ral_h != null && ral_adapter_h != null && env_h != null &&
      env_h.virtual_sequencer_h != null && env_h.virtual_sequencer_h.apb_seqr_h != null)
    ral_h.default_map.set_sequencer(env_h.virtual_sequencer_h.apb_seqr_h, ral_adapter_h);
  //uvm_top.print_topology();
endfunction

task mac_base_test_c::run_phase(uvm_phase phase);
  mac_boot_virtual_sequence_c boot_seq_h;
  phase.raise_objection(this, get_type_name());
  foreach (env_h.reset_agent_top_h.agents[i]) begin
    mac_reset_sequence_c reset_seq_h;
    reset_seq_h = mac_reset_sequence_c::type_id::create($sformatf("boot_reset_seq[%0d]", i));
    reset_seq_h.start(env_h.reset_agent_top_h.agents[i].sequencer_h);
  end
  boot_seq_h = mac_boot_virtual_sequence_c::type_id::create("boot_seq_h");
  boot_seq_h.global_control_addr = tb_cfg_h.apb_cfg_addr;
  boot_seq_h.global_control_data = tb_cfg_h.apb_cfg_data;
  boot_seq_h.start(env_h.virtual_sequencer_h);
  #(tb_cfg_h.config_done_delay_ns);
  tb_cfg_h.config_done = 1'b1;
  tb_cfg_h.reset_event = MAC_RESET_EVENT_CONFIG_DONE;
  run_stimulus(phase);
  phase.drop_objection(this);
endtask

task mac_base_test_c::run_stimulus(uvm_phase phase);
  #1ns;
endtask

`endif  // MAC_BASE_TEST_SVH
