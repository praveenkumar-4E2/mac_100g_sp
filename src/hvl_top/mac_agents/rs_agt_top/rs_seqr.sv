/**
 * @brief MAC RS RX Sequencer.
 *
 * Coordinates communication between the RS sequences and
 * the RS driver. It receives sequence items from the active
 * sequence and forwards them to the driver for execution.
 */
class rs_sequencer_c extends uvm_sequencer #(frame_xtn_c);
  `uvm_component_utils(rs_sequencer_c)

  extern function new(string name = "rs_sequencer_c", uvm_component parent = null);
endclass

/**
 * @brief Constructor for the MAC RS RX sequencer.
 *
 * Initializes the sequencer by calling the parent class
 * constructor.
 *
 * @param name Name of the sequencer component.
 * @param parent Parent component in the UVM hierarchy.
 */
function rs_sequencer_c::new(string name = "rs_sequencer_c", uvm_component parent = null);
  super.new(name, parent);
endfunction
