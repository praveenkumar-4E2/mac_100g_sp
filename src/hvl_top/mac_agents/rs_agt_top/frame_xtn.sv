/**
 * @brief MAC RS RX (line-side) Frame Transaction.
 *
 * Models the complete Ethernet frame as driven on the native
 * MAC/RS stream interface (mac_rs_stream_if.sv): preamble (7 x 0x55),
 * SFD (0xD5), DA/SA/EtherType header, payload, and FCS.
 *
 * The RS driver serializes this item into 512-bit beats with
 * keep/frame_end_byte_index; the MAC RX path strips preamble/SFD in
 * rx_preamble_detect and checks the FCS.
 */
class frame_xtn_c extends uvm_sequence_item;
  `uvm_object_utils(frame_xtn_c)

  //preamble/sfd control
  rand int unsigned	 preamble_len;
  rand bit 		 sfd_present;	

  // Trace identifier assigned at generation or monitor reconstruction.
  int unsigned               packet_id;
  static int unsigned        next_packet_id            = 1;

  // Line-side preamble/SFD (driven at beat offset 0)
  rand bit            [55:0] preamble;  // 7 x 0x55
  rand bit            [ 7:0] sfd;  // 0xD5

  // Ethernet Header
  rand bit            [47:0] dst_addr;  // DA
  rand bit            [47:0] src_addr;  // SA
  rand bit            [15:0] ether_type;

  // Payload
  rand byte unsigned         payload               [];

  // FCS
  rand bit            [31:0] fcs;
  rand bit                   insert_fcs;

  // Deliberate octets serialized after the FCS.  This is invalid Ethernet
  // framing, retained only for negative RX tests which must verify that a
  // valid FCS followed by extra data is rejected.
  byte unsigned              trailing_bytes[];

  // Error Injection
  rand bit                   crc_error;
  rand bit                   length_error;
  rand bit                   alignment_error;

  constraint c_preamble_len {
	  preamble_len inside {[0:7]};
	  }

  constraint c_sfd_present {
	  soft sfd_present == 1;
	  }

  // Preamble and SFD are fixed by IEEE 802.3; kept as rand
  // fields so the monitor can extract/verify them from the
  // line, and future line-error injection (e.g., bad SFD)
  // remains possible.
  constraint c_preamble_sfd {
    preamble == 56'h55_5555_5555_5555;
    sfd == 8'hD5;
  }

  // Bounds the payload to a legal Ethernet frame payload length:
  // 46 bytes (minimum frame size, 64 B incl. header + FCS) to
  // Basic, jumbo, and super-jumbo payloads are legal. The active sequence
  // profile selects a narrower range through its agent configuration.
  constraint c_payload_size {payload.size() inside {[46 : MAC_SUPER_JUMBO_PAYLOAD_BYTES]};}

  // Weighted error injection: the DUT is mostly driven with
  // clean frames, with rare single-error frames to exercise the
  // error detection paths. Weights are roughly 10%/5%/3%.
  constraint c_error_injection {
    crc_error dist {
      0 := 90,
      1 := 10
    };
    length_error dist {
      0 := 95,
      1 := 5
    };
    alignment_error dist {
      0 := 97,
      1 := 3
    };
  }

  // Most frames carry an FCS (90%); frames with insert_fcs == 0
  // are driven without FCS to cover that path. The actual FCS
  // value is computed in post_randomize(), not constrained here,
  // because constraint solving cannot see the finalized payload.
  constraint c_fcs {
    insert_fcs dist {
      1 := 90,
      0 := 10
    };
  }

  // Compute the CRC-32 FCS after randomization so it always
  // matches the random header + payload. If crc_error is set,
  // the computed FCS is deliberately NOT applied, leaving a
  // random (wrong) FCS to inject a CRC error. Frames without
  // an FCS field carry fcs = 0. The preamble/SFD are not
  // FCS-covered per IEEE 802.3.
  function void post_randomize();
    if (packet_id == 0) packet_id = next_packet_id++;
    if (!insert_fcs) fcs = '0;
    else if (!crc_error) fcs = compute_fcs();
  endfunction

  extern function new(string name = "frame_xtn_c");
  extern function void do_copy(uvm_object rhs);
  extern function bit do_compare(uvm_object rhs, uvm_comparer comparer);
  extern function void do_print(uvm_printer printer);
  extern function string convert2string();
  extern function bit [31:0] compute_fcs();
endclass

/**
 * @brief Constructor for the MAC RS RX frame transaction.
 *
 * Initializes the transaction object by calling the parent
 * class constructor.
 *
 * @param name Name of the transaction object.
 */
function frame_xtn_c::new(string name = "frame_xtn_c");
  super.new(name);
endfunction

/**
 * @brief Deep-copies all transaction fields.
 *
 * @param rhs Source transaction object.
 */
function void frame_xtn_c::do_copy(uvm_object rhs);
  frame_xtn_c rhs_h;
  if (!$cast(rhs_h, rhs)) begin
    `uvm_fatal("TYPE_MISMATCH", $sformatf("do_copy: %s is not a frame_xtn_c", rhs.get_type_name()))
  end
  super.do_copy(rhs);
  preamble   = rhs_h.preamble;
  packet_id  = rhs_h.packet_id;
  preamble_len=rhs_h.preamble_len;
  sfd        = rhs_h.sfd;
  dst_addr   = rhs_h.dst_addr;
  src_addr   = rhs_h.src_addr;
  ether_type = rhs_h.ether_type;
  payload    = new[rhs_h.payload.size()];
  foreach (payload[i]) payload[i] = rhs_h.payload[i];
  trailing_bytes = new[rhs_h.trailing_bytes.size()];
  foreach (trailing_bytes[i]) trailing_bytes[i] = rhs_h.trailing_bytes[i];
  fcs             = rhs_h.fcs;
  insert_fcs      = rhs_h.insert_fcs;
  crc_error       = rhs_h.crc_error;
  length_error    = rhs_h.length_error;
  alignment_error = rhs_h.alignment_error;
endfunction

/**
 * @brief Compares all transaction fields.
 *
 * @param rhs       Transaction to compare against.
 * @param comparer  UVM comparer policy.
 * @return 1 on full match, 0 otherwise.
 */
function bit frame_xtn_c::do_compare(uvm_object rhs, uvm_comparer comparer);
  frame_xtn_c rhs_h;
  if (!super.do_compare(rhs, comparer)) return 0;
  if (!$cast(rhs_h, rhs)) return 0;
  // packet_id identifies a monitor transaction; it is not an Ethernet
  // on-wire field and independently generated expected items have no reason
  // to share the monitor's sequence number.
  if (preamble_len !== rhs_h.preamble_len || sfd_present !== rhs_h.sfd_present ||
      preamble !== rhs_h.preamble || sfd !== rhs_h.sfd ||
      dst_addr !== rhs_h.dst_addr || src_addr !== rhs_h.src_addr ||
      ether_type !== rhs_h.ether_type || fcs !== rhs_h.fcs || insert_fcs !== rhs_h.insert_fcs ||
      crc_error !== rhs_h.crc_error || length_error !== rhs_h.length_error ||
      alignment_error !== rhs_h.alignment_error || payload.size() != rhs_h.payload.size())
    return 0;
  foreach (payload[i]) if (payload[i] !== rhs_h.payload[i]) return 0;
  return 1;
endfunction

/**
 * @brief Prints all transaction fields via the UVM printer.
 *
 * @param printer UVM printer instance.
 */
function void frame_xtn_c::do_print(uvm_printer printer);
  super.do_print(printer);
  printer.print_field("packet_id", packet_id, 32, UVM_DEC);
  printer.print_field("preamble_len", preamble_len, 32 ,UVM_DEC);
  printer.print_field("sfd_present", sfd_present, 1, UVM_BIN);
  printer.print_field("preamble", preamble, 56, UVM_HEX);
  printer.print_field("sfd", sfd, 8, UVM_HEX);
  printer.print_field("dst_addr", dst_addr, 48, UVM_HEX);
  printer.print_field("src_addr", src_addr, 48, UVM_HEX);
  printer.print_field("ether_type", ether_type, 16, UVM_HEX);
  printer.print_field("fcs", fcs, 32, UVM_HEX);
  printer.print_field("insert_fcs", insert_fcs, 1, UVM_BIN);
  printer.print_field("crc_error", crc_error, 1, UVM_BIN);
  printer.print_field("length_error", length_error, 1, UVM_BIN);
  printer.print_field("alignment_error", alignment_error, 1, UVM_BIN);
  printer.print_array_header("payload", payload.size(), "byte unsigned", "%0d");
  foreach (payload[i]) printer.print_field($sformatf("[%0d]", i), payload[i], 8, UVM_HEX);
  printer.print_array_footer(payload.size());
  printer.print_array_header("trailing_bytes", trailing_bytes.size(), "byte unsigned", "%0d");
  foreach (trailing_bytes[i])
    printer.print_field($sformatf("trailing_bytes[%0d]", i), trailing_bytes[i], 8, UVM_HEX);
  printer.print_array_footer(trailing_bytes.size());
endfunction

/**
 * @brief Returns a one-line string summary of the transaction.
 *
 * @return Formatted transaction summary.
 */
function string frame_xtn_c::convert2string();
  return {
    $sformatf(
        "PKT=%0d PRE=%h SFD=%h DA=%h SA=%h ET=%h FCS=%h PLEN=%0d TRAIL=%0d FCS_ON=%0b ",
        packet_id,
	preamble_len,
	sfd_present,
        preamble,
        sfd,
        dst_addr,
        src_addr,
        ether_type,
        fcs,
        payload.size(),
        trailing_bytes.size(),
        insert_fcs
    ),
    $sformatf("CRC_ERR=%0b LEN_ERR=%0b ALIGN_ERR=%0b", crc_error, length_error, alignment_error)
  };
endfunction

// Readable protocol-specific alias retained alongside the established factory type.
typedef frame_xtn_c mac_rs_frame_item_c;

/**
 * @brief Computes the IEEE 802.3 CRC-32 FCS over DA+SA+ET+payload.
 *
 * The preamble/SFD are not included, per IEEE 802.3.
 *
 * The algorithm is the LSB-first reflected CRC-32 (polynomial
 * 0xEDB88320, init 0xFFFFFFFF, final complement) used by the DUT
 * pure-Verilog reflected Ethernet CRC-32 implementation. The returned
 * value is the 32-bit FCS; the wire transmits its bytes LSB-first
 * (fcs[7:0] first), which makes the DUT RX residue check
 * (CRC32_RESIDUE = 0xDEBB20E3 over DA..FCS) pass.
 *
 * @return 32-bit FCS value.
 */
function automatic bit [31:0] frame_xtn_c::compute_fcs();
  byte unsigned bytes_q[];
  bit [31:0] crc = 'hFFFF_FFFF;
  bytes_q = new[14 + payload.size()];
  for (int i = 0; i < 6; i++) bytes_q[i] = dst_addr[47-8*i-:8];
  for (int i = 0; i < 6; i++) bytes_q[6+i] = src_addr[47-8*i-:8];
  bytes_q[12] = ether_type[15:8];
  bytes_q[13] = ether_type[7:0];
  foreach (payload[i]) bytes_q[14+i] = payload[i];
  foreach (bytes_q[i]) begin
    for (int b = 0; b < 8; b++) begin
      if (crc[0] ^ bytes_q[i][b]) crc = (crc >> 1) ^ 32'hEDB8_8320;
      else crc = crc >> 1;
    end
  end
  return ~crc;
endfunction
