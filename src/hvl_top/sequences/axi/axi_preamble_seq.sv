/**
 * @brief TX Preamble Generation Sequence (PS002).
 *
 * Exercises the DUT TX preamble/SFD generation across five scenario
 * iterations per the TX_PREAMBLE_GEN_001 specification:
 *   1. Basic — single nominal valid frame.
 *   2. Boundary/pattern — varying payload-start patterns after SFD.
 *   3. Timing/sequence — minimum IFG, variable IFG, mixed-size, back-to-back.
 *   5. Random/stress — constrained-random legal frames over sustained traffic.
 *   6. Additional — constrained-random byte-stream campaign.
 *
 * Every transmitted frame must contain exactly seven 0x55 preamble bytes
 * followed by 0xD5 SFD before the payload.  This is enforced by the
 * protocol checker and scoreboard; this sequence provides the stimulus.
 */
class ps002_tx_preamble_sfd_seq_c extends axi_sequence_base_c;
  `uvm_object_utils(ps002_tx_preamble_sfd_seq_c)

  axi_item_c axi_item_h;

  extern function new(string name = "ps002_tx_preamble_sfd_seq_c");
  extern task body();
  extern task send_clean_frame(int pkt_len = -1);
  extern task send_random_frame();
  extern task send_fixed_payload_frame(byte unsigned start_byte);
endclass

function ps002_tx_preamble_sfd_seq_c::new(string name = "ps002_tx_preamble_sfd_seq_c");
  super.new(name);
endfunction

task ps002_tx_preamble_sfd_seq_c::body();
  resolve_config();

  // ---------------------------------------------------------------
  // Iteration 1: Basic — transmit one nominal valid frame.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "PS002 iteration 1: basic valid frame", UVM_MEDIUM)
  send_clean_frame(46);

  // ---------------------------------------------------------------
  // Iteration 2: Boundary/pattern — check all 7x 0x55 bytes,
  // SFD 0xD5, and the immediate SFD-to-frame boundary by driving
  // frames with varying payload-start patterns after the SFD.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "PS002 iteration 2: boundary/pattern — varying payload start", UVM_MEDIUM)
  send_fixed_payload_frame(8'h00);
  send_fixed_payload_frame(8'hFF);
  send_fixed_payload_frame(8'hAA);
  send_fixed_payload_frame(8'h55);
  send_fixed_payload_frame(8'h01);
  send_fixed_payload_frame(8'hDE);
  send_fixed_payload_frame(8'hAD);
  send_fixed_payload_frame(8'hBE);
  send_fixed_payload_frame(8'hEF);
  send_random_frame();

  // ---------------------------------------------------------------
  // Iteration 3: Timing/sequence — minimum and variable IFG;
  // mixed-size and back-to-back frames.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "PS002 iteration 3: timing/sequence — back-to-back and mixed-size", UVM_MEDIUM)

  // 3a: Back-to-back minimum-size frames (zero inter-frame delay)
  repeat (5) send_clean_frame(46);

  // 3b: Back-to-back maximum-size frames
  repeat (5) send_clean_frame(1500);

  // 3c: Mixed-size frames with randomized payload
  repeat (10) send_random_frame();

  // ---------------------------------------------------------------
  // Iteration 5: Random/stress — constrained-random legal frame
  // sizes and IFG over sustained traffic.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "PS002 iteration 5: random/stress — 1000 constrained-random frames", UVM_MEDIUM)
  repeat (1000) send_random_frame();

  // ---------------------------------------------------------------
  // Iteration 6: Additional — constrained-random byte-stream
  // campaign with varying payload sizes.
  // ---------------------------------------------------------------
  `uvm_info(get_type_name(), "PS002 iteration 6: additional — 200-frame byte-stream campaign", UVM_MEDIUM)
  repeat (200) send_random_frame();

endtask

/**
 * @brief Drives one clean frame with an explicit payload length.
 *
 * @param pkt_len Payload length in bytes; -1 randomizes within config bounds.
 */
task ps002_tx_preamble_sfd_seq_c::send_clean_frame(int pkt_len = -1);
  axi_item_c item;
  item = axi_item_c::type_id::create("item");
  if (!item.randomize() with {
        dst_addr == 48'hFF_FF_FF_FF_FF_FF;
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs      == 1;
        soft ether_type > 16'h0600;
        if (pkt_len >= 0) payload.size() == pkt_len;
        else payload.size() inside {[46 : 1500]};
      }) begin
    `uvm_fatal(get_type_name(), "Randomization of clean AXI item failed")
  end
  do_axi_item(item);
endtask

/**
 * @brief Drives one constrained-random clean frame.
 */
task ps002_tx_preamble_sfd_seq_c::send_random_frame();
  axi_item_c item;
  item = axi_item_c::type_id::create("item");
  if (!item.randomize() with {
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        payload.size() inside {[46 : 1500]};
        soft ether_type > 16'h0600;
      }) begin
    `uvm_fatal(get_type_name(), "Randomization of random AXI item failed")
  end
  do_axi_item(item);
endtask

/**
 * @brief Drives one clean frame whose payload starts with a fixed byte.
 *
 * The first payload byte is set to start_byte; the remaining bytes are
 * randomized.  This exercises the SFD-to-frame boundary by alternating
 * the byte immediately following the SFD.
 *
 * @param start_byte First payload byte value after SFD.
 */
task ps002_tx_preamble_sfd_seq_c::send_fixed_payload_frame(byte unsigned start_byte);
  axi_item_c item;
  item = axi_item_c::type_id::create("item");
  if (!item.randomize() with {
        crc_error       == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs      == 1;
        payload.size() inside {[46 : 1500]};
        payload[0] == start_byte;
        soft ether_type > 16'h0600;
      }) begin
    `uvm_fatal(get_type_name(), "Randomization of fixed-payload AXI item failed")
  end
  do_axi_item(item);
endtask
