/**
 * @brief Reusable passive APB monitor.
 *
 * Reconstructs transfers exclusively from apb_if.mon_cb samples (E-04), the
 * pre-edge #1step view that matches the DUT's always_ff capture. A
 * setup/access state machine latches request fields at the selected setup,
 * counts full access wait cycles, and samples PRDATA (reads) and PSLVERR
 * only at the completing access. Each completed transfer is published as a
 * fresh apb_transfer_t through a uvm_analysis_port and is never modified
 * after write() (E-14).
 *
 * Reset clears all partial state without publishing a hybrid transfer; a
 * reset-during-transfer is reported as an observation (E-13). A transfer
 * abandoned without completion (e.g. driver timeout) is discarded silently —
 * the driver already reported the timeout outcome. Unknown (X/Z) values
 * sampled on address/data/handshake signals during a transfer are flagged on
 * the published item for the checker's optional unknown-value policy.
 */
class apb_monitor_c extends uvm_monitor;
  `uvm_component_utils(apb_monitor_c)

  typedef enum {
    MON_IDLE,
    MON_SETUP,
    MON_ACCESS
  } mon_state_e;

  apb_agent_cfg_c                     cfg_h;
  uvm_analysis_port #(apb_transfer_t) ap;

  mon_state_e                         m_state    = MON_IDLE;
  apb_transfer_t                      m_latched;
  longint unsigned                    m_cycle    = 0;
  longint unsigned                    m_ordinal  = 0;

  extern function new(string name = "apb_monitor_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern function void reset_state();
  extern function void latch_setup();
  extern function void publish(apb_transfer_t t);
endclass

/**
 * @brief Constructor for the APB monitor.
 *
 * Initializes the monitor by calling the parent class constructor.
 *
 * @param name   Name of the monitor component.
 * @param parent Parent component in the UVM hierarchy.
 */
function apb_monitor_c::new(string name = "apb_monitor_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Retrieves and validates the APB agent configuration and creates the
 * analysis port through which completed transfers are published.
 *
 * @param phase Current UVM build phase.
 */
function void apb_monitor_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(apb_agent_cfg_c)::get(this, "", "apb_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR", $sformatf("%s: cannot find apb_agent_cfg in config db",
                                         get_type_name()))
  end
  cfg_h.validate();
  ap = new("ap", this);
endfunction

/**
 * @brief Implements the UVM run phase.
 *
 * Samples the interface once per APB clock and advances the setup/access
 * state machine. A sampled reset clears all partial state; otherwise the
 * machine latches a selected setup, watches for the legal access, counts
 * wait cycles, and publishes the completed transfer.
 *
 * @param phase Current UVM run phase.
 */
task apb_monitor_c::run_phase(uvm_phase phase);
  reset_state();
  forever begin
    @(posedge cfg_h.m_vif.mon_cb);
    m_cycle++;
    if (cfg_h.m_vif.mon_cb.rst) begin
      if (m_state != MON_IDLE) begin
        `uvm_info(APB_RESET_ABORT_ID,
                  $sformatf("APB monitor: reset during transfer, partial state cleared: %s",
                            m_latched.convert2string()), UVM_MEDIUM)
      end
      reset_state();
    end else begin
      case (m_state)
        MON_IDLE: begin
          if (cfg_h.m_vif.mon_cb.psel && !cfg_h.m_vif.mon_cb.penable) latch_setup();
        end
        MON_SETUP: begin
          if (cfg_h.m_vif.mon_cb.psel && cfg_h.m_vif.mon_cb.penable) begin
            m_latched.access_time  = $time;
            m_latched.access_cycle = m_cycle;
            if (cfg_h.m_vif.mon_cb.pready) begin
              // Immediate completion: access begins and completes on the same
              // clock (zero wait cycles). Sample the completing access now.
              m_latched.slverr = cfg_h.m_vif.mon_cb.pslverr;
              if (!m_latched.pwrite) m_latched.rdata = cfg_h.m_vif.mon_cb.prdata;
              if (cfg_h.m_check_known_values)
                m_latched.unknown_sampled = m_latched.unknown_sampled || $isunknown(
                    {cfg_h.m_vif.mon_cb.prdata, cfg_h.m_vif.mon_cb.pslverr}
                );
              m_latched.completion_time  = $time;
              m_latched.completion_cycle = m_cycle;
              m_latched.status           = m_latched.slverr ? APB_SLVERR : APB_OK;
              m_latched.ordinal          = m_ordinal++;
              m_latched.source_id        = cfg_h.m_agent_id;
              publish(m_latched);
              m_latched = null;
              m_state   = MON_IDLE;
            end else begin
              // First wait cycle: the access phase began but PREADY was low.
              m_latched.wait_cycles++;
              m_state = MON_ACCESS;
            end
          end else if (!cfg_h.m_vif.mon_cb.psel) begin
            // Setup was not followed by access (protocol deviation). The SVA
            // reports it; the monitor simply discards the partial item.
            m_latched = null;
            m_state   = MON_IDLE;
          end
        end
        MON_ACCESS: begin
          if (cfg_h.m_vif.mon_cb.pready) begin
            m_latched.slverr = cfg_h.m_vif.mon_cb.pslverr;
            if (!m_latched.pwrite) m_latched.rdata = cfg_h.m_vif.mon_cb.prdata;
            if (cfg_h.m_check_known_values)
              m_latched.unknown_sampled = m_latched.unknown_sampled || $isunknown(
                  {cfg_h.m_vif.mon_cb.prdata, cfg_h.m_vif.mon_cb.pslverr}
              );
            m_latched.completion_time  = $time;
            m_latched.completion_cycle = m_cycle;
            m_latched.status           = m_latched.slverr ? APB_SLVERR : APB_OK;
            m_latched.ordinal          = m_ordinal++;
            m_latched.source_id        = cfg_h.m_agent_id;
            publish(m_latched);
            m_latched = null;
            m_state   = MON_IDLE;
          end else if (!cfg_h.m_vif.mon_cb.psel) begin
            // Access abandoned without completion (driver timeout/abort or a
            // master deviation). Discard silently; never publish a hybrid.
            m_latched = null;
            m_state   = MON_IDLE;
          end else if (!cfg_h.m_vif.mon_cb.penable) begin
            // Abandoned access followed back-to-back by a fresh setup: the
            // timeout idle drive and the next transfer's setup can land in the
            // same timestep, so the setup is what is actually observed. The
            // previous transfer never completed; start over from this setup.
            m_latched = null;
            latch_setup();
          end else begin
            m_latched.wait_cycles++;
          end
        end
      endcase
    end
  end
endtask

/**
 * @brief Clears every partial monitor state field.
 *
 * Called on reset and from the constructor path; leaves the monitor ready to
 * observe a fresh transfer from idle.
 */
function void apb_monitor_c::reset_state();
  m_state   = MON_IDLE;
  m_latched = null;
endfunction

/**
 * @brief Latches a freshly observed setup phase as a new pending transfer.
 *
 * Assumes PSEL=1 and PENABLE=0 are sampled on the clocking block. Used both
 * from MON_IDLE (a new transfer begins) and from MON_ACCESS (an abandoned
 * access is immediately followed by a new setup, so the old partial state is
 * replaced by this fresh one).
 */
function void apb_monitor_c::latch_setup();
  m_latched             = apb_transfer_t::type_id::create("mon_item");
  m_latched.pwrite      = cfg_h.m_vif.mon_cb.pwrite;
  m_latched.addr        = cfg_h.m_vif.mon_cb.paddr;
  m_latched.wdata       = cfg_h.m_vif.mon_cb.pwdata;
  m_latched.setup_time  = $time;
  m_latched.setup_cycle = m_cycle;
  if (cfg_h.m_check_known_values)
    m_latched.unknown_sampled = $isunknown({cfg_h.m_vif.mon_cb.paddr, cfg_h.m_vif.mon_cb.pwdata});
  m_state = MON_SETUP;
endfunction

/**
 * @brief Publishes a completed transfer on the analysis port.
 *
 * After this call the monitor holds no reference to the published object and
 * never modifies it again (E-14); subscribers must treat it as immutable.
 *
 * @param t Completed transfer to publish.
 */
function void apb_monitor_c::publish(apb_transfer_t t);
  mac_txn_logger_c::write(this, "OBSERVE_APB", t);
  ap.write(t);
endfunction
