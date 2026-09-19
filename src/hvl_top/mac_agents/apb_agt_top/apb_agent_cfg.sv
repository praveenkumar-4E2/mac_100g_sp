// Named conservative defaults for the APB agent policy fields (B-23). The
// width defaults are 0 ("derive from the bound VIF during validate()") so the
// generic agent never duplicates interface constants in procedural code.
localparam int unsigned APB_DEFAULT_MAX_WAIT_CYCLES = 64;
localparam int unsigned APB_DEFAULT_RESET_RELEASE_CYCLES = 0;
localparam int unsigned APB_DEFAULT_ADDRESS_ALIGNMENT = 4;

/**
 * @brief APB agent configuration object.
 *
 * Owns all runtime policy for the reusable master-side APB agent: binding
 * and role, bus shape and timing, validation policies, reporting, checking,
 * and identity. The same immutable object is handed to the driver, monitor,
 * and checker through narrowly scoped uvm_config_db settings.
 *
 * Widths and alignment are derived from the bound virtual interface rather
 * than duplicated: leave m_addr_width/m_data_width at 0 to self-derive from
 * $bits of the VIF during validate().
 */
class apb_agent_cfg_c extends uvm_object;
  `uvm_object_utils(apb_agent_cfg_c)

  // Binding/role.
  virtual apb_if          m_vif;
  uvm_active_passive_enum m_is_active                 = UVM_ACTIVE;
  bit                     m_has_monitor               = 1'b1;

  // Shape (0 = derive from $bits of the bound VIF during validate()).
  int unsigned            m_addr_width                = 0;
  int unsigned            m_data_width                = 0;

  // Timing.
  int unsigned            m_max_wait_cycles           = APB_DEFAULT_MAX_WAIT_CYCLES;
  int unsigned            m_reset_release_cycles      = APB_DEFAULT_RESET_RELEASE_CYCLES;

  // Validation policy.
  bit                     m_require_word_alignment    = 1'b0;
  int unsigned            m_address_alignment         = APB_DEFAULT_ADDRESS_ALIGNMENT;
  bit                     m_check_known_values        = 1'b1;

  // Reporting.
  bit                     m_enable_logger             = 1'b0;
  uvm_verbosity           m_transfer_verbosity        = UVM_MEDIUM;

  // Checking.
  bit                     m_enable_protocol_checks    = 1'b1;
  bit                     m_enable_coverage           = 1'b0;
  bit                     m_fail_on_unexpected_slverr = 1'b1;

  // Identity.
  int unsigned            m_agent_id                  = 0;
  string                  m_instance_label            = "";

  extern function new(string name = "apb_agent_cfg_c");
  extern function void validate();
  extern function string convert2string();
endclass

/**
 * @brief Constructor for the APB agent configuration object.
 *
 * Initializes the configuration object by calling the parent constructor.
 *
 * @param name Name of the configuration object.
 */
function apb_agent_cfg_c::new(string name = "apb_agent_cfg_c");
  super.new(name);
endfunction

/**
 * @brief Validates the APB agent configuration before children are built.
 *
 * Collects every discovered configuration problem in one actionable fatal:
 * null VIF, passive agent without a monitor, unusable wait timeout, enabled
 * alignment that is zero/non-power-of-two, and configured shape that
 * disagrees with $bits of the bound virtual interface. Widths left at 0 are
 * self-derived from the bound VIF (the generic agent never hardcodes them).
 */
function void apb_agent_cfg_c::validate();
  string problems;

  if (m_vif == null) begin
    problems = {problems, " m_vif=null"};
  end else begin
    // Derive or cross-check the bus shape against the bound interface.
    if (m_addr_width == 0) m_addr_width = $bits(m_vif.paddr);
    else if (m_addr_width != $bits(m_vif.paddr))
      problems = {
        problems,
        $sformatf(" m_addr_width=%0d != $bits(vif.paddr)=%0d", m_addr_width, $bits(m_vif.paddr))
      };
    if (m_data_width == 0) m_data_width = $bits(m_vif.pwdata);
    else if (m_data_width != $bits(m_vif.pwdata))
      problems = {
        problems,
        $sformatf(" m_data_width=%0d != $bits(vif.pwdata)=%0d", m_data_width, $bits(m_vif.pwdata))
      };
  end

  if (m_is_active == UVM_PASSIVE && !m_has_monitor)
    problems = {problems, " passive agent with m_has_monitor=0 observes nothing"};
  if (m_max_wait_cycles == 0)
    problems = {
      problems, $sformatf(" m_max_wait_cycles=%0d unusable (must be >0)", m_max_wait_cycles)
    };
  if (m_require_word_alignment) begin
    if (m_address_alignment == 0)
      problems = {
        problems, $sformatf(" alignment enabled but m_address_alignment=%0d", m_address_alignment)
      };
    else if ((m_address_alignment & (m_address_alignment - 1)) != 0)
      problems = {
        problems, $sformatf(" m_address_alignment=%0d not a power of two", m_address_alignment)
      };
  end

  if (problems != "")
    `uvm_fatal(get_type_name(), $sformatf("%s: invalid configuration:%0s", get_type_name(), problems
               ))
endfunction

/**
 * @brief Returns a one-line summary of the APB agent configuration.
 *
 * @return Formatted configuration summary.
 */
function string apb_agent_cfg_c::convert2string();
  return {
    $sformatf(
        "mode=%0s monitor=%0b vif=%0d addr_w=%0d data_w=%0d",
        m_is_active.name(),
        m_has_monitor,
        (m_vif != null),
        m_addr_width,
        m_data_width
    ),
    $sformatf(
        " max_wait=%0d release=%0d align_en=%0b align=%0d known=%0b",
        m_max_wait_cycles,
        m_reset_release_cycles,
        m_require_word_alignment,
        m_address_alignment,
        m_check_known_values
    ),
    $sformatf(
        " logger=%0b verbosity=%0s checks=%0b cov=%0b fail_slverr=%0b",
        m_enable_logger,
        m_transfer_verbosity.name(),
        m_enable_protocol_checks,
        m_enable_coverage,
        m_fail_on_unexpected_slverr
    ),
    $sformatf(" agent_id=%0d label=%0s", m_agent_id, m_instance_label)
  };
endfunction
