/**
 * @brief Boundary-pattern and RX_FILTER_MODE RS sequence for address-filtering tests.
 *
 * Comprehensive stimulus-only sequence covering:
 *   - 48-bit DA boundary patterns (zero, all-ones, alternating, neighbors, random)
 *   - Promiscuous-mode burst (unmatched unicast traffic for OFF/ON/OFF testing)
 *   - Multicast burst (group-addressed traffic for active/inactive testing)
 *   - Accepted-rejected-accepted toggle sequences
 *   - Constrained-random 4-class address selection
 *   - Local/group/broadcast class alternation on consecutive frames
 *   - Sustained traffic with non-matching address injection
 *
 * The sequence is pure stimulus — NO APB register accesses.
 * The caller programs the DUT (local address, group table, promiscuous
 * mode, RX enable) before starting the sequence, and re-programs between
 * runs when testing dynamic configuration changes.
 *
 * Usage:
 *   rs_addr_filter_boundary_seq_c seq;
 *   seq = rs_addr_filter_boundary_seq_c::type_id::create("seq");
 *   seq.local_addr   = 48'h00_00_02_00_00_AA;
 *   seq.group_addr   = 48'h00_5E_00_01_00_01;
 *   seq.seq_mode     = rs_addr_filter_boundary_seq_c::MODE_BOUNDARY_PATTERN;
 *   seq.start(rs_seqr_h);
 */
class rs_addr_filter_boundary_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(rs_addr_filter_boundary_seq_c)

  // =========================================================================
  // Boundary-pattern enumeration (existing, unchanged for backward-compat)
  // =========================================================================
  typedef enum bit [2:0] {
    PAT_ZERO        = 3'b000,
    PAT_ALL_ONES    = 3'b001,
    PAT_ALT_55      = 3'b010,
    PAT_ALT_AA      = 3'b011,
    PAT_NEIGHBOR_M1 = 3'b100,  // target_addr - 1
    PAT_NEIGHBOR_P1 = 3'b101,  // target_addr + 1
    PAT_TARGET      = 3'b110,  // exact match
    PAT_RANDOM      = 3'b111
  } pattern_e;

  // =========================================================================
  // Address class enumeration (for randomized modes)
  // =========================================================================
  typedef enum bit [1:0] {
    ADDR_CLASS_LOCAL      = 2'b00,
    ADDR_CLASS_GROUP      = 2'b01,
    ADDR_CLASS_BROADCAST  = 2'b10,
    ADDR_CLASS_RANDOM_UNI = 2'b11
  } addr_class_e;

  // =========================================================================
  // Sequence mode enumeration
  // =========================================================================
  typedef enum bit [2:0] {
    MODE_BOUNDARY_PATTERN         = 3'b000,  // existing 8-pattern sweep
    MODE_PROMISCUOUS_BURST        = 3'b001,  // burst of unmatched unicast
    MODE_MULTICAST_BURST          = 3'b010,  // burst of group-addressed frames
    MODE_ACCEPTED_REJECTED_SEQ    = 3'b011,  // toggle accept/reject pattern
    MODE_CONSTRAINED_RANDOM       = 3'b100,  // randomized 4-class DA selection
    MODE_CLASS_ALTERNATION        = 3'b101,  // local->group->bcast alternation
    MODE_SUSTAINED_WITH_INJECTION = 3'b110   // sustained traffic + injection
  } seq_mode_e;

  // =========================================================================
  // Caller-set addresses
  // =========================================================================
  bit [47:0] target_addr  = 48'h00_00_02_00_00_AA;
  bit [47:0] local_addr   = 48'h00_00_02_00_00_AA;
  bit [47:0] group_addr   = 48'h00_5E_00_01_00_01;

  // =========================================================================
  // Configurable SA and EtherType (boundary-pattern mode)
  // =========================================================================
  bit [47:0] frame_sa       = 48'h02_00_00_00_00_01;
  bit [15:0] frame_ethertype = 16'h0800;

  // =========================================================================
  // Constrained-random knobs
  // =========================================================================
  rand seq_mode_e          seq_mode;
  rand addr_class_e        addr_class;
  rand pattern_e           pattern;
  rand bit [47:0]          frame_da;
  rand bit [47:0]          rnd_sa;
  rand bit [47:0]          nomatch_addr;
  rand int unsigned        num_frames;
  rand int unsigned        payload_size;

  // =========================================================================
  // Constraints
  // =========================================================================

  constraint c_knob_bounds {
    num_frames inside {[1 : 50]};
    payload_size inside {[46 : 150]};
  }

  // Boundary-pattern DA must match the selected pattern (MODE_BOUNDARY_PATTERN)
  constraint c_da_matches_pattern {
    (seq_mode == MODE_BOUNDARY_PATTERN) -> {
      (pattern == PAT_ZERO)        -> frame_da == 48'h00_00_00_00_00_00;
      (pattern == PAT_ALL_ONES)    -> frame_da == 48'hFF_FF_FF_FF_FF_FF;
      (pattern == PAT_ALT_55)      -> frame_da == 48'h55_55_55_55_55_55;
      (pattern == PAT_ALT_AA)      -> frame_da == 48'hAA_AA_AA_AA_AA_AA;
      (pattern == PAT_NEIGHBOR_M1) -> frame_da == (target_addr - 1);
      (pattern == PAT_NEIGHBOR_P1) -> frame_da == (target_addr + 1);
      (pattern == PAT_TARGET)      -> frame_da == target_addr;
      (pattern == PAT_RANDOM)      -> {
        frame_da != target_addr;
        frame_da != local_addr;
        frame_da != group_addr;
        frame_da != 48'hFF_FF_FF_FF_FF_FF;
        frame_da != 48'h01_80_C2_00_00_01;
        frame_da[40] == 1'b0;  // force unicast
      }
    }
  }

  // Address-class distribution (MODE_CONSTRAINED_RANDOM)
  constraint c_addr_class_dist {
    (seq_mode == MODE_CONSTRAINED_RANDOM) -> {
      addr_class dist {
        ADDR_CLASS_LOCAL      := 30,
        ADDR_CLASS_GROUP      := 20,
        ADDR_CLASS_BROADCAST  := 30,
        ADDR_CLASS_RANDOM_UNI := 20
      };
    }
  }

  // DA must match the selected address class (MODE_CONSTRAINED_RANDOM)
  constraint c_da_matches_class {
    (seq_mode == MODE_CONSTRAINED_RANDOM) -> {
      (addr_class == ADDR_CLASS_LOCAL)      -> frame_da == local_addr;
      (addr_class == ADDR_CLASS_GROUP)      -> frame_da == group_addr;
      (addr_class == ADDR_CLASS_BROADCAST)  -> frame_da == 48'hFF_FF_FF_FF_FF_FF;
      (addr_class == ADDR_CLASS_RANDOM_UNI) -> {
        frame_da != local_addr;
        frame_da != group_addr;
        frame_da != 48'hFF_FF_FF_FF_FF_FF;
        frame_da != 48'h01_80_C2_00_00_01;
        frame_da[40] == 1'b0;  // force unicast
      }
    }
  }

  // Non-matching unicast for PROMISCUOUS_BURST and injection frames
  constraint c_nonmatch_da {
    (seq_mode == MODE_PROMISCUOUS_BURST) -> {
      frame_da != local_addr;
      frame_da != group_addr;
      frame_da != 48'hFF_FF_FF_FF_FF_FF;
      frame_da != 48'h01_80_C2_00_00_01;
      frame_da[40] == 1'b0;  // unicast
    }
  }

  extern function new(string name = "rs_addr_filter_boundary_seq_c");
  extern task body();

  // Frame-sending helpers
  extern task send_boundary_frame(bit [47:0] da, bit [47:0] sa);
  extern task send_directed_frame(bit [47:0] da, bit [47:0] sa);

  // Mode body tasks
  extern task body_boundary_pattern();
  extern task body_promiscuous_burst();
  extern task body_multicast_burst();
  extern task body_accepted_rejected_seq();
  extern task body_constrained_random();
  extern task body_class_alternation();
  extern task body_sustained_with_injection();
endclass

// =============================================================================
// Constructor
// =============================================================================
function rs_addr_filter_boundary_seq_c::new(string name = "rs_addr_filter_boundary_seq_c");
  super.new(name);
endfunction

// =============================================================================
// Main body — dispatches to mode-specific sub-task
// =============================================================================
task rs_addr_filter_boundary_seq_c::body();
  payload_min = 46;
  payload_max = 1500;
  case (seq_mode)
    MODE_BOUNDARY_PATTERN:         body_boundary_pattern();
    MODE_PROMISCUOUS_BURST:        body_promiscuous_burst();
    MODE_MULTICAST_BURST:          body_multicast_burst();
    MODE_ACCEPTED_REJECTED_SEQ:    body_accepted_rejected_seq();
    MODE_CONSTRAINED_RANDOM:       body_constrained_random();
    MODE_CLASS_ALTERNATION:        body_class_alternation();
    MODE_SUSTAINED_WITH_INJECTION: body_sustained_with_injection();
    default:                       body_boundary_pattern();
  endcase
endtask

// =============================================================================
// Frame-sending helpers
// =============================================================================

/**
 * @brief Drives one frame with explicit DA and SA, building the frame
 *        manually with computed FCS (for boundary-pattern testing).
 */
task rs_addr_filter_boundary_seq_c::send_boundary_frame(
    bit [47:0] da, bit [47:0] sa);
  frame_xtn_c frm;
  frm            = frame_xtn_c::type_id::create("frm");
  frm.dst_addr   = da;
  frm.src_addr   = sa;
  frm.ether_type = frame_ethertype;
  frm.payload    = new[payload_size];
  foreach (frm.payload[i]) frm.payload[i] = 8'hA5;
  frm.insert_fcs      = 1'b1;
  frm.crc_error       = 1'b0;
  frm.length_error    = 1'b0;
  frm.alignment_error = 1'b0;
  frm.fcs             = frm.compute_fcs();
  do_rs_frame(frm);
  if (inter_frame_delay > 0) #inter_frame_delay;
endtask

/**
 * @brief Drives one frame with explicit DA and SA using send_clean_frame.
 */
task rs_addr_filter_boundary_seq_c::send_directed_frame(
    bit [47:0] da, bit [47:0] sa);
  frame_xtn_c frm;
  frm = frame_xtn_c::type_id::create("frm");
  if (!frm.randomize() with {
        dst_addr    == da;
        src_addr    == sa;
        crc_error   == 0;
        length_error    == 0;
        alignment_error == 0;
        insert_fcs  == 1'b1;
        soft ether_type > 16'h0600;
        payload.size() inside {[46 : 1500]};
      })
    `uvm_fatal(get_type_name(), "Randomization of directed frame failed")
  do_rs_frame(frm);
  if (inter_frame_delay > 0) #inter_frame_delay;
endtask

// =============================================================================
// MODE 0: Boundary / DA extraction — 8 DA patterns (existing, unchanged)
//
// Drives one frame per pattern so the test can verify correct 48-bit
// comparison across the full DA bit vector.
//
// Expected accepted (with target_addr programmed): 2 frames
//   PAT_ALL_ONES (broadcast) + PAT_TARGET (exact match)
// =============================================================================
task rs_addr_filter_boundary_seq_c::body_boundary_pattern();
  for (int unsigned p = 0; p < 8; p++) begin
    // Freeze the loop's pattern so randomize() below cannot re-roll the
    // explicit boundary-pattern index.  Keep the class-level solver in the
    // same scope by also giving handshake to the frame-count knob, which the
    // class constraints already require to stay within the legal range.
    if (!randomize(frame_da, payload_size, pattern, num_frames) with {
          num_frames == 1;
          pattern == pattern_e'(p);
          (p == 0)        -> frame_da == 48'h00_00_00_00_00_00;  // PAT_ZERO
          (p == 1)        -> frame_da == 48'hFF_FF_FF_FF_FF_FF;  // PAT_ALL_ONES
          (p == 2)        -> frame_da == 48'h55_55_55_55_55_55;  // PAT_ALT_55
          (p == 3)        -> frame_da == 48'hAA_AA_AA_AA_AA_AA;  // PAT_ALT_AA
          (p == 4)        -> frame_da == (target_addr - 1);      // PAT_NEIGHBOR_M1
          (p == 5)        -> frame_da == (target_addr + 1);      // PAT_NEIGHBOR_P1
          (p == 6)        -> frame_da == target_addr;            // PAT_TARGET
          (p == 7)        -> {                                    // PAT_RANDOM
            frame_da != target_addr;
            frame_da != local_addr;
            frame_da != group_addr;
            frame_da != 48'hFF_FF_FF_FF_FF_FF;
            frame_da != 48'h01_80_C2_00_00_01;
            frame_da[40] == 1'b0;  // force unicast
          }
        })
      `uvm_fatal(get_type_name(),
          $sformatf("Randomization of boundary pattern frame %0d failed", p))

    send_boundary_frame(frame_da, frame_sa);
  end
endtask

// =============================================================================
// MODE 1: Promiscuous-mode burst — non-matching unicast only
//
// Sends num_frames of non-matching unicast.  The TEST controls promiscuous
// mode via APB between separate runs of this mode:
//   Run 1 (promiscuous OFF) → all dropped
//   Run 2 (promiscuous ON)  → all accepted
//   Run 3 (promiscuous OFF) → all dropped
// =============================================================================
task rs_addr_filter_boundary_seq_c::body_promiscuous_burst();
  repeat (num_frames) begin
    if (!randomize() with { seq_mode == MODE_PROMISCUOUS_BURST; })
      `uvm_fatal(get_type_name(), "Randomization of promiscuous burst frame failed")
    send_directed_frame(frame_da, frame_sa);
  end
endtask

// =============================================================================
// MODE 2: Multicast burst — group-addressed frames
//
// Sends num_frames addressed to group_addr.  The TEST controls the
// multicast group table via APB between separate runs:
//   Run 1 (group entry active)   → all accepted
//   Run 2 (group entry cleared)  → all dropped
//   Run 3 (group entry restored) → all accepted
// =============================================================================
task rs_addr_filter_boundary_seq_c::body_multicast_burst();
  repeat (num_frames) begin
    send_directed_frame(group_addr, frame_sa);
  end
endtask

// =============================================================================
// MODE 3: Accepted → rejected → accepted sequences
//
// Phase 1: 3 accepted  (local, group, broadcast)
// Phase 2: 3 rejected  (3 different non-matching unicast)
// Phase 3: 3 accepted  (local, broadcast, group)
// Phase 4: 10 sustained with injection — alternating accepted/rejected
//   local, nonmatch, bcast, group, nonmatch,
//   local, nonmatch, bcast, group, nonmatch
//
// Total: 19 frames.  Accepted: ~11.  Dropped: ~8.
// =============================================================================
task rs_addr_filter_boundary_seq_c::body_accepted_rejected_seq();
  bit [47:0] nonmatch_addrs [6] = '{
    48'hCA_FE_FA_DE_00_01,
    48'hDE_AD_BE_EF_00_02,
    48'h01_02_03_04_05_06,
    48'hCA_FE_FA_DE_00_03,
    48'hDE_AD_BE_EF_00_04,
    48'hDE_AD_BE_EF_00_06
  };

  // Phase 1: accepted
  send_directed_frame(local_addr, frame_sa);
  send_directed_frame(group_addr, frame_sa);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, frame_sa);

  // Phase 2: rejected
  send_directed_frame(nonmatch_addrs[0], frame_sa);
  send_directed_frame(nonmatch_addrs[1], frame_sa);
  send_directed_frame(nonmatch_addrs[2], frame_sa);

  // Phase 3: accepted
  send_directed_frame(local_addr, frame_sa);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, frame_sa);
  send_directed_frame(group_addr, frame_sa);

  // Phase 4: sustained with injection
  send_directed_frame(local_addr, frame_sa);
  send_directed_frame(nonmatch_addrs[3], frame_sa);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, frame_sa);
  send_directed_frame(group_addr, frame_sa);
  send_directed_frame(nonmatch_addrs[4], frame_sa);
  send_directed_frame(local_addr, frame_sa);
  send_directed_frame(nonmatch_addrs[5], frame_sa);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, frame_sa);
  send_directed_frame(group_addr, frame_sa);
  send_directed_frame(48'hDE_AD_BE_EF_00_05, frame_sa);
endtask

// =============================================================================
// MODE 4: Constrained-random combined — 4-class weighted DA selection
//
// Randomly selects address classes with weighted distribution and sends
// constrained-random frames.  Backward-compatible with all existing tests.
//
// Distribution: LOCAL 30%, GROUP 20%, BROADCAST 30%, RANDOM_UNI 20%
// =============================================================================
task rs_addr_filter_boundary_seq_c::body_constrained_random();
  repeat (num_frames) begin
    if (!randomize()) `uvm_fatal(get_type_name(),
        "Randomization of constrained-random frame failed")
    send_directed_frame(frame_da, frame_sa);
  end
endtask

// =============================================================================
// MODE 5: Class alternation — local → group → broadcast on consecutive frames
//
// Drives 12 frames: local, group, broadcast repeated 4 times.
// All 12 should be accepted (assuming DUT programmed with matching addresses).
// =============================================================================
task rs_addr_filter_boundary_seq_c::body_class_alternation();
  repeat (4) begin
    send_directed_frame(local_addr, frame_sa);
    send_directed_frame(group_addr, frame_sa);
    send_directed_frame(48'hFF_FF_FF_FF_FF_FF, frame_sa);
  end
endtask

// =============================================================================
// MODE 6: Sustained traffic with non-matching address injection
//
// Phase 1: 10 broadcast frames (sustained stream, all accepted)
// Phase 2: 5 non-matching unicast injected (all dropped)
// Phase 3: 9 alternating local / group / broadcast (all accepted)
//
// Total: 24 frames.  Accepted: 19.  Dropped: 5.
// =============================================================================
task rs_addr_filter_boundary_seq_c::body_sustained_with_injection();

  // Phase 1: sustained broadcast
  repeat (10) begin
    send_directed_frame(48'hFF_FF_FF_FF_FF_FF, frame_sa);
  end

  // Phase 2: inject non-matching unicast (all dropped)
  repeat (5) begin
    if (!randomize(nomatch_addr) with {
          nomatch_addr != local_addr;
          nomatch_addr != group_addr;
          nomatch_addr != 48'hFF_FF_FF_FF_FF_FF;
          nomatch_addr != 48'h01_80_C2_00_00_01;
          nomatch_addr[40] == 1'b0;  // unicast
        })
      `uvm_fatal(get_type_name(), "Randomization of injection address failed")
    send_directed_frame(nomatch_addr, frame_sa);
  end

  // Phase 3: alternating local / group / broadcast
  repeat (3) begin
    send_directed_frame(local_addr, frame_sa);
    send_directed_frame(48'hFF_FF_FF_FF_FF_FF, frame_sa);
    send_directed_frame(group_addr, frame_sa);
  end
endtask
