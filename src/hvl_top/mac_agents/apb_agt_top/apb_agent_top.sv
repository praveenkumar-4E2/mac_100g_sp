/**
 * @brief Reusable APB agent top.
 *
 * Top-level container for one or more master-side APB agents. Reads the
 * active/passive APB counts from mac_env_cfg_c, configures each child with an
 * exact component name and a descendant-only config-db scope (the config
 * scope carries the glob star, the component name does not), and factory-
 * creates every child so agent/component overrides apply.
 */
class apb_agent_top_c extends uvm_env;
  `uvm_component_utils(apb_agent_top_c)

  apb_agent_c   active_agents [];
  apb_agent_c   passive_agents[];
  mac_env_cfg_c cfg_h;

  extern function new(string name = "apb_agent_top_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
endclass

/**
 * @brief Constructor for the APB agent top.
 *
 * Initializes the agent top by calling the parent class constructor.
 *
 * @param name   Name of the agent top component.
 * @param parent Parent component in the UVM hierarchy.
 */
function apb_agent_top_c::new(string name = "apb_agent_top_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Retrieves the MAC environment configuration and creates the configured
 * active and passive APB agents, each with its config set at a
 * descendant-only scope.
 *
 * @param phase Current UVM build phase.
 */
function void apb_agent_top_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_env_cfg_c)::get(this, "", "mac_env_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR", $sformatf("%s: cannot find mac_env_cfg in config db",
                                         get_type_name()))
  end

  active_agents = new[cfg_h.num_apb_active_agents];
  foreach (active_agents[i]) begin
    if (cfg_h.apb_active_agent_cfgs[i] == null)
      `uvm_fatal("CONFIG_ERROR", $sformatf("mac_env_cfg_c::apb_active_agent_cfgs[%0d] is null", i))
    uvm_config_db#(apb_agent_cfg_c)::set(this, $sformatf("active_agents[%0d]*", i), "apb_agent_cfg",
                                         cfg_h.apb_active_agent_cfgs[i]);
    active_agents[i] = apb_agent_c::type_id::create($sformatf("active_agents[%0d]", i), this);
  end

  passive_agents = new[cfg_h.num_apb_passive_agents];
  foreach (passive_agents[i]) begin
    if (cfg_h.apb_passive_agent_cfgs[i] == null)
      `uvm_fatal("CONFIG_ERROR", $sformatf("mac_env_cfg_c::apb_passive_agent_cfgs[%0d] is null", i))
    uvm_config_db#(apb_agent_cfg_c)::set(this, $sformatf("passive_agents[%0d]*", i),
                                         "apb_agent_cfg", cfg_h.apb_passive_agent_cfgs[i]);
    passive_agents[i] = apb_agent_c::type_id::create($sformatf("passive_agents[%0d]", i), this);
  end
endfunction
