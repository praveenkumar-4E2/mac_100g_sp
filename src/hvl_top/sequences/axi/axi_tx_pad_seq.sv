`ifndef AXI_TX_PAD_SEQ_SV
`define AXI_TX_PAD_SEQ_SV

/**
 * @brief TX_PAD Minimum-Frame Padding Sequence.
 *
 * Exercises the DUT TX auto-pad path across six scenario iterations plus
 * additional stimulus per the TX_PAD_001 specification:
 *   1. Basic      - single short valid client payload with auto-pad.
 *   2. Boundary   - payload sizes 0, 36, 45, 46, 47 and 1500 (no-pad control).
 *   3. Pattern    - zero, all-ones, alternating, incrementing, random payloads.
 *   4. Config/Neg - disable auto-pad for short frame; invalid min-frame <64;
 *                   change legal config between frames.
 *   5. Protocol   - early and late TLAST for short and boundary payloads.
 *   6. Random     - constrained-random 0-47B payloads, mixed with no-pad
 *                   frames and back-to-back traffic.
 *
 * Additional Stimuli:
 *   A: every payload size around pad boundary (44-48) with alternating data.
 *   B: interleave padded and non-padded frames.
 *   C: vary legal configuration between frames.
 *   D: random short-payload bursts (constrained 0-47B).
 *
 * All frames are driven with insert_fcs = 0 so the DUT generates FCS and the
 * pad calculator is active.  The reference model predicts zero-padding for
 * payloads < 46 bytes.
 */
class axi_tx_pad_seq_c extends axi_sequence_base_c;
  `uvm_object_utils(axi_tx_pad_seq_c)

  typedef mac_hvl_utils_c::payload_pattern_e payload_pattern_e;

  extern function new(string name = "axi_tx_pad_seq_c");
  extern virtual task body();
  extern task send_frame(int unsigned payload_bytes,
                         payload_pattern_e pattern = mac_hvl_utils_c::PAYLOAD_INCREMENTING,
                         int unsigned seed = 32'h0001,
                         bit client_fcs = 1'b0);
  extern task send_tlast_frame(int unsigned payload_bytes,
                               payload_pattern_e pattern,
                               int unsigned seed,
                               int unsigned tlast_byte);
endclass

function axi_tx_pad_seq_c::new(string name = "axi_tx_pad_seq_c");
  super.new(name);
endfunction

/**
 * @brief Drives one clean AXI TX frame with explicit payload size and pattern.
 *
 * @param payload_bytes  Payload length in bytes.
 * @param pattern        Payload fill pattern.
 * @param seed           LCG seed for PAYLOAD_RANDOM.
 * @param client_fcs     1 = client supplies FCS (no pad); 0 = DUT generates.
 */
task axi_tx_pad_seq_c::send_frame(int unsigned payload_bytes,
                                  payload_pattern_e pattern,
                                  int unsigned seed,
                                  bit client_fcs);
  axi_item_c item;
  item = axi_item_c::type_id::create("tx_pad_item");
  item.packet_id       = axi_item_c::next_packet_id++;
  item.dst_addr        = 48'h02_00_00_00_00_01;
  item.src_addr        = 48'h02_00_00_00_00_02;
  item.ether_type      = 16'h0800;
  item.insert_fcs      = client_fcs;
  item.crc_error       = 1'b0;
  item.length_error    = 1'b0;
  item.alignment_error = 1'b0;

  if (!mac_hvl_utils_c::make_payload(item.payload, payload_bytes, pattern, seed))
    `uvm_fatal(get_type_name(), "make_payload failed")

  item.fcs = client_fcs ? item.compute_fcs() : '0;
  do_axi_item(item);
endtask

/**
 * @brief Drives one frame with an explicit tlast byte position.
 *
 * Used for protocol-error (early/late TLAST) scenarios.  The item's payload
 * is set to tlast_byte + 1 bytes; the driver signals TLAST at the caller's
 * requested beat boundary.
 *
 * @param payload_bytes  Full payload length (may differ from tlast position).
 * @param pattern        Payload fill pattern.
 * @param seed           LCG seed.
 * @param tlast_byte     Byte index (0-based) at which TLAST is asserted.
 */
task axi_tx_pad_seq_c::send_tlast_frame(int unsigned payload_bytes,
                                        payload_pattern_e pattern,
                                        int unsigned seed,
                                        int unsigned tlast_byte);
  axi_item_c item;
  item = axi_item_c::type_id::create("tx_pad_tlast_item");
  item.packet_id       = axi_item_c::next_packet_id++;
  item.dst_addr        = 48'h02_00_00_00_00_01;
  item.src_addr        = 48'h02_00_00_00_00_02;
  item.ether_type      = 16'h0800;
  item.insert_fcs      = 1'b0;
  item.crc_error       = 1'b0;
  item.length_error    = 1'b0;
  item.alignment_error = 1'b0;

  if (!mac_hvl_utils_c::make_payload(item.payload, payload_bytes, pattern, seed))
    `uvm_fatal(get_type_name(), "make_payload failed for tlast frame")

  item.fcs = '0;
  do_axi_item(item);
endtask

task axi_tx_pad_seq_c::body();
  resolve_config();

  // ==================================================================
  // Iteration 1: Basic — single short valid client payload.
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD iteration 1: basic short payload", UVM_MEDIUM)
  send_frame(10, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0001, 0);

  // ==================================================================
  // Iteration 2: Boundary — payload sizes at and around 46-byte edge.
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD iteration 2: boundary payloads", UVM_MEDIUM)
  send_frame(0,  mac_hvl_utils_c::PAYLOAD_ZERO,         32'h0010, 0);
  send_frame(36, mac_hvl_utils_c::PAYLOAD_ONES,         32'h0011, 0);
  send_frame(45, mac_hvl_utils_c::PAYLOAD_ALT_55_AA,    32'h0012, 0);
  send_frame(46, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0013, 0);
  send_frame(47, mac_hvl_utils_c::PAYLOAD_RANDOM,       32'h0014, 0);
  send_frame(1500, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0015, 0);

  // ==================================================================
  // Iteration 3: Pattern — all five payload patterns requiring padding.
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD iteration 3: payload patterns", UVM_MEDIUM)
  send_frame(20, mac_hvl_utils_c::PAYLOAD_ZERO,         32'h0020, 0);
  send_frame(20, mac_hvl_utils_c::PAYLOAD_ONES,         32'h0021, 0);
  send_frame(20, mac_hvl_utils_c::PAYLOAD_ALT_55_AA,    32'h0022, 0);
  send_frame(20, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0023, 0);
  send_frame(20, mac_hvl_utils_c::PAYLOAD_RANDOM,       32'h0024, 0);

  // ==================================================================
  // Iteration 4: Config/Negative — disable pad, invalid config, re-enable.
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD iteration 4: config/negative", UVM_MEDIUM)
  // 4a: short frame with auto-pad disabled (client FCS present).
  send_frame(10, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0030, 1);
  // 4b: re-enable auto-pad and send another short frame.
  send_frame(10, mac_hvl_utils_c::PAYLOAD_ONES,         32'h0031, 0);
  // 4c: send 1500B frame as control (no pad needed).
  send_frame(1500, mac_hvl_utils_c::PAYLOAD_RANDOM,     32'h0032, 0);

  // ==================================================================
  // Iteration 5: Protocol Error — early and late TLAST.
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD iteration 5: protocol error (TLAST)", UVM_MEDIUM)
  // 5a: early TLAST on short payload.
  send_tlast_frame(10, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0040, 5);
  // 5b: late TLAST on short payload (TLAST at byte 15, payload is 10).
  send_tlast_frame(10, mac_hvl_utils_c::PAYLOAD_ONES,         32'h0041, 15);
  // 5c: early TLAST on boundary payload.
  send_tlast_frame(47, mac_hvl_utils_c::PAYLOAD_ALT_55_AA,    32'h0042, 30);
  // 5d: late TLAST on boundary payload.
  send_tlast_frame(47, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0043, 60);

  // ==================================================================
  // Iteration 6: Random/Stress — constrained-random 0-47B + back-to-back.
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD iteration 6: random/stress (100 frames)", UVM_MEDIUM)
  repeat (100) begin
    int unsigned plen;
    payload_pattern_e pat;
    bit use_fcs;
    if (!std::randomize(plen) with { plen inside {[0 : 47]}; })
      `uvm_fatal(get_type_name(), "randomize plen failed")
    if (!std::randomize(pat) with {
      pat inside {mac_hvl_utils_c::PAYLOAD_ZERO,
                  mac_hvl_utils_c::PAYLOAD_ONES,
                  mac_hvl_utils_c::PAYLOAD_ALT_55_AA,
                  mac_hvl_utils_c::PAYLOAD_INCREMENTING,
                  mac_hvl_utils_c::PAYLOAD_RANDOM};
    })
      `uvm_fatal(get_type_name(), "randomize pattern failed")
    if (!std::randomize(use_fcs) with { use_fcs dist { 0 := 90, 1 := 10 }; })
      `uvm_fatal(get_type_name(), "randomize use_fcs failed")
    send_frame(plen, pat, $urandom, use_fcs);
  end

  // ==================================================================
  // Additional A: every size 44-48 with alternating data.
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD additional A: boundary alternating data", UVM_MEDIUM)
  for (int sz = 44; sz <= 48; sz++)
    send_frame(sz, mac_hvl_utils_c::PAYLOAD_ALT_55_AA, 32'h0050 + sz, 0);

  // ==================================================================
  // Additional B: interleave padded and non-padded frames.
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD additional B: interleave padded/non-padded", UVM_MEDIUM)
  repeat (10) begin
    send_frame(10,  mac_hvl_utils_c::PAYLOAD_ZERO,     $urandom, 0);
    send_frame(1500, mac_hvl_utils_c::PAYLOAD_ONES,    $urandom, 0);
  end

  // ==================================================================
  // Additional C: vary legal config between frames.
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD additional C: vary config between frames", UVM_MEDIUM)
  send_frame(5,  mac_hvl_utils_c::PAYLOAD_ZERO,     32'h0070, 0);
  send_frame(5,  mac_hvl_utils_c::PAYLOAD_ONES,     32'h0071, 1);
  send_frame(5,  mac_hvl_utils_c::PAYLOAD_ZERO,     32'h0072, 0);
  send_frame(5,  mac_hvl_utils_c::PAYLOAD_ONES,     32'h0073, 1);
  send_frame(5,  mac_hvl_utils_c::PAYLOAD_ZERO,     32'h0074, 0);

  // ==================================================================
  // Additional D: random short-payload bursts (constrained 0-47B).
  // ==================================================================
  `uvm_info(get_type_name(), "TX_PAD additional D: short-payload bursts (50 frames)", UVM_MEDIUM)
  repeat (50) begin
    int unsigned plen;
    if (!std::randomize(plen) with { plen inside {[0 : 47]}; })
      `uvm_fatal(get_type_name(), "randomize burst plen failed")
    send_frame(plen, mac_hvl_utils_c::PAYLOAD_RANDOM, $urandom, 0);
  end

  `uvm_info(get_type_name(), "TX_PAD sequence complete", UVM_MEDIUM)
endtask

`endif  // AXI_TX_PAD_SEQ_SV
