/**
 * @brief MAC Master TX Agent Configuration.
 *
 * Stores the configuration settings for the MAC Master TX
 * agent. This object is used to pass configuration
 * information, such as agent mode, virtual interface, and
 * protocol-specific parameters, to the agent and its
 * sub-components through the UVM configuration database.
 */
class axi_agent_cfg_c extends uvm_object;
  `uvm_object_utils(axi_agent_cfg_c)

  // Default agent behavior
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  int m_mac_id;

  // Virtual interface driven by the agent
  virtual axi4_stream_if vif;

  // Development knobs: set to 0 to disable error injection so
  // bring-up runs only clean frames.
  bit enable_error_injection = 1;

  // Payload bounds applied by the sequence (soft: the item's
  // hard super-jumbo constraint still wins when these are wider).
  int min_payload_len = 46;
  int max_payload_len = 1500;

  // Default frame count per sequence run when a test does not
  // override num_tx.
  int num_tx_default = 10;

  // Set to 0 to skip creating the monitor (stimulus-only runs).
  bit has_monitor = 1;

  // Per-frame UVM_MEDIUM logging from driver and monitor.
  bit enable_logger = 0;

  // Opt-in backpressure generation: when set, the driver itself
  // deasserts vif.tready for a random number of cycles before
  // each handshake to exercise the stall path. Only use in
  // agent-only harnesses; the TB must not also drive tready.
  bit generate_backpressure = 0;
  int tready_stall_max = 5;


  extern function new(string name = "axi_agent_cfg_c");
  extern function void validate();
  extern function string convert2string();
endclass

/**
 * @brief Constructor for the MAC Master TX agent configuration object.
 *
 * Initializes the configuration object by calling the
 * parent class constructor.
 *
 * @param name Name of the configuration object.
 */
function axi_agent_cfg_c::new(string name = "axi_agent_cfg_c");
  super.new(name);
endfunction

/**
 * @brief Validates the agent configuration before child components are
 *        created (UTL-082).
 *
 * Checks that the virtual interface is bound, that the active/passive role
 * is coherent with the monitor presence, that the payload bounds are
 * non-negative and not inverted, and that the opt-in backpressure stall
 * limit is usable. All problems are collected and reported in a single
 * actionable fatal message.
 */
function void axi_agent_cfg_c::validate();
  string problems;

  if (vif == null) problems = {problems, " vif=null"};
  if (is_active == UVM_PASSIVE && !has_monitor)
    problems = {problems, " passive agent with has_monitor=0 observes nothing"};
  if (min_payload_len < 0)
    problems = {problems, $sformatf(" min_payload_len=%0d<0", min_payload_len)};
  if (max_payload_len < 0)
    problems = {problems, $sformatf(" max_payload_len=%0d<0", max_payload_len)};
  if (max_payload_len > MAC_SUPER_JUMBO_PAYLOAD_BYTES)
    problems = {problems, $sformatf(" max_payload_len=%0d exceeds super-jumbo limit %0d",
                                    max_payload_len, MAC_SUPER_JUMBO_PAYLOAD_BYTES)};
  if (min_payload_len > max_payload_len)
    problems = {
      problems, $sformatf(" payload bounds [%0d:%0d] inverted", min_payload_len, max_payload_len)
    };
  if (generate_backpressure && tready_stall_max <= 0)
    problems = {
      problems, $sformatf(" backpressure enabled but tready_stall_max=%0d<=0", tready_stall_max)
    };

  if (problems != "")
    `uvm_fatal(get_type_name(), $sformatf("%s: invalid configuration:%0s", get_type_name(), problems
               ))
endfunction

/**
 * @brief Returns a one-line summary of the agent configuration.
 *
 * @return Formatted configuration summary.
 */
function string axi_agent_cfg_c::convert2string();
  return {
    $sformatf(
        "is_active=%0s mac_id=%0d vif=%0d err_inj=%0b",
        is_active.name(),
        m_mac_id,
        (vif != null),
        enable_error_injection
    ),
    $sformatf(
        " payload=[%0d:%0d] num_tx_default=%0d has_monitor=%0b",
        min_payload_len,
        max_payload_len,
        num_tx_default,
        has_monitor
    ),
    $sformatf(
        " frame_logger=%0b backpressure=%0b stall_max=%0d",
        enable_logger,
        generate_backpressure,
        tready_stall_max
    )
  };
endfunction
