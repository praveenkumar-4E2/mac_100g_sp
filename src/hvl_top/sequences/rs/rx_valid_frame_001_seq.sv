/**
 * @brief RX Valid Frame Reception Sequence (RX_VALID_FRAME_001).
 *
 * Verifies that the DUT RX MAC path accepts complete error-free
 * Ethernet frames after a valid preamble/SFD and delivers correctly
 * disassembled fields (DA, SA, Length/Type, Payload, FCS) to the
 * MAC client.
 *
 * Stimulus iterations:
 *   1. Basic       — nominal valid DA, SA, length/type, payload, FCS.
 *   2. Boundary    — minimum (46 B) and maximum (1500 B) payload sizes;
 *                    payload/FCS alignment edge cases.
 *   3. Pattern     — zero, all-ones, alternating, incrementing, and
 *                    random payloads; single, mixed-size, back-to-back.
 *   4. Config      — default legal RX configuration (applied by test).
 *   + Alternate legal payload start patterns after SFD.
 *   + One-byte preamble/SFD shifts (left/right).
 *   + Mixed valid and malformed starts back-to-back.
 *   + Constrained-random byte-stream campaigns.
 *
 * Every legal error-free frame produces exactly one correctly ordered
 * receive transaction with intact DA, SA, length/type, data, and FCS.
 * Malformed frames (short preamble, invalid SFD) must be discarded.
 */
class rx_valid_frame_001_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(rx_valid_frame_001_seq_c)

  extern function new(string name = "rx_valid_frame_001_seq_c");
  extern task body();

  extern task send_valid_frame(int payload_len = -1,
                               byte unsigned start_byte = 8'h00,
                               bit [47:0] da = 48'hFF_FF_FF_FF_FF_FF);
  extern task send_valid_frame_with_pattern(int payload_len,
                                            mac_hvl_utils_c::payload_pattern_e pattern,
                                            int unsigned seed = 32'h1);
  extern task send_back_to_back_valid(int count);
  extern task send_short_preamble(int preamble_bytes);
  extern task send_invalid_sfd(byte unsigned bad_sfd);
  extern task send_mixed_valid_invalid(int count);
  extern task send_random_valid_frame();
  extern task send_random_invalid_frame();
endclass

function rx_valid_frame_001_seq_c::new(string name = "rx_valid_frame_001_seq_c");
  super.new(name);
endfunction

task rx_valid_frame_001_seq_c::body();
  resolve_config();

  // ---------------------------------------------------------------
  // Iteration 1: Basic — nominal valid frames with default fields.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "RX_VALID_FRAME_001 iteration 1: basic valid frames", UVM_MEDIUM)
  repeat (1) send_valid_frame();

  // ---------------------------------------------------------------
  // Iteration 2: Boundary — minimum and maximum payload sizes.
  // Exercises the payload/fcs boundary at both ends of the legal range.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "RX_VALID_FRAME_001 iteration 2: boundary — min/max payloads", UVM_MEDIUM)
  send_valid_frame(46);    // minimum
  send_valid_frame(47);    // one above minimum
  send_valid_frame(64);    // single-beat boundary
  send_valid_frame(500);   // mid-range
  send_valid_frame(1499);  // one below maximum
  send_valid_frame(1500);  // maximum standard frame
  send_valid_frame(46);    // repeat minimum

  // ---------------------------------------------------------------
  // Iteration 3: Pattern/Sequence — deterministic payload patterns.
  // Exercises data integrity across various bit-level patterns.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "RX_VALID_FRAME_001 iteration 3: payload patterns", UVM_MEDIUM)
  // Zero payload
  send_valid_frame_with_pattern(46, mac_hvl_utils_c::PAYLOAD_ZERO);
  send_valid_frame_with_pattern(1500, mac_hvl_utils_c::PAYLOAD_ZERO);

  // All-ones payload
  send_valid_frame_with_pattern(46, mac_hvl_utils_c::PAYLOAD_ONES);

  // Alternating 0x55/0xAA
  send_valid_frame_with_pattern(46, mac_hvl_utils_c::PAYLOAD_ALT_55_AA);

  // Alternating 0xAA/0x55
  send_valid_frame_with_pattern(46, mac_hvl_utils_c::PAYLOAD_ALT_AA_55);

  // Incrementing
  send_valid_frame_with_pattern(46, mac_hvl_utils_c::PAYLOAD_INCREMENTING);

  // Decrementing
  send_valid_frame_with_pattern(46, mac_hvl_utils_c::PAYLOAD_DECREMENTING);

  // Random (deterministic seed)
  send_valid_frame_with_pattern(46, mac_hvl_utils_c::PAYLOAD_RANDOM, 32'hDEAD);
  send_valid_frame_with_pattern(1500, mac_hvl_utils_c::PAYLOAD_RANDOM, 32'hBEEF);

  // Back-to-back valid frames (rapid fire, minimum IFG)
  `uvm_info(get_type_name(), "RX_VALID_FRAME_001 iteration 3: back-to-back valid frames", UVM_MEDIUM)
  send_back_to_back_valid(3);

  // ---------------------------------------------------------------
  // Additional Stimuli: Alternate legal payload start patterns after SFD.
  // Exercises the SFD-to-frame transition with various first-byte values.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "RX_VALID_FRAME_001: alternate payload start patterns", UVM_MEDIUM)
  send_valid_frame(46, 8'h00);
  send_valid_frame(46, 8'hFF);
  send_valid_frame(46, 8'hAA);
  send_valid_frame(46, 8'h55);
  send_valid_frame(46, 8'hEF);

  // ---------------------------------------------------------------
  // Additional Stimuli: One-byte preamble/SFD shifts.
  // Left shift: 6x0x55 + 0xD5 (short preamble — should be rejected).
  // Right shift: 8x0x55 + 0xD5 (extra byte — should be rejected).
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "RX_VALID_FRAME_001: 1-byte preamble/SFD shifts", UVM_MEDIUM)
  send_short_preamble(6);   // left shift: 6 preamble bytes
  send_invalid_sfd(8'h55);  // right shift: extra 0x55 where SFD should be

  // ---------------------------------------------------------------
  // Additional Stimuli: Mixed valid and malformed back-to-back.
  // Alternates valid frames with malformed starts in rapid succession.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "RX_VALID_FRAME_001: mixed valid/invalid back-to-back", UVM_MEDIUM)
  send_mixed_valid_invalid(6);

  // ---------------------------------------------------------------
  // Additional Stimuli: Constrained-random byte-stream campaign.
  // ~75% valid frames, ~25% invalid (short preamble, bad SFD).
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "RX_VALID_FRAME_001: constrained-random byte-stream (30 frames)", UVM_MEDIUM)
  repeat (30) begin
    if ($urandom_range(0, 3) == 0)
      send_random_invalid_frame();
    else
      send_random_valid_frame();
  end

endtask

/**
 * @brief Drives one valid frame with standard preamble/SFD.
 *
 * @param payload_len Payload length in bytes; -1 randomizes within config bounds.
 * @param start_byte  First payload byte after SFD (default 0x00).
 * @param da          Destination MAC address (default broadcast).
 */
task rx_valid_frame_001_seq_c::send_valid_frame(int payload_len = -1,
                                                byte unsigned start_byte = 8'h00,
                                                bit [47:0] da = 48'hFF_FF_FF_FF_FF_FF);
  frame_xtn_c frm;
  frm = frame_xtn_c::type_id::create("frm");
  start_item(frm);
  if (!frm.randomize() with {
        preamble_len    == 7;
        sfd_present     == 1;
        preamble        == 56'h55_5555_5555_5555;
        sfd             == 8'hD5;
        dst_addr        == da;
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs      == 1;
        soft ether_type > 16'h0600;
        if (payload_len >= 0) payload.size() == payload_len;
        else payload.size() inside {[46 : 1500]};
        payload[0] == start_byte;
      }) begin
    `uvm_fatal(get_type_name(), "valid frame randomization failed")
  end
  finish_item(frm);
endtask

/**
 * @brief Drives one valid frame with a deterministic payload pattern.
 *
 * @param payload_len Exact payload length in bytes.
 * @param pattern     Payload pattern from mac_hvl_utils_c::payload_pattern_e.
 * @param seed        Random seed for PAYLOAD_RANDOM pattern.
 */
task rx_valid_frame_001_seq_c::send_valid_frame_with_pattern(
    int payload_len,
    mac_hvl_utils_c::payload_pattern_e pattern,
    int unsigned seed = 32'h1);
  frame_xtn_c frm;
  byte unsigned pat_payload[];
  frm = frame_xtn_c::type_id::create("frm");
  // Generate the deterministic payload pattern.
  if (!mac_hvl_utils_c::make_payload(pat_payload, payload_len, pattern, seed)) begin
    `uvm_fatal(get_type_name(), $sformatf("make_payload failed for pattern %s",
                                          pattern.name()))
  end
  start_item(frm);
  if (!frm.randomize() with {
        preamble_len    == 7;
        sfd_present     == 1;
        preamble        == 56'h55_5555_5555_5555;
        sfd             == 8'hD5;
        dst_addr        == 48'hFF_FF_FF_FF_FF_FF;
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs      == 1;
        soft ether_type > 16'h0600;
        payload.size() == payload_len;
      }) begin
    `uvm_fatal(get_type_name(), "pattern frame randomization failed")
  end
  // Override payload with deterministic pattern.
  frm.payload = new[payload_len];
  foreach (frm.payload[i]) frm.payload[i] = pat_payload[i];
  frm.fcs = frm.compute_fcs();
  finish_item(frm);
endtask

/**
 * @brief Drives count valid frames back-to-back at minimum IFG.
 *
 * @param count Number of frames to send.
 */
task rx_valid_frame_001_seq_c::send_back_to_back_valid(int count);
  repeat (count) send_valid_frame($urandom_range(46, 1500));
endtask

/**
 * @brief Drives a frame with a short (1-6 byte) preamble.
 *
 * @param preamble_bytes Number of valid 0x55 preamble bytes (< 7).
 */
task rx_valid_frame_001_seq_c::send_short_preamble(int preamble_bytes);
  frame_xtn_c frm;
  frm = frame_xtn_c::type_id::create("frm");
  start_item(frm);
  if (!frm.randomize() with {
        preamble_len inside {[1 : 6]};
        preamble_len == preamble_bytes;
        sfd_present  == 1;
        preamble     == 56'h55_5555_5555_5555;
        sfd          == 8'hD5;
        dst_addr     == 48'hFF_FF_FF_FF_FF_FF;
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs      == 1;
        soft ether_type > 16'h0600;
        payload.size() inside {[46 : 1500]};
      }) begin
    `uvm_fatal(get_type_name(), "short preamble randomization failed")
  end
  finish_item(frm);
endtask

/**
 * @brief Drives a frame with 7x0x55 preamble and an invalid SFD value.
 *
 * @param bad_sfd The invalid SFD byte to inject.
 */
task rx_valid_frame_001_seq_c::send_invalid_sfd(byte unsigned bad_sfd);
  frame_xtn_c frm;
  frm = frame_xtn_c::type_id::create("frm");
  start_item(frm);
  if (!frm.randomize() with {
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs      == 1;
        soft ether_type > 16'h0600;
        payload.size() inside {[46 : 1500]};
      }) begin
    `uvm_fatal(get_type_name(), "invalid SFD base randomization failed")
  end
  frm.preamble_len = 7;
  frm.sfd_present  = 1;
  frm.preamble     = 56'h55_5555_5555_5555;
  frm.sfd          = bad_sfd;
  finish_item(frm);
endtask

/**
 * @brief Drives alternating valid and malformed frames back-to-back.
 *
 * @param count Total number of frames (valid + invalid pairs).
 */
task rx_valid_frame_001_seq_c::send_mixed_valid_invalid(int count);
  repeat (count) begin
    if ($urandom_range(0, 1))
      send_valid_frame();
    else
      send_short_preamble($urandom_range(1, 6));
  end
endtask

/**
 * @brief Drives one constrained-random valid frame.
 */
task rx_valid_frame_001_seq_c::send_random_valid_frame();
  frame_xtn_c frm;
  frm = frame_xtn_c::type_id::create("frm");
  start_item(frm);
  if (!frm.randomize() with {
        preamble_len    == 7;
        sfd_present     == 1;
        preamble        == 56'h55_5555_5555_5555;
        sfd             == 8'hD5;
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs      == 1;
        payload.size() inside {[46 : 1500]};
        soft ether_type > 16'h0600;
      }) begin
    `uvm_fatal(get_type_name(), "random valid frame randomization failed")
  end
  finish_item(frm);
endtask

/**
 * @brief Drives one constrained-random invalid frame.
 *
 * Randomizes preamble length, SFD value, corrupted bytes, and
 * combinations thereof to produce a mix of invalid starts.
 */
task rx_valid_frame_001_seq_c::send_random_invalid_frame();
  frame_xtn_c frm;
  bit [2:0] scenario;
  scenario = $urandom_range(0, 3);
  frm = frame_xtn_c::type_id::create("frm");
  start_item(frm);
  case (scenario)
    0: begin  // short preamble
      if (!frm.randomize() with {
            preamble_len inside {[1 : 6]};
            sfd_present  == 1;
            preamble     == 56'h55_5555_5555_5555;
            sfd          == 8'hD5;
            crc_error       == 0;
            length_error    == 0;
            alignment_error == 0;
            insert_fcs      == 1;
            soft ether_type > 16'h0600;
            payload.size() inside {[46 : 1500]};
          }) begin
        `uvm_fatal(get_type_name(), "random invalid short preamble failed")
      end
    end
    1: begin  // invalid SFD
      if (!frm.randomize() with {
            crc_error       == 0;
            length_error    == 0;
            alignment_error == 0;
            insert_fcs      == 1;
            soft ether_type > 16'h0600;
            payload.size() inside {[46 : 1500]};
          }) begin
        `uvm_fatal(get_type_name(), "random invalid SFD base randomization failed")
      end
      frm.preamble_len = 7;
      frm.sfd_present  = 1;
      frm.preamble     = 56'h55_5555_5555_5555;
      frm.sfd          = $urandom_range(0, 255) == 8'hD5 ? 8'hD6 : $urandom_range(0, 255);
    end
    2: begin  // missing SFD
      if (!frm.randomize() with {
            preamble_len == 7;
            sfd_present  == 0;
            preamble     == 56'h55_5555_5555_5555;
            crc_error       == 0;
            length_error    == 0;
            alignment_error == 0;
            insert_fcs      == 1;
            soft ether_type > 16'h0600;
            payload.size() inside {[46 : 1500]};
          }) begin
        `uvm_fatal(get_type_name(), "random missing SFD failed")
      end
    end
    default: begin  // zero preamble
      if (!frm.randomize() with {
            preamble_len == 0;
            sfd_present  == 1;
            sfd          == 8'hD5;
            crc_error       == 0;
            length_error    == 0;
            alignment_error == 0;
            insert_fcs      == 1;
            soft ether_type > 16'h0600;
            payload.size() inside {[46 : 1500]};
          }) begin
        `uvm_fatal(get_type_name(), "random zero preamble failed")
      end
    end
  endcase
  finish_item(frm);
endtask
