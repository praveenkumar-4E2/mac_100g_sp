/**
 * @brief PF-001 variant PAUSE/control-frame builder.
 *
 * Builds one line-side control frame with every field independently
 * overridable: destination address, EtherType, opcode, pause quanta,
 * payload length (to create below-minimum-length frames), and FCS
 * correctness. Fields are assigned directly (not through randomize()), so
 * illegal combinations that frame_xtn_c's constraints would reject (e.g. a
 * payload shorter than 46 bytes) can still be driven deliberately for
 * negative testing.
 *
 * Defaults reproduce a basic valid PAUSE frame (PF-001 scenario 1); set
 * only the fields relevant to the scenario under test before start().
 */
class mac_pause_frame_variant_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_pause_frame_variant_sequence_c)

  bit [47:0] dst_addr_ovr   = 48'h01_80_C2_00_00_01;  // reserved PAUSE multicast
  bit [47:0] src_addr_ovr   = 48'h02_00_00_00_00_01;
  bit [15:0] ether_type_ovr = 16'h8808;
  bit [15:0] opcode_ovr     = 16'h0001;                // PAUSE opcode
  bit [15:0] pause_quanta   = 16'h0100;

  // Below RS_MIN_FRAME_BYTES-driven minimum (46) deliberately produces a
  // below-minimum-length control frame; below 4 is clamped since the
  // opcode+quanta fields need 4 bytes to remain well-formed.
  int        payload_octets = 46;

  // Deliberately invert the computed FCS to inject a CRC error while
  // leaving every other field legal.
  bit        corrupt_fcs    = 1'b0;

  extern function new(string name = "mac_pause_frame_variant_sequence_c");
  extern task body();
endclass

function mac_pause_frame_variant_sequence_c::new(string name =
                                                  "mac_pause_frame_variant_sequence_c");
  super.new(name);
endfunction

task mac_pause_frame_variant_sequence_c::body();
  frame_xtn_c  frm;
  int unsigned plen;

  plen = (payload_octets < 4) ? 4 : payload_octets;

  frm            = frame_xtn_c::type_id::create("frm");
  frm.dst_addr   = dst_addr_ovr;
  frm.src_addr   = src_addr_ovr;
  frm.ether_type = ether_type_ovr;
  frm.payload    = new[plen];
  frm.payload[0] = opcode_ovr[15:8];
  frm.payload[1] = opcode_ovr[7:0];
  frm.payload[2] = pause_quanta[15:8];
  frm.payload[3] = pause_quanta[7:0];
  for (int i = 4; i < plen; i++) frm.payload[i] = 8'h00;

  frm.insert_fcs      = 1'b1;
  frm.crc_error        = corrupt_fcs;
  frm.length_error     = 1'b0;
  frm.alignment_error  = 1'b0;
  frm.fcs              = corrupt_fcs ? ~frm.compute_fcs() : frm.compute_fcs();

  do_rs_frame(frm);
endtask

