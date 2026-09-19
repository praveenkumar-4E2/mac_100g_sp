/**
 * @brief RS Agent Configuration.
 *
 * Stores the configuration settings for the RS agent. This
 * object is used to pass configuration information, such as
 * agent mode, virtual interface, and protocol-specific
 * parameters, to the agent and its sub-components through
 * the UVM configuration database.
 */
class rs_agent_cfg_c extends uvm_object;
  `uvm_object_utils(rs_agent_cfg_c)

  // Default agent behavior
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  int m_mac_id;

  // Virtual interface driven by the agent (native MAC <-> RS)
  virtual mac_rs_stream_if vif;

  // Inter-packet gap per IEEE 802.3 (96 bit-times minimum). The
  // driver converts this to idle cycles on the interface: the
  // final beat's unused lanes count toward the gap, so only
  // short falls short of the configured bits need extra cycles.
  // Explicitly resolved to the façade-owned constant in
  // mac_hvl_constants.svh (migrated from rs_globals_pkg, same name
  // and value) to prove the constant is visible without the import.
  int ipg_bits = mac_test_pkg::RS_IPG_BITS_DEFAULT;

  // Length/type boundary per IEEE 802.3: fields at or below this
  // value are lengths, above are types. Used by the monitor to
  // derive length_error.
  int eth_len_bound = mac_test_pkg::RS_ETH_LEN_BOUND;

  // Development knobs: set to 0 to disable error injection so
  // bring-up runs only clean frames.
  bit enable_error_injection = 1;

  // Set to 0 to skip the inter-packet-gap check in the monitor.
  // Used for observers of the DUT TX wire, where the gap policy is
  // owned by the DUT's tx_ipg_timer and not constrained by the TB.
  bit enable_ipg_check = 1;

  // Payload bounds applied by the sequence (soft: the item's
  // hard super-jumbo constraint still wins when these are wider).
  int min_payload_len = 46;
  int max_payload_len = 1500;

  // Default frame count per sequence run when a test does not
  // override num_frames.
  int num_frames_default = 10;

  // Set to 0 to skip creating the monitor (stimulus-only runs).
  bit has_monitor = 1;

  // Per-frame UVM_MEDIUM logging from driver and monitor.
  bit enable_logger = 0;

  extern function new(string name = "rs_agent_cfg_c");
  extern function void validate();
  extern function string convert2string();
endclass

/**
 * @brief Constructor for the RS agent configuration object.
 *
 * Initializes the configuration object by calling the
 * parent class constructor.
 *
 * @param name Name of the configuration object.
 */
function rs_agent_cfg_c::new(string name = "rs_agent_cfg_c");
  super.new(name);
endfunction

/**
 * @brief Validates the agent configuration before child components are
 *        created (UTL-083).
 *
 * Checks that the virtual interface is bound, that the active/passive role
 * is coherent with the monitor presence, that the payload bounds are
 * non-negative and not inverted, and that the inter-packet gap value is
 * a legal positive number of bit-times. All problems are collected and
 * reported in a single actionable fatal message.
 */
function void rs_agent_cfg_c::validate();
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
  if (ipg_bits <= 0) problems = {problems, $sformatf(" ipg_bits=%0d<=0", ipg_bits)};

  if (problems != "")
    `uvm_fatal(get_type_name(), $sformatf("%s: invalid configuration:%0s", get_type_name(), problems
               ))
endfunction

/**
 * @brief Returns a one-line summary of the agent configuration.
 *
 * @return Formatted configuration summary.
 */
function string rs_agent_cfg_c::convert2string();
  return {
    $sformatf(
        "is_active=%0s mac_id=%0d vif=%0d err_inj=%0b",
        is_active.name(),
        m_mac_id,
        (vif != null),
        enable_error_injection
    ),
    $sformatf(
        " payload=[%0d:%0d] num_frames_default=%0d has_monitor=%0b",
        min_payload_len,
        max_payload_len,
        num_frames_default,
        has_monitor
    ),
    $sformatf(
        " frame_logger=%0b ipg_bits=%0d eth_len_bound=0x%0h", enable_logger, ipg_bits, eth_len_bound
    )
  };
endfunction
