class mac_virtual_sequencer_c extends uvm_sequencer #(uvm_sequence_item);
  `uvm_component_utils(mac_virtual_sequencer_c)

  axi_sequencer_c       client_ingress_seqr_h;
  axi_sequencer_c       client_egress_seqr_h;
  rs_sequencer_c        line_ingress_seqr_h;
  apb_sequencer_c       apb_seqr_h;
  mac_reset_sequencer_c mac_reset_seqr_h;
  mac_reset_sequencer_c apb_reset_seqr_h;

  extern function new(string name = "mac_virtual_sequencer_c", uvm_component parent = null);
endclass

function mac_virtual_sequencer_c::new(string name = "mac_virtual_sequencer_c",
                                      uvm_component parent = null);
  super.new(name, parent);
endfunction
