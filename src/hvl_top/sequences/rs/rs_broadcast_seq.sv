/**
 * @brief Tier-2 RS variants: broadcast and unicast traffic generators.
 *
 * Thin subclasses of rs_sequence_base_c: each locks one knob and inherits
 * the randomized default body(). All other knobs (count, payload bounds,
 * inter-frame delay) stay configurable by the caller before start().
 */

/**
 * @brief RS broadcast sequence.
 *
 * Drives num_frames clean, broadcast-addressed line-side frames. Matches
 * the DUT's default address-filtering behavior (promiscuous disabled).
 */
class rs_broadcast_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(rs_broadcast_sequence_c)

  extern function new(string name = "rs_broadcast_sequence_c");
endclass

/**
 * @brief Constructor for the RS broadcast sequence.
 *
 * @param name Name of the sequence object.
 */
function rs_broadcast_sequence_c::new(string name = "rs_broadcast_sequence_c");
  super.new(name);
  broadcast_da = 1'b1;
  error_injection = 1'b0;
endfunction

/**
 * @brief RS unicast sequence.
 *
 * Drives num_frames clean frames to a single caller-chosen destination
 * (unicast_da, rand so it can be constrained per test). When the DUT is
 * configured with promiscuous mode off, the destination must match the
 * address filter to reach the client.
 */
class rs_unicast_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(rs_unicast_sequence_c)

  rand bit [47:0] unicast_da;

  extern function new(string name = "rs_unicast_sequence_c");
  extern task body();
endclass

/**
 * @brief Constructor for the RS unicast sequence.
 *
 * @param name Name of the sequence object.
 */
function rs_unicast_sequence_c::new(string name = "rs_unicast_sequence_c");
  super.new(name);
  broadcast_da = 1'b0;
  error_injection = 1'b0;
  unicast_da = 48'h02_00_00_00_00_01;
endfunction

/**
 * @brief Drives one clean unicast frame per configured frame count.
 */
task rs_unicast_sequence_c::body();
  resolve_config();
  repeat (num_frames) begin
    send_clean_frame(-1, unicast_da);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask