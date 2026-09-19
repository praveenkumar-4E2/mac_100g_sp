/**
 * @brief Reusable master-side APB agent.
 *
 * Assembles the APB verification components under one uvm_agent: the monitor
 * is created whenever m_has_monitor is set, and the sequencer plus driver are
 * created only in UVM_ACTIVE mode. When protocol checking is enabled and a
 * monitor exists, the checker is created and the monitor's analysis port is
 * connected to it. A passive agent therefore contains only the monitor (and
 * checker) — never a driver or sequencer (F-07).
 */
class apb_agent_c extends uvm_agent;
  `uvm_component_utils(apb_agent_c)

  apb_sequencer_c        sequencer_h;
  apb_driver_c           driver_h;
  apb_monitor_c          monitor_h;
  apb_protocol_checker_c checker_h;
  apb_agent_cfg_c        cfg_h;

  extern function new(string name = "apb_agent_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern function void connect_phase(uvm_phase phase);
endclass

/**
 * @brief Constructor for the APB agent.
 *
 * Initializes the agent by calling the parent class constructor.
 *
 * @param name   Name of the agent component.
 * @param parent Parent component in the UVM hierarchy.
 */
function apb_agent_c::new(string name = "apb_agent_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Retrieves and validates the APB agent configuration, then creates the
 * monitor (when enabled), the protocol checker (when checking is enabled),
 * and, only for an active agent, the sequencer and driver.
 *
 * @param phase Current UVM build phase.
 */
function void apb_agent_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(apb_agent_cfg_c)::get(this, "", "apb_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR", $sformatf("%s: cannot find apb_agent_cfg in config db",
                                         get_type_name()))
  end
  cfg_h.validate();
  if (cfg_h.m_has_monitor) begin
    monitor_h = apb_monitor_c::type_id::create("monitor_h", this);
    if (cfg_h.m_enable_protocol_checks)
      checker_h = apb_protocol_checker_c::type_id::create("checker_h", this);
  end
  if (cfg_h.m_is_active == UVM_ACTIVE) begin
    sequencer_h = apb_sequencer_c::type_id::create("sequencer_h", this);
    driver_h    = apb_driver_c::type_id::create("driver_h", this);
  end
endfunction

/**
 * @brief Implements the UVM connect phase.
 *
 * Connects the active driver to the sequencer and, when present, the
 * monitor's analysis port to the protocol checker.
 *
 * @param phase Current UVM connect phase.
 */
function void apb_agent_c::connect_phase(uvm_phase phase);
  if (cfg_h.m_is_active == UVM_ACTIVE) driver_h.seq_item_port.connect(sequencer_h.seq_item_export);
  if (monitor_h != null && checker_h != null) monitor_h.ap.connect(checker_h.analysis_export);
endfunction
