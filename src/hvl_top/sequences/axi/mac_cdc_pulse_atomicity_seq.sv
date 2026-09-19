// CDC-PULSE-ATOMICITY: Dedicated traffic-pattern sequence for verifying
// maximum-frame-size configuration update atomicity across APB/MAC clock
// domains.  Provides burst/sparse AXI traffic, constrained-random RS
// traffic, typed single-frame RS traffic, and mixed-size bursts as
// callable methods.
//
// Single class with methods (no multiple classes).  Each method creates
// and starts the appropriate child sequence on the passed sequencer handle.
class mac_cdc_pulse_atomicity_seq_c extends uvm_sequence;
  `uvm_object_utils(mac_cdc_pulse_atomicity_seq_c)

  int unsigned payload_min     = 46;
  int unsigned payload_max     = 1500;
  bit          error_injection = 1'b0;

  extern function new(string name = "mac_cdc_pulse_atomicity_seq_c");

  extern task send_axi_burst_sparse(
      axi_sequencer_c seqr,
      int unsigned burst_cnt,
      int unsigned sparse_cnt,
      time         sparse_ifg);

  extern task send_axi_constrained_burst(
      axi_sequencer_c seqr,
      int unsigned count);

  extern task send_rs_constrained_random(
      rs_sequencer_c seqr,
      int unsigned count);

  extern task send_rs_typed_frame(
      rs_sequencer_c seqr,
      int unsigned frame_octets,
      bit [47:0] da,
      mac_hvl_utils_c::payload_pattern_e pattern,
      string frame_name);

  extern task send_mixed_size_burst(
      rs_sequencer_c seqr,
      int unsigned count,
      int min_sz,
      int max_sz);
endclass

// =============================================================================
// Constructor
// =============================================================================

function mac_cdc_pulse_atomicity_seq_c::new(
    string name = "mac_cdc_pulse_atomicity_seq_c");
  super.new(name);
endfunction

// =============================================================================
// AXI burst/sparse traffic: zero-IFG burst, then sparse with large gap,
// then burst again.
// =============================================================================

task mac_cdc_pulse_atomicity_seq_c::send_axi_burst_sparse(
    axi_sequencer_c seqr,
    int unsigned burst_cnt,
    int unsigned sparse_cnt,
    time         sparse_ifg);
  begin
    axi_clean_sequence_c burst_seq;
    burst_seq = axi_clean_sequence_c::type_id::create("cdc_at_burst");
    burst_seq.num_tx          = burst_cnt;
    burst_seq.payload_min     = payload_min;
    burst_seq.payload_max     = payload_max;
    burst_seq.error_injection = error_injection;
    burst_seq.broadcast_da    = 1'b0;
    burst_seq.start(seqr);
  end
  repeat (sparse_cnt) begin
    axi_clean_sequence_c sparse_seq;
    sparse_seq = axi_clean_sequence_c::type_id::create("cdc_at_sparse");
    sparse_seq.num_tx          = 1;
    sparse_seq.payload_min     = payload_min;
    sparse_seq.payload_max     = payload_max;
    sparse_seq.error_injection = error_injection;
    sparse_seq.broadcast_da    = 1'b0;
    sparse_seq.start(seqr);
    #(sparse_ifg);
  end
  begin
    axi_clean_sequence_c burst2_seq;
    burst2_seq = axi_clean_sequence_c::type_id::create("cdc_at_burst2");
    burst2_seq.num_tx          = burst_cnt;
    burst2_seq.payload_min     = payload_min;
    burst2_seq.payload_max     = payload_max;
    burst2_seq.error_injection = error_injection;
    burst2_seq.broadcast_da    = 1'b0;
    burst2_seq.start(seqr);
  end
endtask

// =============================================================================
// AXI constrained burst (back-to-back clean frames)
// =============================================================================

task mac_cdc_pulse_atomicity_seq_c::send_axi_constrained_burst(
    axi_sequencer_c seqr,
    int unsigned count);
  axi_clean_sequence_c seq_h;
  seq_h = axi_clean_sequence_c::type_id::create("cdc_at_axi_cstr");
  seq_h.num_tx          = count;
  seq_h.payload_min     = payload_min;
  seq_h.payload_max     = payload_max;
  seq_h.error_injection = error_injection;
  seq_h.broadcast_da    = 1'b0;
  seq_h.start(seqr);
endtask

// =============================================================================
// RS constrained-random sustained traffic: randomized IPG, varied patterns
// =============================================================================

task mac_cdc_pulse_atomicity_seq_c::send_rs_constrained_random(
    rs_sequencer_c seqr,
    int unsigned count);
  repeat (count) begin
    rs_sequence_c rs_seq;
    time ipg;
    ipg = $urandom_range(0, 100) * 1ns;
    rs_seq = rs_sequence_c::type_id::create("cdc_at_rs_rnd");
    rs_seq.num_frames      = 1;
    rs_seq.payload_min     = payload_min;
    rs_seq.payload_max     = payload_max;
    rs_seq.error_injection = error_injection;
    rs_seq.broadcast_da    = 1'b1;
    rs_seq.start(seqr);
    #(ipg);
  end
endtask

// =============================================================================
// RS typed single frame: explicit size, destination, and payload pattern
// =============================================================================

task mac_cdc_pulse_atomicity_seq_c::send_rs_typed_frame(
    rs_sequencer_c seqr,
    int unsigned frame_octets,
    bit [47:0] da,
    mac_hvl_utils_c::payload_pattern_e pattern,
    string frame_name);
  apb_002_rx_frame_sequence_c frame_seq_h;
  frame_seq_h = apb_002_rx_frame_sequence_c::type_id::create(
                    {"cdc_at_", frame_name});
  frame_seq_h.frame_octets   = frame_octets;
  frame_seq_h.destination     = da;
  frame_seq_h.payload_pattern = pattern;
  frame_seq_h.payload_seed    = $urandom;
  frame_seq_h.start(seqr);
endtask

// =============================================================================
// Mixed-size RS burst: randomized frame sizes within [min_sz, max_sz]
// =============================================================================

task mac_cdc_pulse_atomicity_seq_c::send_mixed_size_burst(
    rs_sequencer_c seqr,
    int unsigned count,
    int min_sz,
    int max_sz);
  repeat (count) begin
    int unsigned sz;
    mac_hvl_utils_c::payload_pattern_e patterns [5] = '{
        mac_hvl_utils_c::PAYLOAD_ZERO,
        mac_hvl_utils_c::PAYLOAD_ONES,
        mac_hvl_utils_c::PAYLOAD_ALT_55_AA,
        mac_hvl_utils_c::PAYLOAD_INCREMENTING,
        mac_hvl_utils_c::PAYLOAD_RANDOM
    };
    sz = $urandom_range(min_sz, max_sz);
    send_rs_typed_frame(seqr, sz, 48'hFF_FF_FF_FF_FF_FF,
                        patterns[$urandom_range(0, 4)],
                        $sformatf("mixed_%0d", sz));
  end
endtask
