/**
 * @brief Single sequence class providing all comprehensive-scenario traffic
 *        patterns as methods.  Each method creates and starts the appropriate
 *        child sequence (axi_clean_sequence_c or rs_sequence_c) on the
 *        passed sequencer handle.
 *
 * No multiple classes — one class, methods only.
 */
class mac_comprehensive_scenario_seq_c extends uvm_sequence;
  `uvm_object_utils(mac_comprehensive_scenario_seq_c)

  // Shared config knobs
  int unsigned payload_min  = 46;
  int unsigned payload_max  = 1500;
  bit          error_injection = 1'b0;

  extern function new(string name = "mac_comprehensive_scenario_seq_c");

  // AXI: burst (zero IFG) then sparse (large IFG) then burst again.
  extern task send_axi_burst_sparse(
      axi_sequencer_c seqr,
      int unsigned burst_cnt,
      int unsigned sparse_cnt,
      time         sparse_ifg);

  // AXI: back-to-back clean items.
  extern task send_axi_constrained_burst(
      axi_sequencer_c seqr,
      int unsigned count);

  // RS: constrained-random frames with varied dest, pattern, IPG.
  extern task send_rs_constrained_random(
      rs_sequencer_c seqr,
      int unsigned count);
endclass

// =============================================================================
// Constructor
// =============================================================================

function mac_comprehensive_scenario_seq_c::new(
    string name = "mac_comprehensive_scenario_seq_c");
  super.new(name);
endfunction

// =============================================================================
// AXI burst/sparse traffic
// =============================================================================

task mac_comprehensive_scenario_seq_c::send_axi_burst_sparse(
    axi_sequencer_c seqr,
    int unsigned burst_cnt,
    int unsigned sparse_cnt,
    time         sparse_ifg);
  // Burst: zero IFG
  begin
    axi_clean_sequence_c burst_seq;
    burst_seq = axi_clean_sequence_c::type_id::create("axi_burst");
    burst_seq.num_tx       = burst_cnt;
    burst_seq.payload_min  = payload_min;
    burst_seq.payload_max  = payload_max;
    burst_seq.error_injection = error_injection;
    burst_seq.broadcast_da = 1'b0;
    burst_seq.start(seqr);
  end
  // Sparse: large IFG
  repeat (sparse_cnt) begin
    axi_clean_sequence_c sparse_seq;
    sparse_seq = axi_clean_sequence_c::type_id::create("axi_sparse");
    sparse_seq.num_tx       = 1;
    sparse_seq.payload_min  = payload_min;
    sparse_seq.payload_max  = payload_max;
    sparse_seq.error_injection = error_injection;
    sparse_seq.broadcast_da = 1'b0;
    sparse_seq.start(seqr);
    #(sparse_ifg);
  end
  // Burst again
  begin
    axi_clean_sequence_c burst2_seq;
    burst2_seq = axi_clean_sequence_c::type_id::create("axi_burst2");
    burst2_seq.num_tx       = burst_cnt;
    burst2_seq.payload_min  = payload_min;
    burst2_seq.payload_max  = payload_max;
    burst2_seq.error_injection = error_injection;
    burst2_seq.broadcast_da = 1'b0;
    burst2_seq.start(seqr);
  end
endtask

// =============================================================================
// AXI constrained burst (back-to-back)
// =============================================================================

task mac_comprehensive_scenario_seq_c::send_axi_constrained_burst(
    axi_sequencer_c seqr,
    int unsigned count);
  axi_clean_sequence_c seq_h;
  seq_h = axi_clean_sequence_c::type_id::create("axi_cstr_burst");
  seq_h.num_tx       = count;
  seq_h.payload_min  = payload_min;
  seq_h.payload_max  = payload_max;
  seq_h.error_injection = error_injection;
  seq_h.broadcast_da = 1'b0;
  seq_h.start(seqr);
endtask

// =============================================================================
// RS constrained-random sustained traffic
// =============================================================================

task mac_comprehensive_scenario_seq_c::send_rs_constrained_random(
    rs_sequencer_c seqr,
    int unsigned count);
  // Each iteration: drive one randomized RS frame with varied IPG.
  // rs_sequence_c generates a single randomised frame per start(),
  // so we start count single-frame sequences with gaps in between.
  repeat (count) begin
    rs_sequence_c rs_seq;
    time ipg;
    ipg = $urandom_range(0, 100) * 1ns;
    rs_seq = rs_sequence_c::type_id::create("rs_cstr_rnd");
    rs_seq.num_frames   = 1;
    rs_seq.payload_min  = payload_min;
    rs_seq.payload_max  = payload_max;
    rs_seq.error_injection = error_injection;
    rs_seq.broadcast_da = 1'b1;
    rs_seq.start(seqr);
    #(ipg);
  end
endtask
