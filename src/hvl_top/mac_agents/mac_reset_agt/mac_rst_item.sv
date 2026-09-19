typedef enum int {
  MAC_RESET_ASSERT   = 0,
  MAC_RESET_DEASSERT = 1
} mac_reset_operation_e;

class mac_reset_item_c extends uvm_sequence_item;
  `uvm_object_utils(mac_reset_item_c)

  mac_reset_operation_e operation;
  int unsigned          duration_cycles;
  int unsigned          reset_id;
  time                  event_time;

  extern function new(string name = "mac_reset_item_c");
  extern function string convert2string();
endclass

function mac_reset_item_c::new(string name = "mac_reset_item_c");
  super.new(name);
  operation       = MAC_RESET_ASSERT;
  duration_cycles = 0;
  reset_id        = 0;
  event_time      = 0;
endfunction

function string mac_reset_item_c::convert2string();
  return $sformatf(
      "operation=%0s reset_id=%0d duration_cycles=%0d event_time=%0t",
      operation.name(),
      reset_id,
      duration_cycles,
      event_time
  );
endfunction
