`uvm_analysis_imp_decl(_axi)
`uvm_analysis_imp_decl(_rs)
`uvm_analysis_imp_decl(_rs_tx)
`uvm_analysis_imp_decl(_apb_ref)

class mac_reference_model_c extends uvm_component;
  `uvm_component_utils(mac_reference_model_c)

  //input from master tx monitor
  uvm_analysis_imp_axi #(axi_item_c, mac_reference_model_c) axi_observed_imp;
  uvm_analysis_imp_rs #(frame_xtn_c, mac_reference_model_c) rs_observed_imp;
  //input from the MAC TX-wire passive monitor (DUT-generated frames)
  uvm_analysis_imp_rs_tx #(frame_xtn_c, mac_reference_model_c) rs_tx_observed_imp;
  uvm_analysis_imp_apb_ref #(apb_transfer_t, mac_reference_model_c) apb_observed_imp;
  //output to sb master tx port
  uvm_analysis_port #(frame_xtn_c) rs_expected_port;
  uvm_analysis_port #(axi_item_c) axi_expected_port;
  mac_env_cfg_c cfg_h;
  bit [47:0] cfg_mac_addr = '0;
  bit [15:0] cfg_pause_quanta = '0;
  bit cfg_pause_tx_enable;
  bit cfg_pause_tx_soft_req;

  extern function new(string name = "mac_reference_model_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern function void write_axi(axi_item_c m_axi_xtn);
  extern function void write_rs(frame_xtn_c m_rs_xtn);
  extern function void write_rs_tx(frame_xtn_c m_rs_xtn);
  extern function void write_apb_ref(apb_transfer_t m_apb_xtn);
  extern function void queue_pause_tx_expectation();
  extern function bit is_pause_frame(frame_xtn_c item);

endclass

function mac_reference_model_c::new(string name = "mac_reference_model_c",
                                    uvm_component parent = null);
  super.new(name, parent);
  axi_expected_port = new("axi_expected_port", this);
  rs_expected_port = new("rs_expected_port", this);

  axi_observed_imp = new("axi_observed_imp", this);
  rs_observed_imp = new("rs_observed_imp", this);
  rs_tx_observed_imp = new("rs_tx_observed_imp", this);
  apb_observed_imp = new("apb_observed_imp", this);

endfunction

function void mac_reference_model_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_env_cfg_c)::get(this, "", "mac_env_cfg", cfg_h))
    `uvm_fatal("CONFIG_ERROR", "mac_reference_model_c cannot find mac_env_cfg")
endfunction

function void mac_reference_model_c::write_axi(axi_item_c m_axi_xtn);
  frame_xtn_c  expected;
  int unsigned pad_bytes;

  expected = frame_xtn_c::type_id::create("tx_wire_expected");
  expected.packet_id = m_axi_xtn.packet_id;
  expected.preamble = 56'h55_5555_5555_5555;
  expected.sfd = 8'hd5;
  expected.dst_addr = m_axi_xtn.dst_addr;
  expected.src_addr = m_axi_xtn.src_addr;
  expected.ether_type = m_axi_xtn.ether_type;
  pad_bytes = (!m_axi_xtn.insert_fcs && m_axi_xtn.payload.size() < cfg_h.min_payload_bytes) ?
      cfg_h.min_payload_bytes - m_axi_xtn.payload.size() : 0;
  expected.payload = new[m_axi_xtn.payload.size() + pad_bytes];
  foreach (m_axi_xtn.payload[i]) expected.payload[i] = m_axi_xtn.payload[i];
  for (int i = m_axi_xtn.payload.size(); i < expected.payload.size(); i++) expected.payload[i] = '0;
  expected.insert_fcs      = 1'b1;
  expected.fcs             = m_axi_xtn.insert_fcs ? m_axi_xtn.fcs : expected.compute_fcs();
  expected.crc_error       = 1'b0;
  expected.length_error    = 1'b0;
  expected.alignment_error = 1'b0;
  rs_expected_port.write(expected);
endfunction

function void mac_reference_model_c::write_rs(frame_xtn_c m_rs_xtn);
  axi_item_c expected;

  // Bad frames and PAUSE control frames are consumed by the RX MAC.  They
  // intentionally create no AXI expectation, so any delivery is unexpected.
  if (m_rs_xtn.crc_error || m_rs_xtn.length_error || m_rs_xtn.alignment_error ||
      (m_rs_xtn.ether_type == 16'h8808))
    return;

  expected            = axi_item_c::type_id::create("rx_client_expected");
  expected.packet_id  = m_rs_xtn.packet_id;
  expected.dst_addr   = m_rs_xtn.dst_addr;
  expected.src_addr   = m_rs_xtn.src_addr;
  expected.ether_type = m_rs_xtn.ether_type;
  expected.payload    = new[m_rs_xtn.payload.size()];
  foreach (m_rs_xtn.payload[i]) expected.payload[i] = m_rs_xtn.payload[i];
  expected.fcs             = '0;
  expected.insert_fcs      = 1'b0;
  expected.crc_error       = 1'b0;
  expected.length_error    = 1'b0;
  expected.alignment_error = 1'b0;
  axi_expected_port.write(expected);
endfunction

function bit mac_reference_model_c::is_pause_frame(frame_xtn_c item);
  return (item.dst_addr == 48'h01_80_c2_00_00_01) && (item.ether_type == 16'h8808) &&
      (item.payload.size() >= 2) && (item.payload[0] == 8'h00) && (item.payload[1] == 8'h01);
endfunction

function void mac_reference_model_c::write_rs_tx(frame_xtn_c m_rs_xtn);
  // The MAC TX-wire passive monitor observes every frame the DUT emits.  A
  // DUT-generated PAUSE expectation is queued at the APB soft-request edge,
  // preserving its configuration snapshot across CDC latency.  This passive
  // observation point deliberately creates no expectation.
endfunction

function void mac_reference_model_c::queue_pause_tx_expectation();
  frame_xtn_c expected;
  expected            = frame_xtn_c::type_id::create("tx_pause_wire_expected");
  expected.preamble   = 56'h55_5555_5555_5555;
  expected.sfd        = 8'hd5;
  expected.dst_addr   = 48'h01_80_c2_00_00_01;
  expected.src_addr   = cfg_mac_addr;
  expected.ether_type = 16'h8808;
  expected.payload    = new[46];
  expected.payload[0] = 8'h00;
  expected.payload[1] = 8'h01;
  expected.payload[2] = cfg_pause_quanta[15:8];
  expected.payload[3] = cfg_pause_quanta[7:0];
  for (int i = 4; i < expected.payload.size(); i++) expected.payload[i] = '0;
  expected.insert_fcs      = 1'b1;
  expected.fcs             = expected.compute_fcs();
  expected.crc_error       = 1'b0;
  expected.length_error    = 1'b0;
  expected.alignment_error = 1'b0;
  rs_expected_port.write(expected);
endfunction

function void mac_reference_model_c::write_apb_ref(apb_transfer_t m_apb_xtn);
  if (m_apb_xtn == null || !m_apb_xtn.pwrite || m_apb_xtn.status != APB_OK) return;
  case (m_apb_xtn.addr)
    reg_map_pkg::REG_MAC_ADDR_LOW:  cfg_mac_addr[31:0]  = m_apb_xtn.wdata;
    reg_map_pkg::REG_MAC_ADDR_HIGH: cfg_mac_addr[47:32] = m_apb_xtn.wdata[15:0];
    reg_map_pkg::REG_PAUSE_TX_CONFIG: begin
      cfg_pause_tx_enable = (m_apb_xtn.wdata[17:16] != 2'b00) ?
          m_apb_xtn.wdata[reg_map_pkg::PAUSE_TX_EXT_ENABLE_BIT] :
          m_apb_xtn.wdata[reg_map_pkg::PAUSE_TX_ENABLE_BIT];
      cfg_pause_quanta    = m_apb_xtn.wdata[15:0];
      if (cfg_pause_tx_enable &&
          ((m_apb_xtn.wdata[17:16] != 2'b00) ?
              m_apb_xtn.wdata[reg_map_pkg::PAUSE_TX_EXT_SOFT_REQ_BIT] :
              m_apb_xtn.wdata[reg_map_pkg::PAUSE_TX_SOFT_REQ_BIT]) &&
          !cfg_pause_tx_soft_req)
        queue_pause_tx_expectation();
      cfg_pause_tx_soft_req = (m_apb_xtn.wdata[17:16] != 2'b00) ?
          m_apb_xtn.wdata[reg_map_pkg::PAUSE_TX_EXT_SOFT_REQ_BIT] :
          m_apb_xtn.wdata[reg_map_pkg::PAUSE_TX_SOFT_REQ_BIT];
    end
    default: ;
  endcase
endfunction
