/**
 * @brief MAC Master TX Generic Sequence.
 *
 * Drives `num_tx` randomized MAC transmit transactions to the master TX
 * sequencer. Extends the reusable AXI sequence base, so all traffic knobs
 * (payload bounds, error injection, broadcast DA, inter-frame delay)
 * resolve from the agent config unless the caller sets them before start().
 * The default body() preserves caller-set knobs — it never re-randomizes
 * them.
 */
class axi_sequence_c extends axi_sequence_base_c;
  `uvm_object_utils(axi_sequence_c)

  extern function new(string name = "axi_sequence_c");
  extern task body();
endclass

/**
 * @brief Constructor for the MAC Master TX sequence.
 *
 * @param name Name of the sequence object.
 */
function axi_sequence_c::new(string name = "axi_sequence_c");
  super.new(name);
endfunction

/**
 * @brief Implements the main sequence behavior.
 *
 * Delegates to the base: config lookup, knob resolution, then randomized
 * item generation and driving.
 */
task axi_sequence_c::body();
  axi_item_c axi_item_h;
  super.body();
  // UTL-100: look up the config from the starting sequencer's hierarchy
  // rather than a null-context wildcard lookup.
  if (!uvm_config_db#(axi_agent_cfg_c)::get(m_sequencer, "", "axi_agent_cfg", cfg_h)) begin
    `uvm_fatal(get_type_name(),
               "uvm_config_db#(axi_agent_cfg_c)::get cannot find resource axi agt config")
  end

  // Default frame count; tests that constrain num_tx keep theirs.
  if (!randomize() with {soft num_tx == cfg_h.num_tx_default;}) begin
    `uvm_fatal(get_type_name(), "Randomization of num_tx failed")
  end

  repeat (num_tx) begin
    axi_item_h = axi_item_c::type_id::create("axi_item_h");
    if (cfg_h.enable_error_injection) begin
      if (!axi_item_h.randomize() with {
            soft payload.size() inside {[cfg_h.min_payload_len : cfg_h.max_payload_len]};
          }) begin
        `uvm_fatal(get_type_name(), "Randomization of axi_item_h failed")
      end
    end else begin
      if (!axi_item_h.randomize() with {
            crc_error == 0;
            length_error == 0;
            alignment_error == 0;
            soft payload.size() inside {[cfg_h.min_payload_len : cfg_h.max_payload_len]};
          }) begin
        `uvm_fatal(get_type_name(), "Randomization of axi_item_h failed")
      end
    end
    start_item(axi_item_h);
    finish_item(axi_item_h);
  end
endtask
