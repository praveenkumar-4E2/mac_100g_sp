`ifndef AXI_CRC_SEQ_SV
`define AXI_CRC_SEQ_SV 

// Sends one CRC/FCS-directed AXI TX frame. Configure the public fields before
// start(); create multiple sequence objects for a mixed-pattern burst.
class axi_crc_seq_c extends axi_sequence_base_c;
  `uvm_object_utils(axi_crc_seq_c)

  typedef mac_hvl_utils_c::payload_pattern_e payload_pattern_e;

  int unsigned             payload_length     = 64;
  payload_pattern_e        payload_pattern    = mac_hvl_utils_c::PAYLOAD_INCREMENTING;
  int unsigned             payload_seed       = 32'hc001_cafe;
  bit                      client_fcs_present = 1'b0;
  bit               [31:0] client_fcs         = '0;
  bit                      corrupt_fcs        = 1'b0;
  bit               [47:0] dst_addr           = 48'h02_00_00_00_00_01;
  bit               [47:0] src_addr           = 48'h02_00_00_00_00_02;
  bit               [15:0] ether_type         = 16'h0800;

  extern function new(string name = "axi_crc_seq_c");
  extern virtual task body();
endclass

function axi_crc_seq_c::new(string name = "axi_crc_seq_c");
  super.new(name);
endfunction

task axi_crc_seq_c::body();
  axi_item_c item;

  if (payload_length > MAC_SUPER_JUMBO_PAYLOAD_BYTES)
    `uvm_fatal(get_type_name(), $sformatf(
               "Payload length %0d exceeds the super-jumbo limit", payload_length))
  if (corrupt_fcs && !client_fcs_present)
    `uvm_fatal(get_type_name(), "corrupt_fcs requires client_fcs_present")

  item                 = axi_item_c::type_id::create("crc_item");
  item.packet_id       = axi_item_c::next_packet_id++;
  item.dst_addr        = dst_addr;
  item.src_addr        = src_addr;
  item.ether_type      = ether_type;
  item.insert_fcs      = client_fcs_present;
  item.crc_error       = 1'b0;
  item.length_error    = 1'b0;
  item.alignment_error = 1'b0;

  if (!mac_hvl_utils_c::make_payload(item.payload, payload_length, payload_pattern, payload_seed))
    `uvm_fatal(get_type_name(), "Unsupported payload pattern")

  item.fcs = client_fcs_present ? client_fcs : '0;
  if (corrupt_fcs) item.fcs ^= 32'h0000_0001;

  do_axi_item(item);
endtask




//====================================================================
//mac_tx_crc_001_sequence_c
//====================================================================
// Full directed TX CRC/FCS burst used by TX_CRC_001.  Keeping it in the AXI
// sequence layer lets the testcase stay focused on configuration and checks.
class mac_tx_crc_001_sequence_c extends axi_sequence_base_c;
  `uvm_object_utils(mac_tx_crc_001_sequence_c)

  typedef mac_hvl_utils_c::payload_pattern_e payload_pattern_e;

  extern function new(string name = "mac_tx_crc_001_sequence_c");
  extern virtual task body();
  extern task send_frame(int unsigned payload_bytes, payload_pattern_e pattern, int unsigned seed,
                         bit client_fcs, bit corrupt_fcs = 0, bit corrupt_da = 0,
                         bit corrupt_sa = 0, bit corrupt_type = 0, bit corrupt_payload = 0);
endclass

function mac_tx_crc_001_sequence_c::new(string name = "mac_tx_crc_001_sequence_c");
  super.new(name);
endfunction

task mac_tx_crc_001_sequence_c::send_frame(int unsigned payload_bytes, payload_pattern_e pattern,
                                           int unsigned seed, bit client_fcs, bit corrupt_fcs = 0,
                                           bit corrupt_da = 0, bit corrupt_sa = 0,
                                           bit corrupt_type = 0, bit corrupt_payload = 0);
  axi_item_c item;

  item                 = axi_item_c::type_id::create("tx_crc_item");
  item.packet_id       = axi_item_c::next_packet_id++;
  item.dst_addr        = 48'h02_00_00_00_00_01;
  item.src_addr        = 48'h02_00_00_00_00_02;
  item.ether_type      = 16'h0800;
  item.insert_fcs      = client_fcs;
  item.length_error    = 1'b0;
  item.alignment_error = 1'b0;
  if (!mac_hvl_utils_c::make_payload(item.payload, payload_bytes, pattern, seed))
    `uvm_fatal(get_type_name(), "Unable to create TX_CRC_001 payload")

  // Calculate each client FCS before optional protected-field corruption.
  item.fcs = client_fcs ? item.compute_fcs() : '0;
  if (corrupt_da) item.dst_addr[0] ^= 1'b1;
  if (corrupt_sa) item.src_addr[0] ^= 1'b1;
  if (corrupt_type) item.ether_type[0] ^= 1'b1;
  if (corrupt_payload) item.payload[0][0] ^= 1'b1;
  if (corrupt_fcs) item.fcs[0] ^= 1'b1;
  item.crc_error = corrupt_fcs || corrupt_da || corrupt_sa || corrupt_type || corrupt_payload;
  do_axi_item(item);
endtask

task mac_tx_crc_001_sequence_c::body();
  // Basic and FCS control.
  send_frame(64, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0001, 0);
  send_frame(64, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0001, 1);
  send_frame(128, mac_hvl_utils_c::PAYLOAD_KNOWN_CRC, 32'hcafe_0001, 0);

  // Padding/boundary and maximum-frame scenarios.
  send_frame(1, mac_hvl_utils_c::PAYLOAD_ZERO, 32'h0002, 0);
  send_frame(46, mac_hvl_utils_c::PAYLOAD_ONES, 32'h0003, 1);
  send_frame(MAC_SUPER_JUMBO_PAYLOAD_BYTES, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0004, 0);

  // Payload patterns and one-bit sensitivity pair.
  send_frame(96, mac_hvl_utils_c::PAYLOAD_ZERO, 32'h0010, 0);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_ONES, 32'h0011, 1);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_ALT_55_AA, 32'h0012, 0);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0013, 1);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0013, 1, 0, 0, 0, 0, 1);
  send_frame(96, mac_hvl_utils_c::PAYLOAD_RANDOM, 32'h0014, 0);

  // Back-to-back, mixed-size traffic with alternating FCS ownership.
  send_frame(47, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0020, 0);
  send_frame(511, mac_hvl_utils_c::PAYLOAD_ALT_AA_55, 32'h0021, 1);
  send_frame(1500, mac_hvl_utils_c::PAYLOAD_RANDOM, 32'h0022, 0);

  // Mixed valid/error burst: independently corrupt protected fields and FCS.
  send_frame(80, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0030, 1, 0, 1);
  send_frame(80, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0031, 1, 0, 0, 1);
  send_frame(80, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0032, 1, 0, 0, 0, 1);
  send_frame(80, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0033, 1, 0, 0, 0, 0, 1);
  send_frame(80, mac_hvl_utils_c::PAYLOAD_INCREMENTING, 32'h0034, 1, 1);
endtask

`endif  // AXI_CRC_SEQ_SV
