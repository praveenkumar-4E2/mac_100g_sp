/**
 * @brief Tier-2 AXI variants: clean, broadcast, and error-injection traffic
 *        generators.
 *
 * Thin subclasses of axi_sequence_base_c: each locks one knob and inherits
 * the randomized default body(). All other knobs (count, payload bounds,
 * inter-frame delay) stay configurable by the caller before start().
 */

/**
 * @brief AXI clean sequence.
 *
 * Drives num_tx clean client TX items (no CRC/length/alignment errors).
 */
class axi_clean_sequence_c extends axi_sequence_base_c;
  `uvm_object_utils(axi_clean_sequence_c)

  extern function new(string name = "axi_clean_sequence_c");
endclass

/**
 * @brief Constructor for the AXI clean sequence.
 *
 * @param name Name of the sequence object.
 */
function axi_clean_sequence_c::new(string name = "axi_clean_sequence_c");
  super.new(name);
  error_injection = 1'b0;
endfunction

/**
 * @brief AXI broadcast sequence.
 *
 * Drives num_tx client TX items with a broadcast destination address.
 */
class axi_broadcast_sequence_c extends axi_sequence_base_c;
  `uvm_object_utils(axi_broadcast_sequence_c)

  extern function new(string name = "axi_broadcast_sequence_c");
endclass

/**
 * @brief Constructor for the AXI broadcast sequence.
 *
 * @param name Name of the sequence object.
 */
function axi_broadcast_sequence_c::new(string name = "axi_broadcast_sequence_c");
  super.new(name);
  broadcast_da = 1'b1;
endfunction

/**
 * @brief AXI error-injection sequence.
 *
 * Drives num_tx client TX items; each item independently draws
 * CRC/length/alignment errors from the item's weighted distribution.
 */
class axi_error_inject_sequence_c extends axi_sequence_base_c;
  `uvm_object_utils(axi_error_inject_sequence_c)

  extern function new(string name = "axi_error_inject_sequence_c");
endclass

/**
 * @brief Constructor for the AXI error-injection sequence.
 *
 * @param name Name of the sequence object.
 */
function axi_error_inject_sequence_c::new(string name = "axi_error_inject_sequence_c");
  super.new(name);
  error_injection = 1'b1;
endfunction