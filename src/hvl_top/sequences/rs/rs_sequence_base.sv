/**
 * @brief Reusable RS (line-side) sequence base.
 *
 * Owns the shared mechanics of every RS stimulus sequence:
 *  - agent-config lookup from the starting sequencer (resolve_config);
 *  - configurable traffic knobs (frame count, payload bounds, error
 *    injection, broadcast DA, optional inter-frame delay);
 *  - deterministic helper tasks (send_clean_frame, send_pause_frame) that
 *    take explicit arguments so any test, virtual sequence, or subclass can
 *    reuse them without duplicating item construction.
 *
 * The knobs are `rand` with -1 sentinels: resolve_config() replaces the
 * sentinels with the agent-config defaults, while values set by the caller
 * are preserved — the body() never re-randomizes the knobs, so caller
 * assignments survive start(). Deterministic helpers that do not need the
 * config (send_clean_frame/send_pause_frame with an explicit length) are
 * safe to call without resolve_config(); helpers that randomize payload
 * size resolve sentinel bounds to the IEEE 802.3 legal range on their own.
 */
class rs_sequence_base_c extends uvm_sequence #(frame_xtn_c);
  `uvm_object_utils(rs_sequence_base_c)

  // Traffic knobs. -1 sentinels resolve to the agent config; caller-set
  // values are never overwritten by the default body().
  rand int         num_frames      = -1;  // <0 => cfg.num_frames_default
  rand int         payload_min     = -1;  // <0 => cfg.min_payload_len
  rand int         payload_max     = -1;  // <0 => cfg.max_payload_len
  rand bit         error_injection = 1'b0;
  rand bit         broadcast_da    = 1'b1;  // matches default DUT address filtering

  // Optional inter-frame delay inserted by the default body() (0 = none;
  // the RS driver owns the IPG on the native MAC/RS interface).
  time             inter_frame_delay = 0;

  // Resolved agent config (see resolve_config()).
  rs_agent_cfg_c   cfg_h;
  bit              cfg_resolved = 1'b0;
  // Sequence-local progress, available to a calling virtual sequence after
  // start() returns without reaching into the RS driver.
  int unsigned     frames_sent = 0;

  constraint c_knob_bounds {
    num_frames inside {[-1 : 100]};
    payload_min inside {[-1 : MAC_SUPER_JUMBO_PAYLOAD_BYTES]};
    payload_max inside {[-1 : MAC_SUPER_JUMBO_PAYLOAD_BYTES]};
    (payload_min >= 0) -> (payload_max >= payload_min);
  }

  extern function new(string name = "rs_sequence_base_c");
  extern task pre_body();
  extern task resolve_config();
  extern task body();
  extern function void validate_knobs();
  extern function frame_xtn_c new_random_frame();
  extern task do_rs_frame(frame_xtn_c frm);
  extern task send_random_frames(int count = -1);
  extern task send_clean_frame(int pkt_len = -1,
                               bit [47:0] da = 48'hFF_FF_FF_FF_FF_FF,
                               bit fcs_on = 1'b1);
  extern task send_pause_frame(bit [15:0] pause_quanta = 16'h0100,
                               bit [47:0] src_addr = 48'h02_00_00_00_00_01);
endclass

/**
 * @brief Constructor for the RS sequence base.
 *
 * @param name Name of the sequence object.
 */
function rs_sequence_base_c::new(string name = "rs_sequence_base_c");
  super.new(name);
endfunction

// Runs for both the base sequence and subclasses that override body().
task rs_sequence_base_c::pre_body();
  frames_sent = 0;
endtask

/**
 * @brief Resolves the agent config and fills knob sentinels.
 *
 * Looks up the rs_agent_cfg published for the agent owning the starting
 * sequencer (never a null-context wildcard), then replaces negative knobs
 * with the config defaults. Runs once; safe to call repeatedly.
 */
task rs_sequence_base_c::resolve_config();
  if (cfg_resolved) return;
  if (!uvm_config_db#(rs_agent_cfg_c)::get(m_sequencer, "", "rs_agent_cfg", cfg_h)) begin
    `uvm_fatal(get_type_name(),
               "uvm_config_db#(rs_agent_cfg_c)::get cannot find resource rs agt config")
  end
  if (num_frames < 0) num_frames = cfg_h.num_frames_default;
  if (payload_min < 0) payload_min = cfg_h.min_payload_len;
  if (payload_max < 0) payload_max = cfg_h.max_payload_len;
  validate_knobs();
  cfg_resolved = 1'b1;
endtask

// Report invalid caller configuration before transaction randomization.
function void rs_sequence_base_c::validate_knobs();
  if (num_frames < 0 || num_frames > 100 || payload_min < 0 || payload_max < payload_min ||
      payload_max > MAC_SUPER_JUMBO_PAYLOAD_BYTES)
    `uvm_fatal(get_type_name(), $sformatf(
               "Invalid RS sequence knobs: num_frames=%0d payload_min=%0d payload_max=%0d",
               num_frames, payload_min, payload_max))
endfunction

/**
 * @brief Default behavior: drive num_frames randomized frames.
 *
 * Honors the knobs: payload bounds, error-injection enable, and broadcast
 * DA are applied per frame; an optional inter-frame delay is inserted.
 * Subclasses override body() to compose the deterministic helpers instead.
 */
task rs_sequence_base_c::body();
  resolve_config();
  send_random_frames();
endtask

// Drives a caller-selected randomized burst, or num_frames when omitted.
task rs_sequence_base_c::send_random_frames(int count = -1);
  int actual_count;
  actual_count = (count < 0) ? num_frames : count;
  if (actual_count < 0 || actual_count > 100)
    `uvm_fatal(get_type_name(), $sformatf("Invalid RS frame count: %0d", actual_count))
  repeat (actual_count) begin
    frame_xtn_c frm;
    frm = new_random_frame();
    do_rs_frame(frm);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

/**
 * @brief Creates and randomizes a single frame honoring the knobs.
 *
 * When error_injection is disabled, the frame is clean (no CRC/length/
 * alignment errors). Payload size is softly bounded by payload_min/max, the
 * EtherType is kept above the length/type boundary, and broadcast_da fixes
 * the destination to the broadcast address when set.
 *
 * @return Fully randomized frame_xtn_c (not yet sent).
 */
function frame_xtn_c rs_sequence_base_c::new_random_frame();
  frame_xtn_c frm;
  if (payload_min < 0) payload_min = 46;
  if (payload_max < 0) payload_max = 1500;
  frm = frame_xtn_c::type_id::create("frm");
  if (!frm.randomize() with {
        if (error_injection == 1'b0) {
          crc_error == 0;
          length_error == 0;
          alignment_error == 0;
        }
        payload.size() inside {[payload_min : payload_max]};
        soft ether_type > 16'h0600;
        if (broadcast_da) dst_addr == 48'hFF_FF_FF_FF_FF_FF;
      }) begin
    `uvm_fatal(get_type_name(), "Randomization of frame_xtn_c failed")
  end
  return frm;
endfunction

/**
 * @brief Drives one frame through the sequencer to the RS driver.
 *
 * @param frm Frame to send.
 */
task rs_sequence_base_c::do_rs_frame(frame_xtn_c frm);
  if (frm == null) `uvm_fatal(get_type_name(), "Cannot drive a null RS frame")
  start_item(frm);
  finish_item(frm);
  frames_sent++;
endtask

/**
 * @brief Builds and drives one deterministic clean frame.
 *
 * The frame is guaranteed valid (no errors, EtherType above the length/type
 * boundary) with an explicit destination and optional payload length. When
 * pkt_len < 0 the payload is randomized within the knob bounds.
 *
 * @param pkt_len Fixed payload length, or -1 to randomize within bounds.
 * @param da      Destination MAC address.
 * @param fcs_on  Whether the line-side frame carries a computed FCS.
 */
task rs_sequence_base_c::send_clean_frame(int pkt_len = -1,
                                          bit [47:0] da = 48'hFF_FF_FF_FF_FF_FF,
                                          bit fcs_on = 1'b1);
  frame_xtn_c frm;
  if (payload_min < 0) payload_min = 46;
  if (payload_max < 0) payload_max = 1500;
  frm = frame_xtn_c::type_id::create("frm");
  if (!frm.randomize() with {
        dst_addr == da;
        crc_error == 0;
        length_error == 0;
        alignment_error == 0;
        insert_fcs == fcs_on;
        soft ether_type > 16'h0600;
        if (pkt_len >= 0) payload.size() == pkt_len;
        else payload.size() inside {[payload_min : payload_max]};
      }) begin
    `uvm_fatal(get_type_name(), "Randomization of clean frame failed")
  end
  do_rs_frame(frm);
endtask

/**
 * @brief Builds and drives one IEEE 802.3 Annex 31B PAUSE control frame.
 *
 * Deterministic control frame: DA 01-80-C2-00-00-01, EtherType 0x8808,
 * opcode 0x0001, two-byte pause quanta, padded to the minimum frame size,
 * with a valid FCS. The RS driver regenerates preamble/SFD itself.
 *
 * @param pause_quanta Pause time in quanta (big-endian payload field).
 * @param src_addr     Source MAC address.
 */
task rs_sequence_base_c::send_pause_frame(bit [15:0] pause_quanta = 16'h0100,
                                          bit [47:0] src_addr = 48'h02_00_00_00_00_01);
  frame_xtn_c frm;
  frm            = frame_xtn_c::type_id::create("frm");
  frm.dst_addr   = 48'h01_80_C2_00_00_01;
  frm.src_addr   = src_addr;
  frm.ether_type = 16'h8808;
  frm.payload    = new[46];
  frm.payload[0] = 8'h00;  // opcode high
  frm.payload[1] = 8'h01;  // opcode low = PAUSE
  frm.payload[2] = pause_quanta[15:8];  // pause time high
  frm.payload[3] = pause_quanta[7:0];  // pause time low
  foreach (frm.payload[i]) if (i > 3) frm.payload[i] = 8'h00;  // pad to min frame
  frm.insert_fcs      = 1'b1;
  frm.crc_error       = 1'b0;
  frm.length_error    = 1'b0;
  frm.alignment_error = 1'b0;
  frm.fcs             = frm.compute_fcs();
  do_rs_frame(frm);
endtask
