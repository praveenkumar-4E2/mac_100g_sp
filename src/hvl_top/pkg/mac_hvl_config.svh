/**
 * @brief HVL façade-owned top-level testbench configuration (mac_test_pkg
 *        member).
 *
 * UTL-077: a typed object carrying all top-level virtual interfaces and the
 * reset/configuration-completion state, replacing the four wildcard VIF
 * database gets in mac_base_test_c (UTL-080) and the wildcard `rst_done`
 * flag (UTL-111).
 *
 * The single instance is built and published by mac_tb_top (UTL-079) before
 * run_test begins; the base test retrieves it by exact path. mac_tb_top also
 * reads the configuration-intent fields (APB bootstrap write, RX-ready
 * policy, settle delays) so no hard-coded configuration decision lives in
 * the module (UTL-109/110/112).
 *
 * This file is a member of mac_test_pkg (text-included), so it must NOT
 * declare `package`/`endpackage`.
 */
`ifndef MAC_HVL_CONFIG_SVH
`define MAC_HVL_CONFIG_SVH

class mac_tb_cfg_c extends uvm_object;
  `uvm_object_utils(mac_tb_cfg_c)

  //------------------------------------------------------------------------
  // Top-level virtual interfaces (published by mac_tb_top).
  //------------------------------------------------------------------------
  virtual axi4_stream_if          axi_tx_vif;
  virtual axi4_stream_if          axi_rx_vif;
  virtual mac_rs_stream_if        mac_rx_vif;
  virtual mac_rs_stream_if        mac_tx_vif;
  virtual apb_if                  apb_vif;
  virtual mac_reset_if            mac_reset_vif;
  virtual mac_reset_if            apb_reset_vif;

  //------------------------------------------------------------------------
  // Reset / configuration-completion state.
  // Typed replacement for the wildcard `rst_done` database flag.
  //------------------------------------------------------------------------
  mac_reset_event_e               reset_event          = MAC_RESET_EVENT_NONE;
  bit                             config_done          = 0;

  //------------------------------------------------------------------------
  // APB initial-configuration intent (UTL-109/110): describes what the
  // top-level bootstrap must write instead of hard-coding the write.
  // REG_GLOBAL_CONTROL = 0x0004, CTRL_RX|CTRL_TX|CTRL_PROMISCUOUS = 0x85.
  //------------------------------------------------------------------------
  bit                             apb_bootstrap_enable = 1'b1;
  logic                    [15:0] apb_cfg_addr         = 16'h0004;
  logic                    [31:0] apb_cfg_data         = 32'h0000_0085;

  // Post-reset settle before the APB bootstrap write (ns) and post-write
  // settle before config_done (ns). Match the current top-level #100ns /
  // #50ns behavior.
  time                            apb_cfg_delay_ns     = 100;
  time                            config_done_delay_ns = 50;

  //------------------------------------------------------------------------
  // RX-ready policy (UTL-112/113): when set, the TB keeps axi_rx_if.tready
  // asserted for the whole run (baseline behavior). A future APB agent or
  // policy change replaces this controller; the hard-coded direct assign is
  // removed once this named controller is proven equivalent.
  //------------------------------------------------------------------------
  bit                             rx_ready_always      = 1'b1;

  extern function new(string name = "mac_tb_cfg_c");
  extern function void validate();
  extern function string convert2string();
endclass

/**
   * @brief Constructor for the top-level testbench configuration object.
   */
function mac_tb_cfg_c::new(string name = "mac_tb_cfg_c");
  super.new(name);
endfunction

/**
   * @brief Validates the configuration: every required top-level virtual
   *        interface must be bound.
   *
   * UTL-078: fails with a single actionable fatal message naming every null
   * required interface, so a mis-wired testbench aborts at elaboration with
   * one clear error instead of a chain of confusing ones.
   */
function void mac_tb_cfg_c::validate();
  string missing;

  if (axi_tx_vif == null) missing = {missing, " axi_tx_vif"};
  if (axi_rx_vif == null) missing = {missing, " axi_rx_vif"};
  if (mac_rx_vif == null) missing = {missing, " mac_rx_vif"};
  if (mac_tx_vif == null) missing = {missing, " mac_tx_vif"};
  if (apb_vif == null) missing = {missing, " apb_vif"};
  if (mac_reset_vif == null) missing = {missing, " mac_reset_vif"};
  if (apb_reset_vif == null) missing = {missing, " apb_reset_vif"};

  if (missing != "")
    `uvm_fatal(get_type_name(), $sformatf(
               "mac_tb_cfg_c: required virtual interface(s) not bound:%0s", missing))
endfunction

/**
   * @brief Returns a one-line summary of the top-level configuration.
   */
function string mac_tb_cfg_c::convert2string();
  return {
    $sformatf(
        "vif axi_tx=%0d axi_rx=%0d mac_rx=%0d mac_tx=%0d apb=%0d mac_rst=%0d apb_rst=%0d",
        (axi_tx_vif != null),
        (axi_rx_vif != null),
        (mac_rx_vif != null),
        (mac_tx_vif != null),
        (apb_vif != null),
        (mac_reset_vif != null),
        (apb_reset_vif != null)
    ),
    $sformatf(
        " cfg_done=%0b rst_event=%0s apb_addr=%h apb_data=%h",
        config_done,
        reset_event.name(),
        apb_cfg_addr,
        apb_cfg_data
    ),
    $sformatf(
        " rx_ready_always=%0b apb_delay=%0t done_delay=%0t",
        rx_ready_always,
        apb_cfg_delay_ns,
        config_done_delay_ns
    )
  };
endfunction

`endif  // MAC_HVL_CONFIG_SVH
