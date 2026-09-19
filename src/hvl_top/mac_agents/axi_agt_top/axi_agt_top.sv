/**
 * @brief MAC Master TX Agent Top.
 *
 * Top-level container for one or more MAC Master TX agents.
 * Responsible for creating and managing the transmit agent
 * instances used in the verification environment.
 */

class axi_agent_top_c extends uvm_env;
  `uvm_component_utils(axi_agent_top_c)

  axi_agent_c   active_agents [];
  axi_agent_c   passive_agents[];
  mac_env_cfg_c cfg_h;



  extern function new(string name = "axi_agent_top_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);

endclass

/**
 * @brief Constructor for the MAC Master TX Agent Top.
 *
 * Initializes the agent top by calling the parent
 * class constructor.
 *
 * @param name Name of the agent top component.
 * @param parent Parent component in the UVM hierarchy.
 */
function axi_agent_top_c::new(string name = "axi_agent_top_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Creates all required MAC Master TX agent instances
 * and retrieves any configuration objects needed before
 * simulation starts.
 *
 * @param phase Current UVM build phase.
 */
function void axi_agent_top_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_env_cfg_c)::get(this, "", "mac_env_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR",
               "uvm_config_db#(mac_env_cfg_c)::get cannot find resource mac env config")
  end


  active_agents = new[cfg_h.num_axi_active_agents];
  foreach (active_agents[i]) begin
    if (cfg_h.axi_active_agent_cfgs[i] == null) begin
      `uvm_fatal("CONFIG_ERROR", "mac_env_cfg_c::axi_active_agent_cfgs contains a null config")
    end
    // UTL-097: the config scope glob covers the agent and its driver/
    // monitor/sequencer descendants; the component name itself must not
    // carry the glob star.
    uvm_config_db#(axi_agent_cfg_c)::set(this, $sformatf("active_agents[%0d]*", i), "axi_agent_cfg",
                                         cfg_h.axi_active_agent_cfgs[i]);
    active_agents[i] = axi_agent_c::type_id::create($sformatf("active_agents[%0d]", i), this);
  end


  passive_agents = new[cfg_h.num_axi_passive_agents];
  foreach (passive_agents[i]) begin
    if (cfg_h.axi_passive_agent_cfgs[i] == null) begin
      `uvm_fatal("CONFIG_ERROR", "mac_env_cfg_c::axi_passive_agent_cfgs contains a null config")
    end
    uvm_config_db#(axi_agent_cfg_c)::set(this, $sformatf("passive_agents[%0d]*", i),
                                         "axi_agent_cfg", cfg_h.axi_passive_agent_cfgs[i]);
    passive_agents[i] = axi_agent_c::type_id::create($sformatf("passive_agents[%0d]", i), this);
  end
endfunction
