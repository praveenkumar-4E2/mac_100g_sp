class mac_base_virtual_sequence_c extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(mac_base_virtual_sequence_c)
  `uvm_declare_p_sequencer(mac_virtual_sequencer_c)

  extern function new(string name = "mac_base_virtual_sequence_c");
endclass

function mac_base_virtual_sequence_c::new(string name = "mac_base_virtual_sequence_c");
  super.new(name);
endfunction

class mac_boot_virtual_sequence_c extends mac_base_virtual_sequence_c;
  `uvm_object_utils(mac_boot_virtual_sequence_c)
  bit [15:0] global_control_addr = reg_map_pkg::REG_GLOBAL_CONTROL;
  bit [31:0] global_control_data = 32'h0000_0085;

  extern function new(string name = "mac_boot_virtual_sequence_c");
  extern task body();
endclass

function mac_boot_virtual_sequence_c::new(string name = "mac_boot_virtual_sequence_c");
  super.new(name);
endfunction

task mac_boot_virtual_sequence_c::body();
  apb_write_sequence_c write_h;
  if (p_sequencer.apb_seqr_h == null)
    `uvm_fatal(get_type_name(), "APB sequencer is required for MAC configuration")
  write_h = apb_write_sequence_c::type_id::create("initial_global_control");
  write_h.m_addr = global_control_addr;
  write_h.m_wdata = global_control_data;
  write_h.start(p_sequencer.apb_seqr_h);
endtask
