class mac_rx_crc_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_rx_crc_sequence_c)

  typedef mac_hvl_utils_c::payload_pattern_e payload_pattern_e;

  // Number of frames expected at the RX AXI monitor.  Corrupted and
  // post-FCS-trailing frames are intentionally dropped by the MAC.
  int unsigned expected_rx_frames;

  extern function new(string name = "mac_rx_crc_sequence_c");
  extern virtual task body();
  extern task send_frame(int unsigned payload_bytes, payload_pattern_e pattern, int unsigned seed,
                         bit client_fcs, bit corrupt_fcs=0,bit corrupt_da = 0, bit corrupt_sa = 0,
                         bit corrupt_type = 0, bit corrupt_payload = 0,
                         bit [31:0] fcs_xor_mask = 32'h0000_0001,
                         int unsigned payload_corrupt_index = 0,
                         byte unsigned payload_xor_mask = 8'h01,
                         int unsigned trailing_byte_count = 0,
                         byte unsigned trailing_byte = 8'ha5);
endclass


function mac_rx_crc_sequence_c::new(string name = "mac_rx_crc_sequence_c");
  super.new(name);
endfunction

task mac_rx_crc_sequence_c::send_frame(int unsigned payload_bytes, payload_pattern_e pattern,
                                      int unsigned seed, bit client_fcs, bit corrupt_fcs=0,
                                      bit corrupt_da = 0, bit corrupt_sa = 0, bit corrupt_type = 0,
                                      bit corrupt_payload = 0,
                                      bit [31:0] fcs_xor_mask = 32'h0000_0001,
                                      int unsigned payload_corrupt_index = 0,
                                      byte unsigned payload_xor_mask = 8'h01,
                                      int unsigned trailing_byte_count = 0,
                                      byte unsigned trailing_byte = 8'ha5);
  frame_xtn_c item;

  item                 = frame_xtn_c::type_id::create("rx_crc_item");
  item.packet_id       = frame_xtn_c::next_packet_id++;
  item.preamble        = 56'h55_5555_5555_5555;
  item.sfd             = 8'hD5;
  item.dst_addr        = 48'h02_00_00_00_00_02;
  item.src_addr        = 48'h02_00_00_00_00_01;
  item.ether_type      = 16'h0800;

  item.insert_fcs      = client_fcs;
  item.length_error    = 1'b0;
  item.alignment_error = 1'b0;

  if (!mac_hvl_utils_c::make_payload(item.payload, payload_bytes, pattern, seed))
    `uvm_fatal(get_type_name(), "Unable to create RX_CRC_002 payload")

  // CRC covers the finalized header and payload.  Apply all corruption only
  // after this calculation, so each selected corruption is independently
  // capable of producing a bad residue.
  item.fcs = client_fcs ? item.compute_fcs() : '0;

  if (corrupt_da) item.dst_addr[0]          ^= 1'b1;
  if (corrupt_sa) item.src_addr[0]          ^= 1'b1;
  if (corrupt_type) item.ether_type[0]      ^= 1'b1;
  if (corrupt_payload) begin
    if (payload_corrupt_index >= item.payload.size())
      `uvm_fatal(get_type_name(), "Payload corruption index is outside the payload")
    item.payload[payload_corrupt_index] ^= payload_xor_mask;
  end
  if (corrupt_fcs) begin
    if (!client_fcs) `uvm_fatal(get_type_name(), "FCS corruption requires an FCS-present frame")
    item.fcs ^= fcs_xor_mask;
  end
  item.trailing_bytes = new[trailing_byte_count];
  foreach (item.trailing_bytes[i]) item.trailing_bytes[i] = trailing_byte ^ byte'(i);

  item.crc_error = corrupt_fcs || corrupt_da || corrupt_sa || corrupt_type || corrupt_payload ||
      (trailing_byte_count != 0);
  if (!item.crc_error) expected_rx_frames++;
  do_rs_frame(item);
endtask


task mac_rx_crc_sequence_c ::body();
  expected_rx_frames = 0;

  // Basic: valid reference-calculated client FCS and no-client-FCS modes.
  send_frame(64, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0000_0001, 1);
  send_frame(128, mac_hvl_utils_c::PAYLOAD_KNOWN_CRC, 32'hcafe_0001, 1);
  send_frame(64, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0000_0002, 0);

  // Negative: FCS, protected payload, and invalid post-FCS octets.
  send_frame(96, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0010, 1, 1, 0, 0, 0, 0,
             32'h0000_0021);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0011, 1, 0, 0, 0, 0, 1,
             32'h1, 37, 8'h84);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_KNOWN_CRC, 32'h0012, 1, 0, 0, 0, 0, 0,
             32'h1, 0, 8'h1, 3, 8'ha5);

  // Boundary and deterministic/random patterns.
  send_frame(46, mac_hvl_utils_c::PAYLOAD_ZERO, 32'h0020, 1);
  send_frame(MAC_SUPER_JUMBO_PAYLOAD_BYTES, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0021, 1);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_ONES, 32'h0022, 0);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_ALT_55_AA, 32'h0023, 1);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_ALT_AA_55, 32'h0024, 0);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_RANDOM, 32'h0025, 1);

  // Required ordering and back-to-back valid traffic.
  send_frame(80, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0030, 1);
  send_frame(80, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0031, 1, 1);
  send_frame(80, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0032, 1);
  for (int unsigned i = 0; i < 4; i++)
    send_frame(64 + i, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0040 + i, i[0]);

  // Mixed valid/error burst: independently and jointly corrupt protected fields.
  for (int unsigned i = 0; i < 20; i++) begin
    if ((i % 2) == 0)
      send_frame(72 + i, mac_hvl_utils_c::PAYLOAD_RANDOM, 32'h0100 + i, i[0]);
    else
      send_frame(72 + i, mac_hvl_utils_c::PAYLOAD_RANDOM, 32'h0100 + i, 1,
                 (i % 5) == 1, (i % 5) == 2, (i % 5) == 3, (i % 5) == 4,
                 (i % 5) == 0, 32'h0000_0101, i % (72 + i), 8'h81);
  end
  send_frame(88, mac_hvl_utils_c::PAYLOAD_RANDOM, 32'h0200, 1, 1, 1, 1, 1, 1,
             32'h8000_0003, 11, 8'h42);

  // 100+ back-to-back valid frames, alternating FCS-present mode and payload.
  for (int unsigned i = 0; i < 101; i++)
    // FCS-absent ingress still needs 64 on-wire octets, so its minimum
    // payload is 50 bytes (14-byte header + 50-byte payload).
    send_frame(50 + (i % 128), mac_hvl_utils_c::PAYLOAD_RANDOM, 32'h1000 + i, i[0]);

endtask
