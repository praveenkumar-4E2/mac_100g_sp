/**
 * @brief STAS-001 variant RX-side frame builder for interrupt-cause testing.
 *
 * Builds one line-side frame with every fault-relevant field independently
 * overridable: destination/source address, EtherType, control opcode,
 * payload length (to create oversize or below-minimum-length frames), FCS
 * correctness, and an explicit length/type inconsistency flag. Fields are
 * assigned directly (not through randomize()), mirroring
 * mac_pause_frame_variant_sequence_c, so illegal or fault combinations that
 * frame_xtn_c's constraints would otherwise reject can still be driven
 * deliberately for negative/fault testing.
 *
 * Defaults reproduce an ordinary good frame (no cause asserted); set only
 * the fields relevant to the cause under test before start().
 */
class mac_stats_variant_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_stats_variant_sequence_c)

  bit [47:0] dst_addr_ovr   = 48'h02_00_00_00_00_02;   // ordinary individual address
  bit [47:0] src_addr_ovr   = 48'h02_00_00_00_00_01;
  bit [15:0] ether_type_ovr = 16'h0800;                 // IPv4, non-control by default
  bit [15:0] opcode_ovr     = 16'h0001;                 // only meaningful when is_control=1

  bit        is_control     = 1'b0;                     // drives EtherType=0x8808 when set

  // Payload sizing. Default sits inside the legal 46-1500 client-data
  // range. Set above 1518-14-4=1500 client bytes to force RX oversize;
  // reducing below 4 is clamped since a control opcode+params frame needs
  // at least 4 payload bytes to remain well-formed.
  int        payload_octets = 46;

  // Fault-injection flags, applied directly on the built frame_xtn_c so
  // combinations frame_xtn_c's own constraints would reject can still be
  // driven for negative testing.
  bit        corrupt_fcs      = 1'b0;  // -> RX CRC error cause
  bit        force_invalid    = 1'b0;  // -> RX invalid cause (length/type inconsistency)

  extern function new(string name = "mac_stats_variant_sequence_c");
  extern task body();
endclass

function mac_stats_variant_sequence_c::new(string name = "mac_stats_variant_sequence_c");
  super.new(name);
endfunction

task mac_stats_variant_sequence_c::body();
  frame_xtn_c  frm;
  int unsigned plen;

  plen = (payload_octets < 4) ? 4 : payload_octets;

  frm            = frame_xtn_c::type_id::create("frm");
  frm.dst_addr   = dst_addr_ovr;
  frm.src_addr   = src_addr_ovr;
  frm.ether_type = is_control ? 16'h8808 : ether_type_ovr;
    if (is_control) frm.dst_addr = 48'h01_80_C2_00_00_01;  // MAC_CONTROL_DEST_ADDR, required by mac_control_top.is_control_frame
  frm.payload    = new[plen];

  if (is_control) begin
    frm.payload[0] = opcode_ovr[15:8];
    frm.payload[1] = opcode_ovr[7:0];
    for (int i = 2; i < plen; i++) frm.payload[i] = 8'h00;
  end else begin
    for (int i = 0; i < plen; i++) frm.payload[i] = 8'(i);
  end

  frm.insert_fcs      = 1'b1;
  frm.crc_error        = corrupt_fcs;
  frm.length_error     = force_invalid;
  frm.alignment_error  = 1'b0;
  frm.fcs              = corrupt_fcs ? ~frm.compute_fcs() : frm.compute_fcs();

  do_rs_frame(frm);
endtask

/**
 * @brief STAS-001 TX-side fault builder for the TX Error cause (TC07).
 *
 * Mirrors mac_stats_variant_sequence_c's direct-assignment style, driving
 * a normal AXI client item on the TX ingress side.
 *
 * KNOWN RTL/INTEGRATION BUG (confirmed, not a testbench issue):
 * src/rtl_verilog/integration/mac_core_v.v ties tx_error_event to a
 * constant 1b0 in its apb_regs instantiation, and no other signal in
 * that file drives tx_error_event from tx_path_error/egress_tx_mac_error.
 * As a result, TC07 cannot currently observe INT_TX_ERROR_BIT or
 * REG_TX_STATUS bit0 assert no matter what is driven here. This sequence
 * is written correctly against the intended behavior; TC07 is expected to
 * FAIL until mac_core_v.v wires a real tx_error_event source. Do not
 * modify this sequence or STAS_001.sv's TC07 checks to mask that failure.
 */
class mac_stats_tx_fault_sequence_c extends axi_sequence_base_c;
  `uvm_object_utils(mac_stats_tx_fault_sequence_c)

  int payload_octets = 46;

  extern function new(string name = "mac_stats_tx_fault_sequence_c");
  extern task body();
endclass

function mac_stats_tx_fault_sequence_c::new(string name = "mac_stats_tx_fault_sequence_c");
  super.new(name);
endfunction

task mac_stats_tx_fault_sequence_c::body();
  axi_item_c   item_h;
  int unsigned plen;

  plen = (payload_octets < 1) ? 1 : payload_octets;

  item_h                 = axi_item_c::type_id::create("item_h");
  item_h.payload         = new[plen];
  for (int i = 0; i < plen; i++) item_h.payload[i] = 8'(i);

  start_item(item_h);
  finish_item(item_h);
endtask

/**
 * @brief STAS-001 randomized event mix for TC15.
 *
 * Reuses mac_stats_variant_sequence_c to drive a bounded burst of frames,
 * each independently chosen to be a good/qualifying frame or one of the
 * three RS-side fault types, so the owning test can exercise cause
 * qualification under random interleaving.
 */
class mac_stats_random_event_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_stats_random_event_seq_c)

  int unsigned num_events = 10;

  extern function new(string name = "mac_stats_random_event_seq_c");
  extern task body();
endclass

function mac_stats_random_event_seq_c::new(string name = "mac_stats_random_event_seq_c");
  super.new(name);
endfunction

task mac_stats_random_event_seq_c::body();
  mac_stats_variant_sequence_c frm_seq_h;
  int unsigned                 pick;

  repeat (num_events) begin
    frm_seq_h = mac_stats_variant_sequence_c::type_id::create("frm_seq_h");
    pick      = $urandom_range(0, 3);
    case (pick)
      0: ; // good/qualifying frame - defaults are already clean
      1: frm_seq_h.corrupt_fcs      = 1'b1;              // CRC cause
      2: frm_seq_h.force_invalid    = 1'b1;               // invalid cause
      3: frm_seq_h.payload_octets   = 1600;                // oversize cause
    endcase
    frm_seq_h.start(m_sequencer);
  end
endtask
