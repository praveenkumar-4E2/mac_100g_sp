/**
 * @brief Canonical frame codec (mac_test_pkg member).
 *
 * `mac_frame_codec_c` is the single source of truth for converting between
 * captured AXI / RS byte streams and the canonical `mac_frame_c` frame
 * representation. It is stateless and package-private (declared inside
 * mac_test_pkg via this include, located in src/hvl_top/common/); the
 * protected constructor prevents instantiation because every member is
 * static.
 *
 * Contract (per skills/utilities/proposal.md):
 *  - methods return success/error information (0 = ok, -1 = malformed input);
 *    they never issue uvm_error themselves — monitors decide report context;
 *  - the codec explicitly distinguishes:
 *    + RS wire frames include preamble/SFD; AXI streams never do;
 *    + generated (DUT-inserted) versus client-supplied FCS via
 *      `mac_frame_c::fcs_present`;
 *    + big-endian Ethernet header fields versus LSB-first FCS octets
 *      (mac_hvl_utils_c encode/decode helpers);
 *    + `tkeep`/`frame_end_byte_index` valid-lane counts versus flat byte-array length;
 *    + frame error/drop status (`mac_frame_result_e`) versus the AXI
 *      tuser sideband contract (tuser[0] = error, tuser[1] = fcs_present).
 *
 * This file is a member of mac_test_pkg (text-included), so it must NOT
 * declare `package`/`endpackage`. UTL-055 declares the API; UTL-056/059/
 * 061/063 implement the bodies.
 */
`ifndef MAC_FRAME_CODEC_SVH
`define MAC_FRAME_CODEC_SVH

class mac_frame_codec_c;
  protected
  function new();
  endfunction

  // AXI captured-byte stream + final-beat sideband -> canonical frame.
  // frame_q is the captured AXI bytes in wire order (no preamble/SFD);
  // tuser[1] = fcs_present, tuser[0] = error; eop_byte_count is the valid
  // byte count of the final beat (tkeep); direction is AXI_TX or AXI_RX;
  // eth_len_bound is the length/type discrimination bound (0 disables the
  // length check). Returns 0 on success, -1 on malformed input.
  extern static function int axi_to_frame(
      byte unsigned frame_q[$], input bit [7:0] tuser, input int unsigned eop_byte_count,
      input mac_frame_dir_e direction, input int unsigned eth_len_bound, output mac_frame_c frame);

  // RS captured wire-byte stream + final metadata -> canonical frame.
  // wire_q is the captured wire bytes (preamble/SFD/DA/SA/ET/payload[/FCS]);
  // eop_byte_count is the valid byte count of the final beat (frame_end_byte_index);
  // last_err / last_fcs are the final-beat wire error / fcs_present flags;
  // direction is RS_TX or RS_RX. Returns 0 on success, -1 on malformed.
  extern static function int rs_to_frame(
      byte unsigned wire_q[$], input int unsigned eop_byte_count, input bit last_err,
      input bit last_fcs, input mac_frame_dir_e direction, input int unsigned eth_len_bound,
      output mac_frame_c frame);

  // Canonical frame -> AXI byte queue (wire order, no preamble/SFD).
  // Emits DA/SA/ET/payload and, when frame.fcs_present, the 4 LSB-first
  // FCS bytes. Returns 0 on success, -1 on invalid frame.
  extern static function int frame_to_axi(mac_frame_c frame, output byte unsigned axi_q[$]);

  // Canonical frame -> RS wire byte queue (wire order with preamble/SFD).
  // Emits 7 x 0x55 + SFD + DA/SA/ET/payload and, when frame.fcs_present,
  // the 4 LSB-first FCS bytes. Returns 0 on success, -1 on invalid frame.
  extern static function int frame_to_rs(mac_frame_c frame, output byte unsigned wire_q[$]);
endclass

// Placeholder bodies; implemented by UTL-056/059/061/063.
function int mac_frame_codec_c::axi_to_frame(
    byte unsigned frame_q[$], input bit [7:0] tuser, input int unsigned eop_byte_count,
    input mac_frame_dir_e direction, input int unsigned eth_len_bound, output mac_frame_c frame);
  byte unsigned work[$];
  bit fcs_present;
  bit error_flag;
  int nbytes;
  int n_payload;

  fcs_present = tuser[AXI_TUSER_FCS_PRESENT_BIT];
  error_flag  = tuser[AXI_TUSER_ERROR_BIT];
  nbytes      = frame_q.size();

  // AXI frames never carry preamble/SFD; a bare header is the minimum.
  if (nbytes < RS_HDR_BYTES) return -1;
  n_payload = nbytes - RS_HDR_BYTES - (fcs_present ? RS_FCS_BYTES : 0);
  if (n_payload < 0) return -1;

  frame = mac_frame_c::type_id::create("frame");

  // Header fields are big-endian on the wire; decode off a working copy so
  // the caller's queue is untouched.
  work  = frame_q;
  void'(mac_hvl_utils_c::decode_be48(work, frame.da));
  void'(mac_hvl_utils_c::decode_be48(work, frame.sa));
  void'(mac_hvl_utils_c::decode_be16(work, frame.ether_type));

  frame.payload = new[n_payload];
  foreach (frame.payload[i]) frame.payload[i] = frame_q[RS_HDR_BYTES+i];

  // FCS (client-supplied) is LSB-first on the wire.
  frame.fcs_present = fcs_present;
  if (fcs_present) begin
    work.delete();
    for (int i = 0; i < RS_FCS_BYTES; i++) work.push_back(frame_q[nbytes-RS_FCS_BYTES+i]);
    void'(mac_hvl_utils_c::wire_bytes_to_fcs(work, frame.fcs));
  end else begin
    frame.fcs = '0;
  end

  // AXI status comes from the tuser sideband (error bit -> CRC error);
  // length/alignment are not transported on AXI. The tkeep valid-lane
  // count of the final beat is recorded as EOP metadata.
  frame.direction        = direction;
  frame.result           = error_flag ? MAC_FRAME_RESULT_CRC_ERROR : MAC_FRAME_RESULT_CLEAN;
  frame.sop              = 1'b1;
  frame.eop              = 1'b1;
  frame.eop_byte_count   = eop_byte_count;
  frame.preamble_present = 1'b0;
  frame.sfd              = 8'h00;
  return 0;
endfunction

function int mac_frame_codec_c::rs_to_frame(
    byte unsigned wire_q[$], input int unsigned eop_byte_count, input bit last_err,
    input bit last_fcs, input mac_frame_dir_e direction, input int unsigned eth_len_bound,
    output mac_frame_c frame);
  byte unsigned work[$];
  int n;
  int pld_len;
  bit crc_error;
  bit length_error;

  n = wire_q.size();
  // Minimum RS frame: preamble + SFD + header, with an optional FCS.
  if (n < RS_MIN_FRAME_BYTES) return -1;
  pld_len = n - RS_MIN_FRAME_BYTES - (last_fcs ? RS_FCS_BYTES : 0);
  if (pld_len < 0) return -1;

  frame                  = mac_frame_c::type_id::create("frame");

  // Preamble/SFD are captured line-side fields, not canonical header/
  // payload content; they are recorded as line-side metadata only.
  frame.preamble_present = 1'b1;
  frame.sfd              = wire_q[RS_PREAMBLE_BYTES];

  // Header fields are big-endian on the wire, following the preamble/SFD.
  work                   = wire_q;
  for (int i = 0; i < RS_PREAMBLE_SFD_BYTES; i++) void'(work.pop_front());
  void'(mac_hvl_utils_c::decode_be48(work, frame.da));
  void'(mac_hvl_utils_c::decode_be48(work, frame.sa));
  void'(mac_hvl_utils_c::decode_be16(work, frame.ether_type));

  frame.payload = new[pld_len];
  foreach (frame.payload[i]) frame.payload[i] = wire_q[RS_MIN_FRAME_BYTES+i];

  // FCS (generated by the DUT) is LSB-first on the wire.
  frame.fcs_present = last_fcs;
  if (last_fcs) begin
    work.delete();
    for (int i = 0; i < RS_FCS_BYTES; i++) work.push_back(wire_q[n-RS_FCS_BYTES+i]);
    void'(mac_hvl_utils_c::wire_bytes_to_fcs(work, frame.fcs));
  end else begin
    frame.fcs = '0;
  end

  // Frame status derived from the wire (generated FCS) — unlike AXI, the
  // error classification is computed here, not taken from a sideband.
  work.delete();
  void'(mac_hvl_utils_c::encode_be48(work, frame.da));
  void'(mac_hvl_utils_c::encode_be48(work, frame.sa));
  void'(mac_hvl_utils_c::encode_be16(work, frame.ether_type));
  foreach (frame.payload[i]) work.push_back(frame.payload[i]);
  crc_error = last_fcs && (mac_hvl_utils_c::compute_fcs32(work) != frame.fcs);
  length_error = (eth_len_bound > 0) && (frame.ether_type < eth_len_bound) &&
      (frame.ether_type != pld_len);

  frame.direction = direction;
  frame.result = crc_error ? MAC_FRAME_RESULT_CRC_ERROR :
      length_error ? MAC_FRAME_RESULT_LENGTH_ERROR :
      last_err ? MAC_FRAME_RESULT_ALIGNMENT_ERROR : MAC_FRAME_RESULT_CLEAN;
  frame.sop = 1'b1;
  frame.eop = 1'b1;
  frame.eop_byte_count = eop_byte_count;
  return 0;
endfunction

function int mac_frame_codec_c::frame_to_axi(mac_frame_c frame, output byte unsigned axi_q[$]);
  if (frame == null) return -1;
  axi_q.delete();
  // Header fields big-endian; AXI streams never carry preamble/SFD.
  void'(mac_hvl_utils_c::encode_be48(axi_q, frame.da));
  void'(mac_hvl_utils_c::encode_be48(axi_q, frame.sa));
  void'(mac_hvl_utils_c::encode_be16(axi_q, frame.ether_type));
  foreach (frame.payload[i]) axi_q.push_back(frame.payload[i]);
  // Client-supplied FCS (fcs_present) is emitted LSB-first.
  if (frame.fcs_present) void'(mac_hvl_utils_c::fcs_to_wire_bytes(axi_q, frame.fcs));
  return 0;
endfunction

function int mac_frame_codec_c::frame_to_rs(mac_frame_c frame, output byte unsigned wire_q[$]);
  if (frame == null) return -1;
  wire_q.delete();
  // RS wire carries the preamble and SFD before the big-endian header.
  for (int i = 0; i < 7; i++) wire_q.push_back(8'h55);
  wire_q.push_back(8'hD5);
  void'(mac_hvl_utils_c::encode_be48(wire_q, frame.da));
  void'(mac_hvl_utils_c::encode_be48(wire_q, frame.sa));
  void'(mac_hvl_utils_c::encode_be16(wire_q, frame.ether_type));
  foreach (frame.payload[i]) wire_q.push_back(frame.payload[i]);
  // Client-supplied FCS (fcs_present) is emitted LSB-first.
  if (frame.fcs_present) void'(mac_hvl_utils_c::fcs_to_wire_bytes(wire_q, frame.fcs));
  return 0;
endfunction

`endif  // MAC_FRAME_CODEC_SVH
