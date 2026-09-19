`ifndef MAC_PAUSE_FRAME_TESTS_SVH
`define MAC_PAUSE_FRAME_TESTS_SVH

// Alias: mac_pause_frame_sequence_c was deleted with mac_pause_test.sv but
// is still referenced by apb_003.sv.  Map it to mac_control_frame_sequence_c.
class mac_pause_frame_sequence_c extends mac_control_frame_sequence_c;
  `uvm_object_utils(mac_pause_frame_sequence_c)
  extern function new(string name = "mac_pause_frame_sequence_c");
endclass

function mac_pause_frame_sequence_c::new(string name = "mac_pause_frame_sequence_c");
  super.new(name);
endfunction

`include "PF_001.sv"
`include "PF_002.sv"
`include "PF_003.sv"
`include "PF_004.sv"
`include "PF_005.sv"

`endif  // MAC_PAUSE_FRAME_TESTS_SVH
