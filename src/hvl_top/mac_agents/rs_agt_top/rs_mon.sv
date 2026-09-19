/**
 * @brief MAC RS (line-side) Monitor.
 *
 * Passively samples the native MAC <-> RS interface (mac_rs_stream_if)
 * from the MAC side, reconstructs signal-level activity into
 * frame_xtn_c transactions, and forwards them through the
 * analysis port for checking and coverage.
 *
 * Sampling rules follow the pure-Verilog native MAC/RS ingress boundary and
 * the converted RX preamble detector:
 *  - A beat is captured on a valid && ready handshake.
 *  - Stream inputs are sampled with raw-signal timing: wait for
 *    the clock edge, then #1step, which reads the pre-edge wire
 *    values (identical to a clocking-block input skew); ready is
 *    the raw wire value.
 *  - Frames are lane-0 aligned: sop on beat 0, eop + frame_end_byte_index on
 *    the final beat, keep a contiguous-ones prefix mask.
 *  - error may assert on the final beat only (a beat-0 error
 *    drops the frame at the preamble detector SEARCH state).
 *  - fcs_present marks frames whose last four bytes are FCS.
 *  - cfg_h.ipg_bits (96 per IEEE 802.3) of idle must separate
 *    consecutive frames; the final beat's unused lanes count
 *    toward that gap.
 *
 * Reconstructed items carry:
 *  - preamble/SFD/DA/SA/ether_type/payload/fcs byte-exact from
 *    the wire, insert_fcs = fcs_present,
 *  - crc_error = FCS mismatch against a freshly computed CRC-32,
 *  - length_error = ether_type used as a length (< cfg_h.eth_len_bound)
 *    that disagrees with the counted payload,
 *  - alignment_error = wire error on the final beat.
 * Protocol field sizes come from the façade-owned
 * mac_hvl_constants.svh (migrated from rs_globals_pkg); beat
 * geometry comes from the mac_rs_stream_if parameters (KEEP_WIDTH/DATA_WIDTH).
 */

class rs_monitor_c extends uvm_monitor;
  `uvm_component_utils(rs_monitor_c)

  virtual mac_rs_stream_if               vif;
  rs_agent_cfg_c                         cfg_h;
  uvm_analysis_port #(frame_xtn_c)       analysis_port;

  // Instance-local frame counter (UTL-091), read by tests via the monitor
  // handle; replaces the former class-static counter on the config.
  int                                    mon_rcvd_xtn_cnt              = 0;
  frame_xtn_c                            last_rcvd_xtn;


  byte unsigned                          frame_q                  [$];
  frame_xtn_c                            item;
  bit                                    in_frame                      = 0;
  bit                                    beat_valid                    = 0;
  bit                                    beat_eop                      = 0;
  bit                                    frame_start                   = 0;
  int                                    idle_cnt                      = 0;
  int                                    gap_idle_cnt                  = 0;
  int                                    prev_frame_end_byte_index     = 0;
  int                                    beats                         = 0;
  int                                    frames_seen                   = 0;
  logic                            [6:0] frame_end_byte_index_v        = 0;
  bit                                    last_err                      = 0;
  bit                                    last_fcs                      = 0;

  extern function new(string name = "rs_monitor_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern task capture_beat();
  extern task check_keep();
  extern task check_ipg();
  extern task finish_frame();
  extern function void frame_to_item(byte unsigned frame_q[$], int frame_end_byte_index_v,
                                     bit last_err, bit last_fcs, output frame_xtn_c item);
endclass


/**
 * @brief Constructor implementation.
 *
 * Initializes the MAC RS monitor component and establishes
 * its relationship with the parent UVM component.
 *
 * @param name   Instance name of the monitor.
 * @param parent Parent UVM component.
 */
function rs_monitor_c::new(string name = "rs_monitor_c", uvm_component parent = null);
  super.new(name, parent);
  analysis_port = new("analysis_port", this);
endfunction


/**
 * @brief Build phase implementation.
 *
 * Retrieves the agent configuration and the virtual native
 * MAC <-> RS interface from the UVM configuration database.
 *
 * @param phase Current UVM phase.
 */
function void rs_monitor_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(rs_agent_cfg_c)::get(this, "", "rs_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR",
               "uvm_config_db#(rs_agent_cfg_c)::get cannot find resource rs agt config")
  end
  if (cfg_h.vif == null) begin
    `uvm_fatal("CONFIG_ERROR", "rs_agent_cfg_c::vif is null")
  end
  vif = cfg_h.vif;
endfunction


/**
 * @brief Implements the UVM run phase.
 *
 * Continuously samples the interface, reconstructs complete
 * frames, runs protocol checks, and forwards the captured
 * transactions to the analysis port.
 *
 * Scheduling is delegated to the sampling/checking tasks:
 * capture_beat() blocks until the next clock edge and
 * updates the capture state; on a valid && ready handshake
 * check_keep() and (at end of frame) finish_frame() run,
 * with check_ipg() verifying the inter-frame gap at the
 * start of each new frame.
 *
 * @param phase Current UVM run phase.
 */
task rs_monitor_c::run_phase(uvm_phase phase);
  prev_frame_end_byte_index = vif.KEEP_WIDTH;

  forever begin
    capture_beat();
    if (beat_valid) begin
      check_keep();
      if (frame_start) check_ipg();
      if (beat_eop) finish_frame();
    end
  end
endtask


/**
 * @brief Samples one clock edge and captures a beat.
 *
 * Blocks on the next posedge clk (sampling with #1step) and
 * updates the capture state:
 *  - valid && ready: marks beat_valid, checks sop structure,
 *    pushes the beat bytes into frame_q, and latches eop/error/
 *    fcs_present for the downstream checks.
 *  - !valid: counts one idle cycle toward the inter-frame gap.
 *    At frame start the accumulated gap count is latched into
 *    gap_idle_cnt for check_ipg before the counter resets.
 *  - other cases (e.g. unknown valid before the first drive):
 *    treated as neither handshake nor idle.
 */
task rs_monitor_c::capture_beat();
  // mon_cb input skew #1step samples the pre-edge value — the exact
  // view the DUT's always_ff capture uses — so the monitor sees the
  // same handshakes (and the same idle cycles) as the RTL.
  @(vif.mon_cb);

  beat_valid  = 0;
  frame_start = 0;
  beat_eop    = 0;

  if (vif.mon_cb.valid && vif.mon_cb.ready) begin
    beat_valid = 1;

    if (!in_frame) begin
      if (!vif.mon_cb.sop) `uvm_error(get_type_name(), "sop not asserted on first beat of frame")
      frame_start  = 1;
      gap_idle_cnt = idle_cnt;
      idle_cnt     = 0;
      in_frame     = 1;
      beats        = 0;
      frame_q.delete();
    end else if (vif.mon_cb.sop) begin
      // Also gated by enable_ipg_check: when the DUT backpressures the
      // wire (post-frame drain), the driver holds the next SOP beat and
      // ready blips make this check misfire.
      if (cfg_h.enable_ipg_check) `uvm_error(get_type_name(), "sop asserted inside frame")
    end

    beats++;

    // UTL-076: beat capture is utility-derived — the contiguous-low keep
    // maps to a valid-byte count (valid_bytes_from_keep), and
    // append_beat_bytes moves the low lanes onto the frame queue.
    void'(mac_hvl_utils_c::append_beat_bytes(
        frame_q,
        vif.mon_cb.data,
        mac_hvl_utils_c::valid_bytes_from_keep(
            vif.mon_cb.keep, vif.KEEP_WIDTH
        ),
        vif.KEEP_WIDTH
    ));

    beat_eop = vif.mon_cb.eop;
    frame_end_byte_index_v = vif.mon_cb.frame_end_byte_index;
    last_err = vif.mon_cb.error;
    last_fcs = vif.mon_cb.fcs_present;
  end else if (!vif.mon_cb.valid) begin
    idle_cnt++;
  end
endtask


/**
 * @brief Checks the keep mask of the captured beat.
 *
 * Runs on every captured handshake beat:
 *  - keep must be nonzero and a contiguous-ones prefix mask,
 *  - final beat (beat_eop): all ones when full, otherwise
 *    (1 << frame_end_byte_index) - 1,
 *  - interior beats: keep all ones, error deasserted, and
 *    frame_end_byte_index zero.
 *
 * UTL-076: the mask geometry is validated with the shared utilities
 * (is_contiguous_low_mask, frame_end_byte_index_from_keep, keep_from_valid_bytes)
 * instead of hand-rolled bit arithmetic.
 */
task rs_monitor_c::check_keep();
  bit [63:0] full_keep;

  if (vif.mon_cb.keep == '0) `uvm_error(get_type_name(), "keep = 0 on valid beat")
  else if (!mac_hvl_utils_c::is_contiguous_low_mask(vif.mon_cb.keep, vif.KEEP_WIDTH))
    `uvm_error(get_type_name(), $sformatf(
               "keep %h is not a contiguous-ones prefix mask", vif.mon_cb.keep))

  full_keep = mac_hvl_utils_c::keep_from_valid_bytes(vif.KEEP_WIDTH, vif.KEEP_WIDTH);
  if (beat_eop) begin
    if (mac_hvl_utils_c::frame_end_byte_index_from_keep(
            vif.mon_cb.keep, vif.KEEP_WIDTH
        ) != frame_end_byte_index_v)
      `uvm_error(get_type_name(), $sformatf(
                 "final beat keep %h != (1<<frame_end_byte_index)-1 (%h)",
                 vif.mon_cb.keep,
                 mac_hvl_utils_c::keep_from_valid_bytes(
                     frame_end_byte_index_v, vif.KEEP_WIDTH
                 )
                 ))
  end else begin
    if (vif.mon_cb.keep != full_keep)
      `uvm_error(get_type_name(), $sformatf("interior beat keep %h != all ones", vif.mon_cb.keep))
    if (vif.mon_cb.error) `uvm_error(get_type_name(), "error asserted on non-final beat")
    if (vif.mon_cb.frame_end_byte_index != 0)
      `uvm_error(
          get_type_name(), $sformatf(
          "frame_end_byte_index %0d nonzero on non-final beat", vif.mon_cb.frame_end_byte_index))
  end
endtask


/**
 * @brief Checks the inter-frame gap at the start of a frame.
 *
 * Verifies that the idle between consecutive frames meets the required
 * minimum.  The previous final beat's unused lanes plus whole idle cycles
 * (gap_idle_cnt, latched by capture_beat) may exceed the minimum whenever
 * the upstream client has no next frame ready; that extra source-starvation
 * time is legal and is not a MAC IPG violation.
 *
 * UTL-076: the expected whole-cycle count is derived with
 * ipg_cycles_from_valid_bytes (the single source of truth for
 * IPG geometry) instead of the inline ceiling formula.
 */
task rs_monitor_c::check_ipg();
  int idle_bits;
  int expected;

  if (frames_seen == 0) return;

  idle_bits = (vif.KEEP_WIDTH - prev_frame_end_byte_index) * 8 + gap_idle_cnt * vif.DATA_WIDTH;
  expected = mac_hvl_utils_c::ipg_cycles_from_valid_bytes(prev_frame_end_byte_index, vif.KEEP_WIDTH,
                                                          vif.DATA_WIDTH, cfg_h.ipg_bits) *
      vif.DATA_WIDTH + (vif.KEEP_WIDTH - prev_frame_end_byte_index) * 8;
  if (cfg_h.enable_ipg_check && idle_bits < expected)
    `uvm_error(get_type_name(), $sformatf(
               "IPG=%0d bits is below required minimum %0d bits (idle=%0d cycles, prev_frame_end_byte_index=%0d)",
               idle_bits,
               expected,
               gap_idle_cnt,
               prev_frame_end_byte_index
               ))
endtask


/**
 * @brief Closes out a captured frame at end of frame.
 *
 * Validates the byte count against beats and frame_end_byte_index, enforces
 * the minimum frame size, reconstructs the transaction, and
 * forwards it through the analysis port. Resets the frame state
 * for the next frame.
 */
task rs_monitor_c::finish_frame();
  frames_seen++;

  if (frame_q.size() != vif.KEEP_WIDTH * (beats - 1) + frame_end_byte_index_v)
    `uvm_error(get_type_name(), $sformatf(
               "byte count %0d != %0d*%0d+frame_end_byte_index=%0d",
               frame_q.size(),
               vif.KEEP_WIDTH,
               beats - 1,
               frame_end_byte_index_v
               ))
  else if (frame_q.size() <
           mac_test_pkg::RS_MIN_FRAME_BYTES + (last_fcs ? mac_test_pkg::RS_FCS_BYTES : 0))
    `uvm_error(get_type_name(), $sformatf(
               "frame too short: %0d bytes, fcs_present=%0b", frame_q.size(), last_fcs))
  else begin
    frame_to_item(frame_q, frame_end_byte_index_v, last_err, last_fcs, item);
    mon_rcvd_xtn_cnt++;
    last_rcvd_xtn = item;
    mac_txn_logger_c::write(this, "OBSERVE_RS", item);
    if (cfg_h.enable_logger)
      `uvm_info(
          get_type_name(), $sformatf(
          "mon rcvd frame: %s beats=%0d bytes=%0d", item.convert2string(), beats, frame_q.size()),
          UVM_MEDIUM)
    else
      `uvm_info(
          get_type_name(), $sformatf(
          "mon rcvd frame: %s beats=%0d bytes=%0d", item.convert2string(), beats, frame_q.size()),
          UVM_HIGH)
    analysis_port.write(item);
  end
  prev_frame_end_byte_index = frame_end_byte_index_v;
  in_frame                  = 0;
endtask


/**
 * @brief Reconstructs a frame_xtn_c from a captured byte stream.
 *
 * UTL-070: field parsing is delegated to `mac_frame_codec_c::rs_to_frame`
 * (the single source of truth for wire byte layout — big-endian header,
 * LSB-first FCS, preamble/SFD exclusion, CRC/length/alignment status).
 * This monitor keeps its handshake sampling, protocol checks, the raw
 * preamble-byte copy (the canonical frame records only preamble_present and
 * sfd), and the analysis-port publication; it then maps the canonical frame
 * onto the item.
 *
 * @param frame_q Captured frame bytes (preamble..FCS).
 * @param frame_end_byte_index_v Valid byte count on the final beat.
 * @param last_err  Wire error flag on the final beat.
 * @param last_fcs  Wire fcs_present flag.
 * @param item      Reconstructed transaction (output).
 */
function void rs_monitor_c::frame_to_item(byte unsigned frame_q[$], int frame_end_byte_index_v,
                                          bit last_err, bit last_fcs, output frame_xtn_c item);
  mac_frame_c canon;
  int n = frame_q.size();

  if (mac_frame_codec_c::rs_to_frame(
          frame_q,
          frame_end_byte_index_v,
          last_err,
          last_fcs,
          MAC_FRAME_DIR_RS_RX,
          cfg_h.eth_len_bound,
          canon
      ) != 0) begin
    `uvm_error(get_type_name(), $sformatf("rs_to_frame rejected %0d-byte frame (err=%0b fcs=%0b)",
                                          n, last_err, last_fcs))
    item = null;
    return;
  end

  item = frame_xtn_c::type_id::create("item");
  item.packet_id = frame_xtn_c::next_packet_id++;
  // Preamble bytes are copied straight off the wire (line-side field only;
  // the canonical model keeps preamble_present/sfd).
  item.preamble = '0;
  for (int i = 0; i < mac_test_pkg::RS_PREAMBLE_BYTES; i++)
  item.preamble[mac_test_pkg::RS_PREAMBLE_BYTES*8-1-8*i-:8] = frame_q[i];
  item.sfd        = canon.sfd;
  item.dst_addr   = canon.da;
  item.src_addr   = canon.sa;
  item.ether_type = canon.ether_type;
  item.payload    = new[canon.payload.size()];
  foreach (canon.payload[i]) item.payload[i] = canon.payload[i];
  item.insert_fcs      = canon.fcs_present;
  item.fcs             = canon.fcs;
  // Status is derived by the codec from the wire (generated FCS, ether_type
  // length field, final-beat error) and mapped onto the item error flags.
  item.crc_error       = (canon.result == MAC_FRAME_RESULT_CRC_ERROR);
  item.length_error    = (canon.result == MAC_FRAME_RESULT_LENGTH_ERROR);
  item.alignment_error = (canon.result == MAC_FRAME_RESULT_ALIGNMENT_ERROR);
endfunction
