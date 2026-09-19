/**
 * @brief Reusable APB protocol checker.
 *
 * Non-driving analysis subscriber (E-15) consuming the monitor's published
 * transactions. Enforces transaction-level policy per the agent configuration:
 *   - E-16 timeout / reset-abort statuses (defensive; the monitor never
 *     publishes hybrids, but a mis-connected source is caught here),
 *   - E-17 optional address alignment,
 *   - E-18 optional unknown-value flagging from the monitor's 4-state sample,
 *   - E-19 unexpected slave error policy,
 *   - E-20 read/write response consistency (status matches slverr; writes
 *     carry no sampled data).
 *
 * Report IDs are distinct from the interface SVA (APB_ASSERT) and the driver
 * (APB_TIMEOUT / APB_RESET_ABORT / APB_RESPONSE): policy violations use
 * APB_PROTOCOL, and unexpected slave errors use APB_SLV_UNEXPECTED (E-21).
 * Received objects are read-only; the checker never modifies a published
 * transaction.
 */
class apb_protocol_checker_c extends uvm_subscriber #(apb_transfer_t);
  `uvm_component_utils(apb_protocol_checker_c)

  apb_agent_cfg_c cfg_h;

  int unsigned    m_n_transfers    = 0;
  int unsigned    m_n_waits        = 0;
  int unsigned    m_n_slverr       = 0;
  int unsigned    m_n_timeout      = 0;
  int unsigned    m_n_reset_abort  = 0;
  int unsigned    m_n_protocol_err = 0;

  extern function new(string name = "apb_protocol_checker_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern function void write(apb_transfer_t t);
  extern function void report_phase(uvm_phase phase);
endclass

/**
 * @brief Constructor for the APB protocol checker.
 *
 * Initializes the checker by calling the parent class constructor.
 *
 * @param name   Name of the checker component.
 * @param parent Parent component in the UVM hierarchy.
 */
function apb_protocol_checker_c::new(string name = "apb_protocol_checker_c",
                                     uvm_component parent = null);
  super.new(name, parent);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Retrieves and validates the APB agent configuration.
 *
 * @param phase Current UVM build phase.
 */
function void apb_protocol_checker_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(apb_agent_cfg_c)::get(this, "", "apb_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR", $sformatf("%s: cannot find apb_agent_cfg in config db",
                                         get_type_name()))
  end
  cfg_h.validate();
endfunction

/**
 * @brief Checks one published transaction against the configured policies.
 *
 * @param t Monitor-published transfer (read-only).
 */
function void apb_protocol_checker_c::write(apb_transfer_t t);
  m_n_transfers++;
  m_n_waits += t.wait_cycles;

  // E-16: explicit timeout/reset-abort outcome (defensive for non-monitor
  // sources; the monitor publishes neither).
  if (t.status == APB_TIMEOUT) begin
    m_n_timeout++;
    `uvm_error(APB_TIMEOUT_ID, $sformatf("APB checker: observed timeout transfer: %s",
                                         t.convert2string()))
  end
  if (t.status == APB_RESET_ABORT) begin
    m_n_reset_abort++;
    `uvm_error(APB_RESET_ABORT_ID, $sformatf("APB checker: observed reset-aborted transfer: %s",
                                             t.convert2string()))
  end

  // E-17: optional word-alignment policy.
  if (cfg_h.m_require_word_alignment && (t.addr % cfg_h.m_address_alignment) != 0) begin
    m_n_protocol_err++;
    `uvm_error(APB_PROTOCOL_ID, $sformatf("APB checker: unaligned access (align=%0d): %s",
                                          cfg_h.m_address_alignment, t.convert2string()))
  end

  // E-18: optional unknown-value policy (flag set by the monitor from its
  // 4-state samples; the item fields themselves are 2-state).
  if (cfg_h.m_check_known_values && t.unknown_sampled) begin
    m_n_protocol_err++;
    `uvm_error(APB_PROTOCOL_ID, $sformatf(
                                    "APB checker: unknown (X/Z) value sampled during transfer: %s",
                                    t.convert2string()))
  end

  // E-19: unexpected-slave-error policy.
  if (t.status == APB_SLVERR) begin
    m_n_slverr++;
    if (cfg_h.m_fail_on_unexpected_slverr)
      `uvm_error(APB_SLV_UNEXPECTED_ID, $sformatf(
                 "APB checker: unexpected PSLVERR observed: %s", t.convert2string()))
    else
      `uvm_info(APB_SLV_UNEXPECTED_ID, $sformatf(
                "APB checker: observed PSLVERR (policy allows): %s", t.convert2string()),
                UVM_MEDIUM)
  end

  // E-20: read/write response consistency.
  if (t.slverr != (t.status == APB_SLVERR)) begin
    m_n_protocol_err++;
    `uvm_error(APB_PROTOCOL_ID, $sformatf("APB checker: status/slverr inconsistent: %s",
                                          t.convert2string()))
  end
  if (t.pwrite && t.rdata !== '0) begin
    m_n_protocol_err++;
    `uvm_error(APB_PROTOCOL_ID, $sformatf("APB checker: write carried sampled read data: %s",
                                          t.convert2string()))
  end
endfunction

/**
 * @brief Prints a summary of checked transfers in the report phase.
 *
 * @param phase Current UVM report phase.
 */
function void apb_protocol_checker_c::report_phase(uvm_phase phase);
  `uvm_info(get_type_name(), $sformatf(
            "APB checker summary: transfers=%0d waits=%0d slverr=%0d timeout=%0d reset_abort=%0d protocol_err=%0d"
                ,
            m_n_transfers,
            m_n_waits,
            m_n_slverr,
            m_n_timeout,
            m_n_reset_abort,
            m_n_protocol_err
            ), UVM_MEDIUM)
endfunction
