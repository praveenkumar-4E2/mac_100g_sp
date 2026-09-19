/**
 * @brief Reusable master-side APB driver.
 *
 * Consumes apb_transfer_c items from the sequencer and drives the APB master
 * signals (psel/penable/pwrite/paddr/pwdata) through the interface contract
 * defined in docs/interface/apb_agent_contract.md:
 *
 *   idle      PSEL=0, PENABLE=0
 *   setup     PSEL=1, PENABLE=0            (exactly one APB clock)
 *   access    PSEL=1, PENABLE=1            (held through every wait cycle)
 *   complete  access sampled with PREADY=1 (PRDATA/PSLVERR sampled here only)
 *
 * Master signals are written with raw nonblocking assignments and the slave
 * handshake (prdata/pready/pslverr) plus reset are sampled through the drv_cb
 * #1step pre-edge skew, so the driver and the DUT always agree on completion.
 * This driver never writes prdata, pready, or pslverr (D-22).
 *
 * Every acquired item receives exactly one item_done() and exactly one
 * response: APB_OK/APB_SLVERR on normal completion, APB_TIMEOUT when the
 * configured wait bound is exceeded, and APB_RESET_ABORT when reset is
 * sampled during setup/access. Timeout and reset-abort both restore the bus
 * to idle so the sequencer is never left blocked.
 */
class apb_driver_c extends uvm_driver #(apb_transfer_c);
  `uvm_component_utils(apb_driver_c)

  apb_agent_cfg_c  cfg_h;

  // Response ordinal and observed-clock counter for this driver instance.
  longint unsigned m_ordinal = 0;
  longint unsigned m_cycle   = 0;

  extern function new(string name = "apb_driver_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern task tick();
  extern task drive_idle();
  extern task wait_reset_deasserted();
  extern function apb_transfer_t new_response(apb_transfer_t req);
  extern task drive_transfer(apb_transfer_t req, apb_transfer_t rsp);
endclass

/**
 * @brief Constructor for the APB driver.
 *
 * Initializes the driver by calling the parent class constructor.
 *
 * @param name   Name of the driver component.
 * @param parent Parent component in the UVM hierarchy.
 */
function apb_driver_c::new(string name = "apb_driver_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Retrieves and validates the APB agent configuration from the config
 * database before any sequence item is processed.
 *
 * @param phase Current UVM build phase.
 */
function void apb_driver_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(apb_agent_cfg_c)::get(this, "", "apb_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR", $sformatf("%s: cannot find apb_agent_cfg in config db",
                                         get_type_name()))
  end
  cfg_h.validate();
endfunction

/**
 * @brief Implements the UVM run phase.
 *
 * Drives the bus to idle, then continuously serves sequence items: each item
 * is driven only after reset deassertion and the configured post-reset
 * release cycles, and every item is completed with exactly one response.
 *
 * @param phase Current UVM run phase.
 */
task apb_driver_c::run_phase(uvm_phase phase);
  apb_transfer_t req;
  apb_transfer_t rsp;
  drive_idle();
  forever begin
    seq_item_port.get_next_item(req);
    drive_idle();
    wait_reset_deasserted();
    if (cfg_h.m_reset_release_cycles > 0) repeat (cfg_h.m_reset_release_cycles) tick();
    rsp = new_response(req);
    drive_transfer(req, rsp);
    mac_txn_logger_c::write(this, "DRIVE_APB", rsp);
    seq_item_port.item_done(rsp);
  end
endtask

/**
 * @brief Advances one APB clock and updates the observed-cycle counter.
 *
 * Every @(posedge) this driver takes passes through tick() so setup/access/
 * completion cycle metadata uses a consistent per-driver timebase.
 *
 * The wait uses the raw clock edge rather than a clocking-block posedge event.
 * The drv_cb clocking block applies a #1step input skew, so its posedge event
 * fires one step before the real edge; if the driver resumes (get_next_item,
 * reset release) inside that pre-edge window, a second immediate tick() can
 * return in the same timestep and collapse the setup phase to zero cycles.
 * The raw clock edge fires exactly at the transition and cannot re-fire within
 * the same timestep, so every tick advances exactly one APB clock and the
 * setup phase is always observed for one full cycle by the DUT.  Slave-side
 * handshake sampling still goes through drv_cb, which captures the pre-edge
 * values the DUT's always_ff blocks consume.
 */
task apb_driver_c::tick();
  @(posedge cfg_h.m_vif.clk);
  m_cycle++;
endtask

/**
 * @brief Drives every master signal to the defined APB idle state.
 *
 * PSEL/PENABLE/PWRITE are deasserted and address/write data are cleared with
 * raw nonblocking assignments. Slave outputs (prdata/pready/pslverr) are
 * never touched.
 */
task apb_driver_c::drive_idle();
  cfg_h.m_vif.psel <= 1'b0;
  cfg_h.m_vif.penable <= 1'b0;
  cfg_h.m_vif.pwrite <= 1'b0;
  cfg_h.m_vif.paddr <= '0;
  cfg_h.m_vif.pwdata <= '0;
endtask

/**
 * @brief Waits until reset is sampled deasserted.
 *
 * Samples reset through the drv_cb pre-edge skew; returns right after the
 * first posedge at which reset is deasserted, so the DUT has already observed
 * the deassertion.
 */
task apb_driver_c::wait_reset_deasserted();
  while (cfg_h.m_vif.drv_cb.rst) tick();
endtask

/**
 * @brief Builds a fresh response shell carrying the request fields.
 *
 * Creates a new apb_transfer_t (never a copy of the request object, so the
 * request remains untouched for monitor/coverage consumers), seeds request
 * and identity metadata, and marks it as the completion for the request via
 * set_id_info so the sequence's get_response() can match it.
 *
 * @param req Acquired request item.
 * @return Response object seeded with request fields.
 */
function apb_transfer_t apb_driver_c::new_response(apb_transfer_t req);
  apb_transfer_t rsp = apb_transfer_t::type_id::create("rsp");
  rsp.pwrite        = req.pwrite;
  rsp.addr          = req.addr;
  rsp.wdata         = req.wdata;
  rsp.expect_slverr = req.expect_slverr;
  rsp.ordinal       = m_ordinal++;
  rsp.source_id     = cfg_h.m_agent_id;
  rsp.tag           = req.tag;
  rsp.set_id_info(req);
  return rsp;
endfunction

/**
 * @brief Drives one APB transfer and fills the response.
 *
 * Performs the setup phase for exactly one APB clock, enters the access
 * phase on the following clock, and holds every request control stable while
 * PREADY is low. PRDATA (reads) and PSLVERR are sampled only at the
 * completing access (PREADY sampled high). Returns through the response:
 *   - APB_OK / APB_SLVERR on normal completion,
 *   - APB_TIMEOUT when the configured wait bound is exceeded (bus returned
 *     to idle),
 *   - APB_RESET_ABORT when reset is sampled during setup/access (bus
 *     returned to idle).
 * In every outcome the bus is left idle, and completion/timeout/abort all
 * count exactly one item_done() in run_phase.
 *
 * @param req Acquired request item.
 * @param rsp Response object to fill.
 */
task apb_driver_c::drive_transfer(apb_transfer_t req, apb_transfer_t rsp);
  int unsigned wait_cycles = 0;

  // Setup phase: selected, not enabled, with direction/address/write data.
  cfg_h.m_vif.psel <= 1'b1;
  cfg_h.m_vif.penable <= 1'b0;
  cfg_h.m_vif.pwrite <= req.pwrite;
  cfg_h.m_vif.paddr <= req.addr;
  cfg_h.m_vif.pwdata <= req.wdata;
  rsp.setup_time  = $time;
  rsp.setup_cycle = m_cycle;

  tick();
  if (cfg_h.m_vif.drv_cb.rst) begin
    drive_idle();
    rsp.status          = APB_RESET_ABORT;
    rsp.completion_time = $time;
    `uvm_info(APB_RESET_ABORT_ID, $sformatf("APB reset abort during setup: %s",
                                            rsp.convert2string()), UVM_MEDIUM)
    return;
  end

  // Access phase: entered exactly one APB clock after setup.
  cfg_h.m_vif.penable <= 1'b1;
  rsp.access_time  = $time;
  rsp.access_cycle = m_cycle;

  forever begin
    tick();
    if (cfg_h.m_vif.drv_cb.rst) begin
      drive_idle();
      rsp.status          = APB_RESET_ABORT;
      rsp.completion_time = $time;
      `uvm_info(APB_RESET_ABORT_ID, $sformatf("APB reset abort during access: %s",
                                              rsp.convert2string()), UVM_MEDIUM)
      return;
    end
    if (cfg_h.m_vif.drv_cb.pready) break;
    wait_cycles++;
    if (wait_cycles > cfg_h.m_max_wait_cycles) begin
      drive_idle();
      rsp.status           = APB_TIMEOUT;
      rsp.wait_cycles      = wait_cycles;
      rsp.completion_time  = $time;
      rsp.completion_cycle = m_cycle;
      `uvm_info(APB_TIMEOUT_ID, $sformatf("APB timeout after %0d wait cycles: %s", wait_cycles,
                                          rsp.convert2string()), UVM_MEDIUM)
      return;
    end
  end

  // Completing access: PREADY sampled high; sample PRDATA (reads) and
  // PSLVERR here, never during earlier wait cycles.
  rsp.slverr = cfg_h.m_vif.drv_cb.pslverr;
  if (!req.pwrite) rsp.rdata = cfg_h.m_vif.drv_cb.prdata;
  rsp.wait_cycles      = wait_cycles;
  rsp.completion_time  = $time;
  rsp.completion_cycle = m_cycle;
  rsp.status           = rsp.slverr ? APB_SLVERR : APB_OK;
  drive_idle();

  if (cfg_h.m_enable_logger)
    `uvm_info(get_type_name(), $sformatf("APB drv %s", rsp.convert2string()),
              cfg_h.m_transfer_verbosity)
  else `uvm_info(get_type_name(), $sformatf("APB drv %s", rsp.convert2string()), UVM_HIGH)
endtask
