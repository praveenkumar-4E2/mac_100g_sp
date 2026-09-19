// Reusable directed RX traffic for MAC-APB-002.  frame_octets includes the
// Ethernet DA..FCS span; the sequence derives the payload length so callers
// express the same limits that REG_MAX_FRAME_SIZE implements.
class apb_002_rx_frame_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(apb_002_rx_frame_sequence_c)

  typedef mac_hvl_utils_c::payload_pattern_e payload_pattern_e;

  int unsigned frame_octets = MAC_STANDARD_FRAME_OCTETS;
  bit [47:0] destination    = 48'hff_ff_ff_ff_ff_ff;
  payload_pattern_e payload_pattern = mac_hvl_utils_c::PAYLOAD_RANDOM;
  int unsigned payload_seed = 32'h0020_0002;

  extern function new(string name = "apb_002_rx_frame_sequence_c");
  extern task body();
endclass

function apb_002_rx_frame_sequence_c::new(string name = "apb_002_rx_frame_sequence_c");
  super.new(name);
endfunction

task apb_002_rx_frame_sequence_c::body();
  frame_xtn_c frame_h;
  int unsigned payload_octets;

  if (frame_octets < (RS_HDR_BYTES + RS_FCS_BYTES + 46))
    `uvm_fatal("APB_002_FRAME", $sformatf("Illegal frame size %0d", frame_octets))
  payload_octets = frame_octets - RS_HDR_BYTES - RS_FCS_BYTES;
  frame_h = frame_xtn_c::type_id::create("apb_002_rx_frame");
  if (!frame_h.randomize() with {
        dst_addr == destination;
        ether_type == 16'h0800;
        payload.size() == payload_octets;
        insert_fcs == 1'b1;
        crc_error == 1'b0;
        length_error == 1'b0;
        alignment_error == 1'b0;
      })
    `uvm_fatal("APB_002_FRAME", "Frame randomization failed")

  if (!mac_hvl_utils_c::make_payload(frame_h.payload, payload_octets, payload_pattern, payload_seed))
    `uvm_fatal("APB_002_FRAME", "Unsupported payload pattern")
  // Payload was modified after post_randomize(), so regenerate the valid FCS.
  frame_h.fcs = frame_h.compute_fcs();
  do_rs_frame(frame_h);
endtask
