/**
 * @brief Tier-2 RS variant: error-injection traffic generator.
 *
 * Thin subclass of rs_sequence_base_c with error injection enabled, so each
 * randomized frame independently draws CRC/length/alignment errors from the
 * item's weighted distribution. Frame count and payload bounds stay
 * configurable by the caller before start().
 */
class rs_error_inject_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(rs_error_inject_sequence_c)

  extern function new(string name = "rs_error_inject_sequence_c");
endclass

/**
 * @brief Constructor for the RS error-injection sequence.
 *
 * @param name Name of the sequence object.
 */
function rs_error_inject_sequence_c::new(string name = "rs_error_inject_sequence_c");
  super.new(name);
  error_injection = 1'b1;
endfunction