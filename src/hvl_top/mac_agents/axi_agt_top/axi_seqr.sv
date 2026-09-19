/**
 * @brief MAC Master TX Sequencer.
 *
 * Coordinates communication between the TX sequences and
 * the TX driver. It receives sequence items from the active
 * sequence and forwards them to the driver for execution.
 */
class axi_sequencer_c extends uvm_sequencer #(axi_item_c);
  `uvm_component_utils(axi_sequencer_c)

  extern function new(string name = "axi_sequencer_c", uvm_component parent = null);
endclass

/**
 * @brief Constructor for the MAC Master TX sequencer.
 *
 * Initializes the sequencer by calling the parent class
 * constructor.
 *
 * @param name Name of the sequencer component.
 * @param parent Parent component in the UVM hierarchy.
 */
function axi_sequencer_c::new(string name = "axi_sequencer_c", uvm_component parent = null);
  super.new(name, parent);
endfunction


