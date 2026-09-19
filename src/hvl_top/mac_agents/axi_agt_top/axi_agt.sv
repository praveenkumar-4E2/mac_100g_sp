/**
 * @brief MAC Master TX Agent.
 *
 * Encapsulates all transmit-side verification components,
 * including the sequencer, driver, and monitor. It is
 * responsible for creating and connecting these components
 * based on the agent configuration.
 */
class axi_agent_c extends uvm_agent;
  `uvm_component_utils(axi_agent_c)

  axi_sequencer_c sequencer_h;
  axi_driver_c    driver_h;
  axi_monitor_c   monitor_h;
  axi_agent_cfg_c cfg_h;

  extern function new(string name = "axi_agent_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern function void connect_phase(uvm_phase phase);

endclass

/**
 * @brief Constructor for the MAC Master TX agent.
 *
 * Initializes the agent by calling the parent
 * class constructor.
 *
 * @param name Name of the agent component.
 * @param parent Parent component in the UVM hierarchy.
 */
function axi_agent_c::new(string name = "axi_agent_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Creates all required agent components and retrieves
 * configuration objects and virtual interfaces from
 * the UVM configuration database.
 *
 * @param phase Current UVM build phase.
 */
function void axi_agent_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(axi_agent_cfg_c)::get(this, "", "axi_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR",
               "uvm_config_db#(axi_agent_cfg_c)::get cannot find resource axi agt config");
  end
  cfg_h.validate();
  if (cfg_h.is_active == UVM_ACTIVE) begin
    sequencer_h = axi_sequencer_c::type_id::create("sequencer_h", this);
    driver_h = axi_driver_c::type_id::create("driver_h", this);
  end
  if (cfg_h.has_monitor) begin
    monitor_h = axi_monitor_c::type_id::create("monitor_h", this);
  end

endfunction

/**
 * @brief Implements the UVM connect phase.
 *
 * Connects the sequencer to the driver and establishes
 * all required TLM connections within the agent.
 *
 * @param phase Current UVM connect phase.
 */
function void axi_agent_c::connect_phase(uvm_phase phase);
  if (cfg_h.is_active == UVM_ACTIVE) begin
    driver_h.seq_item_port.connect(sequencer_h.seq_item_export);
  end
endfunction
