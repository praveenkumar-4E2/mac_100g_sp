/**
 * @brief APB master sequencer.
 *
 * Coordinates APB transfers between the reusable sequences and the APB
 * driver. Responses produced by the driver via item_done(rsp) are routed
 * back to the requesting sequence through the UVM response mechanism.
 */
class apb_sequencer_c extends uvm_sequencer #(apb_transfer_c);
  `uvm_component_utils(apb_sequencer_c)

  extern function new(string name = "apb_sequencer_c", uvm_component parent = null);
endclass

/**
 * @brief Constructor for the APB sequencer.
 *
 * Initializes the sequencer by calling the parent class constructor.
 *
 * @param name   Name of the sequencer component.
 * @param parent Parent component in the UVM hierarchy.
 */
function apb_sequencer_c::new(string name = "apb_sequencer_c", uvm_component parent = null);
  super.new(name, parent);
endfunction
