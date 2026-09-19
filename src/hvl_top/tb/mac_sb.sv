`uvm_analysis_imp_decl(_reset_sb)

/**
 * @brief
 * Top-level Ethernet MAC Scoreboard.
 *
 * Responsibilities:
 *  - Receives expected transactions from the reference model/TX monitor.
 *  - Receives actual transactions from the DUT/RX monitor.
 *  - Matches expected and actual transactions.
 *  - Performs protocol and data integrity checks.
 *  - Reports PASS/FAIL status for every compared frame.
 *  - Collects overall scoreboard statistics.
 */
class mac_scoreboard_c extends uvm_scoreboard;
  `uvm_component_utils(mac_scoreboard_c)

  uvm_tlm_analysis_fifo #(axi_item_c)                             axi_actual_fifo;
  uvm_tlm_analysis_fifo #(frame_xtn_c)                            rs_actual_fifo;
  uvm_tlm_analysis_fifo #(frame_xtn_c)                            rs_expected_fifo;
  uvm_tlm_analysis_fifo #(axi_item_c)                             axi_expected_fifo;
  uvm_analysis_imp_reset_sb #(mac_reset_item_c, mac_scoreboard_c) reset_imp;

  axi_item_c                                                      axi_expected_q    [$];
  axi_item_c                                                      axi_actual_q      [$];
  frame_xtn_c                                                     rs_expected_q     [$];
  frame_xtn_c                                                     rs_actual_q       [$];
  int unsigned                                                    tx_matches;
  int unsigned                                                    rx_matches;
  int unsigned                                                    mismatches;
  int unsigned                                                    timed_out;
  int unsigned                                                    reset_flushes;
  int unsigned                                                    reset_epochs;
  time                                                            last_match_time;
  mac_env_cfg_c                                                   cfg_h;

  extern function new(string name = "mac_scoreboard_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern task run_phase(uvm_phase phase);
  extern function void compare_tx(frame_xtn_c expected, frame_xtn_c actual);
  extern function void compare_rx(axi_item_c expected, axi_item_c actual);
  extern function void write_reset_sb(mac_reset_item_c reset_item);
  extern function void flush_pending(string reason);
  extern function bit has_unmatched();
  extern function void check_unmatched_timeout();
  extern function void report_phase(uvm_phase phase);
  extern function void check_phase(uvm_phase phase);


endclass

/**
 * @brief
 * Constructs the MAC scoreboard component.
 *
 * @param name
 * Instance name of the scoreboard.
 *
 * @param parent
 * Parent UVM component.
 *
 * @return
 * None.
 */
function mac_scoreboard_c::new(string name = "mac_scoreboard_c", uvm_component parent = null);
  super.new(name, parent);
  axi_actual_fifo   = new("axi_actual_fifo", this);
  rs_actual_fifo    = new("rs_actual_fifo", this);
  axi_expected_fifo = new("axi_expected_fifo", this);
  rs_expected_fifo  = new("rs_expected_fifo", this);
  reset_imp         = new("reset_imp", this);
endfunction




/**
 * @brief
 * Creates and initializes all scoreboard resources.
 *
 * @param phase
 * Current UVM build phase handle.
 *
 * @return
 * None.
 */
function void mac_scoreboard_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_env_cfg_c)::get(this, "", "mac_env_cfg", cfg_h))
    `uvm_fatal("CONFIG_ERROR", "mac_scoreboard_c cannot find mac_env_cfg")
endfunction



/**
 * @brief
 * Executes the main scoreboard processing loop that
 * receives, matches, and compares Ethernet frames.
 *
 * @param phase
 * Current UVM run phase handle.
 *
 * @return
 * None.
 */
task mac_scoreboard_c::run_phase(uvm_phase phase);
  axi_item_c  axi_item;
  frame_xtn_c rs_item;
  forever begin
    // Nonblocking drains mean an absent frame does not deadlock the test;
    // residual expected/actual items are reported in check_phase.
    while (axi_expected_fifo.try_get(axi_item)) axi_expected_q.push_back(axi_item);
    while (axi_actual_fifo.try_get(axi_item)) axi_actual_q.push_back(axi_item);
    while (rs_expected_fifo.try_get(rs_item)) rs_expected_q.push_back(rs_item);
    while (rs_actual_fifo.try_get(rs_item)) rs_actual_q.push_back(rs_item);

    while (rs_expected_q.size() != 0 && rs_actual_q.size() != 0)
    compare_tx(rs_expected_q.pop_front(), rs_actual_q.pop_front());
    while (axi_expected_q.size() != 0 && axi_actual_q.size() != 0)
    compare_rx(axi_expected_q.pop_front(), axi_actual_q.pop_front());
    check_unmatched_timeout();
    #1ns;
  end
endtask

function void mac_scoreboard_c::compare_tx(frame_xtn_c expected, frame_xtn_c actual);
  bit match;
  if (!cfg_h.scoreboard_enable_tx_check) return;
  match = 1;
  if (cfg_h.scoreboard_check_addresses)
    match &= (expected.preamble === actual.preamble) && (expected.sfd === actual.sfd) &&
        (expected.dst_addr === actual.dst_addr) && (expected.src_addr === actual.src_addr);
  if (cfg_h.scoreboard_check_ether_type) match &= (expected.ether_type === actual.ether_type);
  if (cfg_h.scoreboard_check_fcs)
    match &= (expected.fcs === actual.fcs) && (expected.insert_fcs === actual.insert_fcs);
  if (cfg_h.scoreboard_check_error_flags)
    match &= (expected.crc_error === actual.crc_error) &&
        (expected.length_error === actual.length_error) &&
        (expected.alignment_error === actual.alignment_error);
  if (cfg_h.scoreboard_check_payload) begin
    match &= (expected.payload.size() == actual.payload.size());
    foreach (expected.payload[i])
    if (i >= actual.payload.size() || expected.payload[i] !== actual.payload[i]) match = 0;
  end
  if (match) begin
    tx_matches++;
    last_match_time = $time;
  end else begin
    mismatches++;
    `uvm_error("MAC_SB_TX", $sformatf(
               "TX frame mismatch\n expected: %s\n actual:   %s",
               expected.convert2string(),
               actual.convert2string()
               ))
  end
endfunction

function void mac_scoreboard_c::compare_rx(axi_item_c expected, axi_item_c actual);
  bit match;
  if (!cfg_h.scoreboard_enable_rx_check) return;
  match = 1;
  if (cfg_h.scoreboard_check_addresses)
    match &= (expected.dst_addr === actual.dst_addr) && (expected.src_addr === actual.src_addr);
  if (cfg_h.scoreboard_check_ether_type) match &= (expected.ether_type === actual.ether_type);
  if (cfg_h.scoreboard_check_fcs)
    match &= (expected.fcs === actual.fcs) && (expected.insert_fcs === actual.insert_fcs);
  if (cfg_h.scoreboard_check_error_flags)
    match &= (expected.crc_error === actual.crc_error) &&
        (expected.length_error === actual.length_error) &&
        (expected.alignment_error === actual.alignment_error);
  if (cfg_h.scoreboard_check_payload) begin
    match &= (expected.payload.size() == actual.payload.size());
    foreach (expected.payload[i])
    if (i >= actual.payload.size() || expected.payload[i] !== actual.payload[i]) match = 0;
  end
  if (match) begin
    rx_matches++;
    last_match_time = $time;
  end else begin
    mismatches++;
    `uvm_error("MAC_SB_RX", $sformatf(
               "RX frame mismatch\n expected: %s\n actual:   %s",
               expected.convert2string(),
               actual.convert2string()
               ))
  end
endfunction

function bit mac_scoreboard_c::has_unmatched();
  return ((cfg_h.scoreboard_enable_rx_check &&
           (axi_expected_q.size() != 0 || axi_actual_q.size() != 0)) ||
          (cfg_h.scoreboard_enable_tx_check &&
           (rs_expected_q.size() != 0 || rs_actual_q.size() != 0)));
endfunction

function void mac_scoreboard_c::flush_pending(string reason);
  axi_item_c   axi_item;
  frame_xtn_c  rs_item;
  int unsigned flushed;
  while (axi_expected_fifo.try_get(axi_item)) flushed++;
  while (axi_actual_fifo.try_get(axi_item)) flushed++;
  while (rs_expected_fifo.try_get(rs_item)) flushed++;
  while (rs_actual_fifo.try_get(rs_item)) flushed++;
  flushed += axi_expected_q.size() + axi_actual_q.size() + rs_expected_q.size() +
      rs_actual_q.size();
  axi_expected_q.delete();
  axi_actual_q.delete();
  rs_expected_q.delete();
  rs_actual_q.delete();
  if (flushed != 0) begin
    reset_flushes += flushed;
    `uvm_info("MAC_SB_RESET", $sformatf("flushed %0d pending frame(s): %s", flushed, reason),
              UVM_MEDIUM)
  end
endfunction

function void mac_scoreboard_c::write_reset_sb(mac_reset_item_c reset_item);
  if (reset_item.operation == MAC_RESET_ASSERT) begin
    reset_epochs++;
    if (cfg_h.scoreboard_flush_on_reset)
      flush_pending($sformatf("reset_id=%0d at %0t", reset_item.reset_id, reset_item.event_time));
  end
endfunction

function void mac_scoreboard_c::check_unmatched_timeout();
  if (cfg_h.scoreboard_unmatched_timeout_ns == 0 || !has_unmatched()) return;
  if (($time - last_match_time) >= cfg_h.scoreboard_unmatched_timeout_ns) begin
    timed_out++;
    mismatches++;
    `uvm_error(
        "MAC_SB_TIMEOUT",
        $sformatf("unmatched frame timeout after %0t: tx_exp=%0d tx_act=%0d rx_exp=%0d rx_act=%0d",
                  cfg_h.scoreboard_unmatched_timeout_ns, rs_expected_q.size(), rs_actual_q.size(),
                  axi_expected_q.size(), axi_actual_q.size()))
    // Avoid re-reporting the same unmatched epoch every nanosecond.
    last_match_time = $time;
  end
endfunction

function void mac_scoreboard_c::check_phase(uvm_phase phase);
  axi_item_c  axi_item;
  frame_xtn_c rs_item;
  while (axi_expected_fifo.try_get(axi_item)) axi_expected_q.push_back(axi_item);
  while (axi_actual_fifo.try_get(axi_item)) axi_actual_q.push_back(axi_item);
  while (rs_expected_fifo.try_get(rs_item)) rs_expected_q.push_back(rs_item);
  while (rs_actual_fifo.try_get(rs_item)) rs_actual_q.push_back(rs_item);
  while (rs_expected_q.size() != 0 && rs_actual_q.size() != 0)
  compare_tx(rs_expected_q.pop_front(), rs_actual_q.pop_front());
  while (axi_expected_q.size() != 0 && axi_actual_q.size() != 0)
  compare_rx(axi_expected_q.pop_front(), axi_actual_q.pop_front());
  if ((cfg_h.scoreboard_enable_tx_check && (rs_expected_q.size() || rs_actual_q.size())) ||
      (cfg_h.scoreboard_enable_rx_check && (axi_expected_q.size() || axi_actual_q.size()))) begin
    mismatches++;
    `uvm_error("MAC_SB_RESIDUAL",
               $sformatf("unmatched frames: tx_exp=%0d tx_act=%0d rx_exp=%0d rx_act=%0d",
                         rs_expected_q.size(), rs_actual_q.size(), axi_expected_q.size(),
                         axi_actual_q.size()))
  end
endfunction

function void mac_scoreboard_c::report_phase(uvm_phase phase);
  `uvm_info("MAC_SB", $sformatf(
            "scoreboard summary: tx_matches=%0d rx_matches=%0d mismatches=%0d timed_out=%0d reset_epochs=%0d reset_flushed=%0d"
                ,
            tx_matches,
            rx_matches,
            mismatches,
            timed_out,
            reset_epochs,
            reset_flushes
            ), UVM_NONE)
endfunction
