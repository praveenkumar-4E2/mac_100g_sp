/**
 * @brief Encapsulates the MAC RX verification components.
 *
 * The agent creates and manages the sequencer, driver,
 * and monitor required for MAC RX verification. It is
 * responsible for building these components and connecting
 * them to enable transaction-level communication.
 */
class rs_agent_c extends uvm_agent;
  `uvm_component_utils(rs_agent_c)

  rs_driver_c    driver_h;
  rs_monitor_c   monitor_h;
  rs_sequencer_c sequencer_h;
  rs_agent_cfg_c cfg_h;

  extern function new(string name = "rs_agent_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern function void connect_phase(uvm_phase phase);
endclass


/**
 * @brief Constructor implementation.
 *
 * Initializes the MAC RX agent component and establishes
 * its relationship with the parent UVM component.
 *
 * @param name   Instance name of the agent.
 * @param parent Parent UVM component.
 */
function rs_agent_c::new(string name = "rs_agent_c", uvm_component parent = null);
  super.new(name, parent);
endfunction


/**
 * @brief Build phase implementation.
 *
 * Creates and initializes the sequencer, driver, and
 * monitor components required for the MAC RX agent.
 *
 * @param phase Current UVM phase.
 */
function void rs_agent_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(rs_agent_cfg_c)::get(this, "", "rs_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR",
               "uvm_config_db#(rs_agent_cfg_c)::get cannot find resource rs agent config")
  end
  cfg_h.validate();

  if (cfg_h.is_active == UVM_ACTIVE) begin
    driver_h    =  rs_driver_c::type_id::create("driver_h",this);
    sequencer_h   =  rs_sequencer_c::type_id::create("sequencer_h",this);
  end
  if (cfg_h.has_monitor) monitor_h = rs_monitor_c::type_id::create("monitor_h", this);
endfunction


/**
 * @brief Connect phase implementation.
 *
 * Establishes the connections between the sequencer,
 * driver, and monitor to enable transaction flow
 * within the MAC RX agent.
 *
 * @param phase Current UVM phase.
 */
function void rs_agent_c::connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  if (cfg_h.is_active == UVM_ACTIVE) begin
    driver_h.seq_item_port.connect(sequencer_h.seq_item_export);
  end
endfunction
