class mac_reset_agent_top_c extends uvm_env;
  `uvm_component_utils(mac_reset_agent_top_c)

  mac_reset_agent_c agents[];
  mac_env_cfg_c     cfg_h;

  extern function new(string name = "mac_reset_agent_top_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
endclass

function mac_reset_agent_top_c::new(string name = "mac_reset_agent_top_c",
                                    uvm_component parent = null);
  super.new(name, parent);
endfunction

function void mac_reset_agent_top_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_env_cfg_c)::get(this, "", "mac_env_cfg", cfg_h))
    `uvm_fatal("RESET_CFG", "mac_env_cfg_c was not supplied")

  agents = new[cfg_h.num_reset_agents];
  foreach (agents[i]) begin
    if (cfg_h.reset_agent_cfgs[i] == null)
      `uvm_fatal("RESET_CFG", $sformatf("reset_agent_cfgs[%0d] is null", i))
    uvm_config_db#(mac_reset_agent_cfg_c)::set(this, $sformatf("agents[%0d]*", i),
                                               "mac_reset_agent_cfg", cfg_h.reset_agent_cfgs[i]);
    agents[i] = mac_reset_agent_c::type_id::create($sformatf("agents[%0d]", i), this);
  end
endfunction
