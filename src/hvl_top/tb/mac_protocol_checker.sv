`uvm_analysis_imp_decl(_axi_protocol)
`uvm_analysis_imp_decl(_rs_protocol)

// Transaction-level protocol checks complementary to the signal-level
// assertions in the RTL and monitors.  This subscriber is deliberately
// non-driving and can be enabled independently of end-to-end scoreboarding.
class mac_protocol_checker_c extends uvm_component;
  `uvm_component_utils(mac_protocol_checker_c)

  uvm_analysis_imp_axi_protocol #(axi_item_c, mac_protocol_checker_c) axi_imp;
  uvm_analysis_imp_rs_protocol #(frame_xtn_c, mac_protocol_checker_c) rs_imp;
  mac_env_cfg_c cfg_h;
  int unsigned axi_checked;
  int unsigned rs_checked;
  int unsigned violations;

  extern function new(string name = "mac_protocol_checker_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern function void write_axi_protocol(axi_item_c item);
  extern function void write_rs_protocol(frame_xtn_c item);
  extern function void report_phase(uvm_phase phase);
endclass

function mac_protocol_checker_c::new(string name = "mac_protocol_checker_c",
                                     uvm_component parent = null);
  super.new(name, parent);
  axi_imp = new("axi_imp", this);
  rs_imp  = new("rs_imp", this);
endfunction

function void mac_protocol_checker_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_env_cfg_c)::get(this, "", "mac_env_cfg", cfg_h))
    `uvm_fatal("CONFIG_ERROR", "mac_protocol_checker_c cannot find mac_env_cfg")
endfunction

function void mac_protocol_checker_c::write_axi_protocol(axi_item_c item);
  axi_checked++;
  if ((item.payload.size() < cfg_h.min_payload_bytes) ||
      (item.payload.size() > cfg_h.max_payload_bytes)) begin
    violations++;
    `uvm_error("MAC_AXI_PROTOCOL", $sformatf("payload size %0d outside configured [%0d:%0d]",
                                             item.payload.size(), cfg_h.min_payload_bytes,
                                             cfg_h.max_payload_bytes))
  end
  if (item.insert_fcs && !item.crc_error && item.fcs != item.compute_fcs()) begin
    violations++;
    `uvm_error("MAC_AXI_PROTOCOL", "FCS-present AXI frame has an invalid FCS")
  end
endfunction

function void mac_protocol_checker_c::write_rs_protocol(frame_xtn_c item);
  rs_checked++;
  if (item.preamble != 56'h55_5555_5555_5555 || item.sfd != 8'hd5) begin
    violations++;
    `uvm_error("MAC_RS_PROTOCOL", "RS frame has an invalid IEEE 802.3 preamble/SFD")
  end
  if ((item.payload.size() < cfg_h.min_payload_bytes) ||
      (item.payload.size() > cfg_h.max_payload_bytes)) begin
    violations++;
    `uvm_error("MAC_RS_PROTOCOL", $sformatf("payload size %0d outside configured [%0d:%0d]",
                                            item.payload.size(), cfg_h.min_payload_bytes,
                                            cfg_h.max_payload_bytes))
  end
  if (item.insert_fcs && !item.crc_error && item.fcs != item.compute_fcs()) begin
    violations++;
    `uvm_error("MAC_RS_PROTOCOL", "FCS-present RS frame has an invalid FCS")
  end
endfunction

function void mac_protocol_checker_c::report_phase(uvm_phase phase);
  `uvm_info("MAC_PROTOCOL", $sformatf(
            "protocol summary: axi=%0d rs=%0d violations=%0d", axi_checked, rs_checked, violations),
            UVM_NONE)
endfunction
