/**
 * @brief Canonical Ethernet frame class (mac_test_pkg member).
 *
 * `mac_frame_c` is the neutral, protocol-agnostic frame representation
 * produced by the codecs from either an AXI captured byte stream or an RS
 * captured wire-byte stream, and consumed by the scoreboard/ref-model for
 * comparison. It is package-private (declared inside mac_test_pkg via this
 * include, located in src/hvl_top/common/); no agent owns it.
 *
 * Byte-order contract:
 *  - DA/SA/EtherType are big-endian wire order (first byte on the wire is
 *    the MSB) — matches mac_hvl_utils_c::encode_be48/encode_be16;
 *  - payload[0] is the first payload byte on the wire;
 *  - fcs is the 32-bit LSB-first CRC value (mac_hvl_utils_c FCS helpers);
 *    fcs_present distinguishes a captured FCS from an absent one.
 *
 * This file is a member of mac_test_pkg (text-included), so it must NOT
 * declare `package`/`endpackage`. UTL-052 adds the metadata fields;
 * UTL-053 implements do_copy/do_compare/convert2string.
 */
class mac_frame_c extends uvm_sequence_item;
  `uvm_object_utils(mac_frame_c)

  // Ethernet header (big-endian wire order)
  rand bit                [47:0] da;  // destination MAC address
  rand bit                [47:0] sa;  // source MAC address
  rand bit                [15:0] ether_type;  // EtherType / length field

  // Payload (canonical byte order, index 0 first on the wire)
  rand byte unsigned             payload                                         [];

  // FCS (LSB-first 32-bit CRC value; fcs_present marks an absent FCS)
  rand bit                [31:0] fcs;
  rand bit                       fcs_present;

  // Direction of capture/production: which MAC data-path point produced (or
  // consumes) this frame (mac_hvl_types.svh).
  rand mac_frame_dir_e           direction;

  // Outcome after DUT processing: consolidates CRC/length/alignment/drop
  // (mac_hvl_types.svh).
  rand mac_frame_result_e        result;

  // Beat metadata (from the capturing AXI/RS interface)
  rand bit                       sop;  // start-of-packet beat marker
  rand bit                       eop;  // end-of-packet beat marker
  rand int unsigned              eop_byte_count;  // valid bytes in the EOP beat

  // Line-side metadata (RS directions only; unset for AXI directions)
  rand bit                       preamble_present;  // 7 x 0x55 preamble captured
  rand bit                [ 7:0] sfd;  // SFD byte value (0xD5)

  extern function new(string name = "mac_frame_c");
  extern function void do_copy(uvm_object rhs);
  extern function bit do_compare(uvm_object rhs, uvm_comparer comparer);
  extern function string convert2string();
endclass

/**
 * @brief Constructor for the canonical frame.
 *
 * @param name Name of the transaction object.
 */
function mac_frame_c::new(string name = "mac_frame_c");
  super.new(name);
endfunction

/**
 * @brief Deep-copies all canonical frame fields.
 *
 * The payload array is allocated fresh and copied byte-by-byte so the
 * cloned object never aliases the source object's payload storage.
 *
 * @param rhs Source object.
 */
function void mac_frame_c::do_copy(uvm_object rhs);
  mac_frame_c rhs_h;
  if (!$cast(rhs_h, rhs)) begin
    `uvm_fatal("TYPE_MISMATCH", $sformatf("do_copy: %s is not a mac_frame_c", rhs.get_type_name()))
  end
  super.do_copy(rhs);
  da         = rhs_h.da;
  sa         = rhs_h.sa;
  ether_type = rhs_h.ether_type;
  payload    = new[rhs_h.payload.size()];
  foreach (payload[i]) payload[i] = rhs_h.payload[i];
  fcs              = rhs_h.fcs;
  fcs_present      = rhs_h.fcs_present;
  direction        = rhs_h.direction;
  result           = rhs_h.result;
  sop              = rhs_h.sop;
  eop              = rhs_h.eop;
  eop_byte_count   = rhs_h.eop_byte_count;
  preamble_present = rhs_h.preamble_present;
  sfd              = rhs_h.sfd;
endfunction

/**
 * @brief Compares all canonical frame fields, byte-by-byte payload.
 *
 * @param rhs      Object to compare against.
 * @param comparer UVM comparer policy.
 * @return 1 on full match, 0 otherwise.
 */
function bit mac_frame_c::do_compare(uvm_object rhs, uvm_comparer comparer);
  mac_frame_c rhs_h;
  if (!super.do_compare(rhs, comparer)) return 0;
  if (!$cast(rhs_h, rhs)) return 0;
  if (da !== rhs_h.da || sa !== rhs_h.sa || ether_type !== rhs_h.ether_type || fcs !== rhs_h.fcs ||
      fcs_present !== rhs_h.fcs_present || direction !== rhs_h.direction ||
      result !== rhs_h.result || sop !== rhs_h.sop || eop !== rhs_h.eop ||
      eop_byte_count !== rhs_h.eop_byte_count || preamble_present !== rhs_h.preamble_present ||
      sfd !== rhs_h.sfd || payload.size() != rhs_h.payload.size())
    return 0;
  foreach (payload[i]) if (payload[i] !== rhs_h.payload[i]) return 0;
  return 1;
endfunction

/**
 * @brief Returns a one-line string summary of the canonical frame.
 *
 * @return Formatted summary.
 */
function string mac_frame_c::convert2string();
  return {
    $sformatf(
        "DIR=%s RES=%s DA=%h SA=%h ET=%h FCS=%h FCS_ON=%0b ",
        direction.name(),
        result.name(),
        da,
        sa,
        ether_type,
        fcs,
        fcs_present
    ),
    $sformatf(
        "PLEN=%0d SOP=%0b EOP=%0b EOP_BYTES=%0d PRE=%0b SFD=%h",
        payload.size(),
        sop,
        eop,
        eop_byte_count,
        preamble_present,
        sfd
    )
  };
endfunction
