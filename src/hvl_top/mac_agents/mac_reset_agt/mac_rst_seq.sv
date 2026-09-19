class mac_reset_sequence_c extends uvm_sequence #(mac_reset_item_c);
  `uvm_object_utils(mac_reset_sequence_c)
  `uvm_declare_p_sequencer(mac_reset_sequencer_c)

  int unsigned duration_cycles = 0;

  extern function new(string name = "mac_reset_sequence_c");
  extern task body();
  extern task send_operation(mac_reset_operation_e operation, int unsigned item_duration_cycles);
endclass

function mac_reset_sequence_c::new(string name = "mac_reset_sequence_c");
  super.new(name);
endfunction

task mac_reset_sequence_c::body();
  int unsigned effective_duration_cycles;

  effective_duration_cycles = (duration_cycles == 0) ? p_sequencer.cfg_h.default_duration_cycles :
      duration_cycles;
  send_operation(MAC_RESET_ASSERT, effective_duration_cycles);
  send_operation(MAC_RESET_DEASSERT, 0);
endtask

task mac_reset_sequence_c::send_operation(mac_reset_operation_e operation,
                                          int unsigned item_duration_cycles);
  mac_reset_item_c item_h;

  item_h = mac_reset_item_c::type_id::create("item_h");
  start_item(item_h);
  item_h.operation       = operation;
  item_h.duration_cycles = item_duration_cycles;
  item_h.reset_id        = p_sequencer.cfg_h.reset_id;
  finish_item(item_h);
endtask
