/**
 * @brief MAC RS RX (line-side) Driver.
 *
 * Receives transaction objects from the sequencer and drives
 * them onto the native MAC <-> RS interface (mac_rs_stream_if). The driver
 * is primarily active during the run_phase.
 *
 * RS drive contract follows the pure-Verilog native MAC/RS ingress boundary
 * and the converted RX preamble detector:
 *  - keep_width-byte beats (mac_rs_stream_if KEEP_WIDTH = DATA_WIDTH/8),
 *    lane-0 aligned; the stream carries preamble
 *    (7 x 0x55) + SFD (0xD5) + DA + SA + ET + payload + FCS.
 *  - keep is a contiguous-ones prefix mask, all-ones on interior
 *    beats, (1 << frame_end_byte_index) - 1 on the final beat.
 *  - sop asserts on beat 0; eop and frame_end_byte_index assert on the final
 *    beat (frame_end_byte_index = valid byte count on that beat).
 *  - error asserts only on the final beat: a beat-0 error would
 *    drop the frame at the preamble detector SEARCH state.
 *  - fcs_present mirrors insert_fcs (informational: the scalar
 *    RX port set has no fcs_present input).
 *  - ready is driven by the MAC; a stalled beat (ready low) must
 *    stay unchanged. cfg_h.ipg_bits (96 per IEEE 802.3) of idle
 *    separate consecutive frames; the final beat's unused lanes
 *    count toward that gap.
 * All signal accesses use raw-signal timing: drives are NBA
 * assignments issued after @(posedge clk) (landing in the same
 * edge's NBA region), and ready is sampled with #1step so the
 * drive/sample points match the MAC's own view of the bus.
 * Protocol field sizes come from the façade-owned
 * mac_hvl_constants.svh (migrated from rs_globals_pkg); beat
 * geometry comes from the mac_rs_stream_if parameters.
 */

class rs_driver_c extends uvm_driver #(frame_xtn_c);
  `uvm_component_utils(rs_driver_c)

  virtual mac_rs_stream_if vif;
  rs_agent_cfg_c           cfg_h;

  // Instance-local frame counter (UTL-090), read by tests via the driver
  // handle; replaces the former class-static counter on the config.
  int                      drv_data_sent_cnt = 0;

  // Per-frame driver log sink (default sim/rs_drv.log, override
  // with +RS_DRV_LOG=path). All driver uvm_info messages are
  // echoed to this file via the component report handler.
  string                   drv_log_file      = "sim/rs_drv.log";
  int                      drv_log_fd;

  extern function new(string name = "rs_driver_c", uvm_component parent = null);

  extern function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function void final_phase(uvm_phase phase);
  extern task reset_signals();
  extern task drive_frame(frame_xtn_c item);
  extern task send_beat(logic [511:0] data, logic [63:0] keep, bit sop, bit eop,
                        logic [6:0] frame_end_byte_index, bit err, bit fcs_present);
endclass

/**
 * @brief Constructor for the MAC RS RX driver.
 *
 * Initializes the driver by calling the parent class
 * constructor.
 *
 * @param name Name of the driver component.
 * @param parent Parent component in the UVM hierarchy.
 */
function rs_driver_c::new(string name = "rs_driver_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Retrieves the agent configuration and the virtual native
 * MAC <-> RS interface from the UVM configuration database.
 *
 * @param phase Current UVM build phase.
 */
function void rs_driver_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(rs_agent_cfg_c)::get(this, "", "rs_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR",
               "uvm_config_db#(rs_agent_cfg_c)::get cannot find resource rs agt config")
  end
  if (cfg_h.vif == null) begin
    `uvm_fatal("CONFIG_ERROR", "rs_agent_cfg_c::vif is null")
  end
  vif = cfg_h.vif;

  // UTL-107: driver logging is disabled by default. A per-frame log file is
  // only opened and the report handler is only re-routed when a run-configured
  // destination is supplied via +RS_DRV_LOG=<path>. Without it, the driver
  // reports at its normal verbosity to the UVM log only.
  if ($value$plusargs("RS_DRV_LOG=%s", drv_log_file)) begin
    drv_log_fd = $fopen(drv_log_file, "w");
    if (drv_log_fd == 0) begin
      `uvm_info(get_type_name(), $sformatf(
                                     "cannot open driver log %0s, falling back to cwd rs_drv.log",
                                     drv_log_file), UVM_LOW)
      drv_log_file = "rs_drv.log";
      drv_log_fd   = $fopen(drv_log_file, "w");
    end
    if (drv_log_fd == 0) begin
      `uvm_warning(get_type_name(), "cannot open any rs driver log file; driver logging disabled")
    end else begin
      set_report_default_file(drv_log_fd);
      set_report_severity_action(UVM_INFO, UVM_DISPLAY | UVM_LOG);
      set_report_verbosity_level(UVM_HIGH);
      `uvm_info(get_type_name(), $sformatf("driver log file %0s open", drv_log_file), UVM_LOW)
    end
  end
endfunction

/**
 * @brief Implements the UVM run phase.
 *
 * Continuously pulls transactions from the sequencer and drives
 * them as native RS frames.
 *
 * @param phase Current UVM run phase.
 */
task rs_driver_c::run_phase(uvm_phase phase);
  reset_signals();
  // Align the first drive to a clock edge: driving between edges
  // would let the first handshake sample complete before the beat
  // appears on the bus.
  @(posedge vif.clk);
  forever begin
    seq_item_port.get_next_item(req);
    drive_frame(req);
    seq_item_port.item_done();
  end
endtask

/**
 * @brief Drives all interface signals to their idle state.
 *
 * Called once before the drive loop starts; all signals are
 * deasserted so the DUT sees an idle bus.
 */
task rs_driver_c::reset_signals();
  vif.valid                <= 1'b0;
  vif.data                 <= '0;
  vif.keep                 <= '0;
  vif.sop                  <= 1'b0;
  vif.eop                  <= 1'b0;
  vif.frame_end_byte_index <= '0;
  vif.error                <= 1'b0;
  vif.fcs_present          <= 1'b0;
endtask

/**
 * @brief Drives one frame as a sequence of native RS beats.
 *
 * UTL-074: the line-side frame bytes are built by the shared codec
 * (mac_frame_codec_c::frame_to_rs: preamble + SFD + DA/SA/ET + payload
 * and, when insert_fcs is set, the LSB-first FCS), and the beat geometry
 * is utility-derived: beat count via ceil_div, contiguous-low keep via
 * keep_from_valid_bytes, beat lane bytes via extract_beat_bytes, and the
 * IPG idle cycles via ipg_cycles_from_valid_bytes. Handshake timing is
 * unchanged (send_beat). All frame_xtn items are constrained to the
 * standard preamble (7 x 0x55) and SFD (0xD5), so the canonical codec
 * output is byte-identical to the previous manual packing.
 *
 * Error injection (gated by cfg_h.enable_error_injection):
 *  - crc_error: the item already carries a corrupted FCS; the
 *    wire error signal stays 0 (rx_crc_check flags the residue).
 *  - length_error: the canonical ether_type is overridden with
 *    payload.size() - RS_LEN_ERR_OFFSET, which is always <= 1500
 *    and mismatched with the counted payload => invalid_length
 *    in rx_length_check.
 *  - alignment_error: error asserts on the final beat only; a
 *    beat-0 error would drop the frame at the preamble detector.
 *
 * @param item Transaction to drive.
 */
task rs_driver_c::drive_frame(frame_xtn_c item);
  mac_frame_c           canon;
  byte unsigned         wire_q               [$];
  int                   frame_size;
  int                   beats;
  int                   valid_bytes;
  logic         [511:0] data;
  logic         [ 63:0] keep;
  logic         [  6:0] frame_end_byte_index;
  bit                   last_err;
  bit                   fcs_present;

  mac_txn_logger_c::write(this, "DRIVE_RS", item);

  canon = new();
  canon.da = item.dst_addr;
  canon.sa = item.src_addr;
  // length_error injection: override ether_type with a length
  // value mismatched with the counted payload => invalid_length.
  canon.ether_type = (item.length_error && cfg_h.enable_error_injection) ?
      item.payload.size() - mac_test_pkg::RS_LEN_ERR_OFFSET : item.ether_type;
  canon.payload = new[item.payload.size()];
  foreach (item.payload[i]) canon.payload[i] = item.payload[i];
  canon.fcs              = item.fcs;
  canon.fcs_present      = item.insert_fcs;
  canon.preamble_present = 1'b1;
  canon.sfd              = 8'hD5;

  if (mac_frame_codec_c::frame_to_rs(canon, wire_q) != 0) begin
    `uvm_error(get_type_name(), "frame_to_rs failed for RS drive")
    return;
  end
  // Negative CRC tests may append octets after a valid FCS.  Keep these out
  // of the canonical Ethernet codec: they intentionally violate framing.
  foreach (item.trailing_bytes[i]) wire_q.push_back(item.trailing_bytes[i]);

  fcs_present = item.insert_fcs;
  frame_size  = wire_q.size();
  beats       = mac_hvl_utils_c::ceil_div(frame_size, vif.KEEP_WIDTH);
  for (int b = 0; b < beats; b++) begin
    valid_bytes = (frame_size - b * vif.KEEP_WIDTH >= vif.KEEP_WIDTH) ? vif.KEEP_WIDTH :
        frame_size - b * vif.KEEP_WIDTH;
    keep = mac_hvl_utils_c::keep_from_valid_bytes(valid_bytes, vif.KEEP_WIDTH);
    void'(mac_hvl_utils_c::extract_beat_bytes(wire_q, data, valid_bytes, vif.KEEP_WIDTH));
    // alignment_error asserts on the final beat only: a beat-0
    // error would drop the frame at the preamble detector SEARCH.
    last_err = (b == beats - 1) && (item.alignment_error && cfg_h.enable_error_injection);
    frame_end_byte_index = (b == beats - 1) ? valid_bytes : '0;
    send_beat(data, keep, (b == 0), (b == beats - 1), frame_end_byte_index, last_err, fcs_present);
  end

  // IEEE 802.3 inter-packet gap: cfg_h.ipg_bits of idle between
  // frames. The final beat's unused lanes already count toward
  // the gap; only the shortfall needs extra idle cycles.
  begin
    int ipg_cycles = mac_hvl_utils_c::ipg_cycles_from_valid_bytes(
        valid_bytes, vif.KEEP_WIDTH, vif.DATA_WIDTH, cfg_h.ipg_bits
    );
    repeat (ipg_cycles) @(posedge vif.clk);
  end

  drv_data_sent_cnt++;
  if (cfg_h.enable_logger) begin
    `uvm_info(get_type_name(), $sformatf("drv sent frame: %s beats=%0d bytes=%0d",
                                         item.convert2string(), beats, frame_size), UVM_MEDIUM)
  end else begin
    `uvm_info(get_type_name(), $sformatf(
              "drv sent frame: %s beats=%0d bytes=%0d", item.convert2string(), beats, frame_size),
              UVM_HIGH)
  end
endtask

/**
 * @brief Drives a single native RS beat with full handshaking.
 *
 * Writes the beat with raw nonblocking assignments (visible to the
 * DUT at the next posedge), then holds until ready is sampled high.
 * drv_cb.ready is sampled with the #1step input skew — the pre-edge
 * value, the exact view the DUT's always_ff capture uses — so the
 * driver and the DUT always agree on the handshake edge (a post-edge
 * read could advance the driver before the DUT sees the beat).
 *
 * @param data 512-bit beat payload.
 * @param keep 64-bit byte-enable prefix mask.
 * @param sop Start-of-packet marker.
 * @param eop End-of-packet marker.
 * @param frame_end_byte_index Valid byte count on the final beat.
 * @param err Error flag.
 * @param fcs_present FCS presence flag.
 */
task rs_driver_c::send_beat(logic [511:0] data, logic [63:0] keep, bit sop, bit eop,
                            logic [6:0] frame_end_byte_index, bit err, bit fcs_present);
  vif.valid                <= 1'b1;
  vif.data                 <= data;
  vif.keep                 <= keep;
  vif.sop                  <= sop;
  vif.eop                  <= eop;
  vif.frame_end_byte_index <= frame_end_byte_index;
  vif.error                <= err;
  vif.fcs_present          <= fcs_present;
  do begin
    // Wait on the raw clock edge, not the clocking-block posedge event:
    // drv_cb applies a #1step input skew whose event fires one step before
    // the real edge, so a beat driven from an item that arrives inside that
    // pre-edge window can have its first wait return in the same timestep,
    // collapsing the handshake to zero cycles and dropping the beat (the
    // DUT would then mis-decode a mid-frame beat as a new frame start).
    // The raw edge fires exactly at the transition and cannot re-fire within
    // a timestep, so the beat is held for at least one full clock.
    @(posedge vif.clk);
  // Sample ready at the raw transfer edge.  drv_cb.ready is skewed by
  // #1step and can therefore report a stale high value, causing the source
  // to advance without a real DUT handshake at a frame-size boundary.
  end while (!vif.ready);
  vif.valid <= 1'b0;
endtask

/**
 * @brief Closes the driver log file at the end of simulation.
 *
 * @param phase Current UVM phase (final_phase).
 */
function void rs_driver_c::final_phase(uvm_phase phase);
  if (drv_log_fd != 0) begin
    $fclose(drv_log_fd);
    drv_log_fd = 0;
  end
endfunction
