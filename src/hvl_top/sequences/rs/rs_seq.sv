/**
 * @brief MAC RS RX Generic Sequence.
 *
 * Drives `num_frames` randomized line-side frame transactions (preamble +
 * SFD + frame) to the RS sequencer. Extends the reusable RS sequence base,
 * so all traffic knobs (payload bounds, error injection, broadcast DA,
 * inter-frame delay) resolve from the agent config unless the caller sets
 * them before start(). The default body() preserves caller-set knobs —
 * it never re-randomizes them.
 */
class rs_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(rs_sequence_c)

  extern function new(string name = "rs_sequence_c");
  extern task body();
endclass

/**
 * @brief Constructor for the MAC RS RX sequence.
 *
 * @param name Name of the sequence object.
 */
function rs_sequence_c::new(string name = "rs_sequence_c");
  super.new(name);
endfunction

/**
 * @brief Implements the main sequence behavior.
 *
 * Delegates to the base: config lookup, knob resolution, then randomized
 * frame generation and driving.
 */
task rs_sequence_c::body();
  resolve_config();
  send_random_frames();
endtask

// NOTE: ps001_rx_preamble_sfd_seq_c has been superseded by
// rx_preamble_sfd_001_seq_c in rx_preamble_sfd_seq.sv (RX_PREAMBLE_SFD_001).
