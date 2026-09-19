/**
 * @brief Comprehensive RS sequence for address-filtering verification.
 *
 * Drives frames across six operating modes covering every address-filter
 * scenario: basic configuration, address-class coverage, promiscuous-mode
 * interaction, 48-bit DA/SA boundary patterns, toggle/stress sequences,
 * and constrained-random mixed traffic.
 *
 * The sequence is pure stimulus — it contains NO APB register accesses.
 * The caller programs the DUT (local address, group table, promiscuous
 * mode, RX enable) before starting the sequence, and re-programs between
 * runs when testing dynamic configuration changes.
 *
 * Usage:
 *   rs_addr_filter_sequence_c seq;
 *   seq = rs_addr_filter_sequence_c::type_id::create("seq");
 *   seq.local_addr      = 48'h00_00_02_00_00_AA;
 *   seq.group_addr      = 48'h00_5E_00_01_00_01;
 *   seq.num_addr_frames = 30;
 *   seq.seq_mode        = rs_addr_filter_sequence_c::MODE_RANDOM_COMBINED;
 *   seq.start(rs_seqr_h);
 */
class rs_addr_filter_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(rs_addr_filter_sequence_c)

  // =========================================================================
  // Address class enumeration (existing, unchanged for backward-compat)
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
    MODE_BASIC_CONFIG     = 3'b000,
    MODE_ADDR_CLASSES     = 3'b001,
    MODE_PROMISCUOUS      = 3'b010,
    MODE_BOUNDARY_PATTERN = 3'b011,
    MODE_TOGGLE_STRESS    = 3'b100,
    MODE_RANDOM_COMBINED  = 3'b101
  } seq_mode_e;

  // =========================================================================
  // Boundary-pattern enumeration (10 patterns)
  // =========================================================================
  typedef enum bit [3:0] {
    PAT_ZERO         = 4'd0,
    PAT_ALL_ONES     = 4'd1,
    PAT_ALT_55       = 4'd2,
    PAT_ALT_AA       = 4'd3,
    PAT_TARGET_M2    = 4'd4,
    PAT_TARGET_M1    = 4'd5,
    PAT_TARGET       = 4'd6,
    PAT_TARGET_P1    = 4'd7,
    PAT_TARGET_P2    = 4'd8,
    PAT_RANDOM       = 4'd9
  } pattern_e;

  // =========================================================================
  // Caller-set addresses
  // =========================================================================
  bit [47:0] local_addr = 48'h02_00_00_00_00_01;
  bit [47:0] group_addr = 48'h00_5E_00_01_00_01;

  // =========================================================================
  // Constrained-random knobs
  // =========================================================================
  seq_mode_e          seq_mode = MODE_RANDOM_COMBINED;
  rand addr_class_e   addr_class;
  rand bit [47:0]     frame_da;
  rand bit [47:0]     frame_sa;
  rand int unsigned   num_addr_frames;
  rand int unsigned   num_burst_frames;
  rand pattern_e      da_pattern;

  // =========================================================================
  // Constraints
  // =========================================================================

  constraint c_knob_bounds {
    num_addr_frames inside {[1 : 50]};
    num_burst_frames inside {[1 : 20]};
  }

  constraint c_payload_bounds {
    payload_min == 46;
    payload_max == 1500;
  }

  // Address-class distribution (used by MODE_RANDOM_COMBINED)
  constraint c_addr_class_dist {
    addr_class dist {
      ADDR_CLASS_LOCAL      := 30,
      ADDR_CLASS_GROUP      := 20,
      ADDR_CLASS_BROADCAST  := 30,
      ADDR_CLASS_RANDOM_UNI := 20
    };
  }

  // DA must match the selected address class (MODE_RANDOM_COMBINED)
  constraint c_da_matches_class {
    (seq_mode == MODE_RANDOM_COMBINED) -> {
      (addr_class == ADDR_CLASS_LOCAL)      -> frame_da == local_addr;
      (addr_class == ADDR_CLASS_GROUP)      -> frame_da == group_addr;
      (addr_class == ADDR_CLASS_BROADCAST)  -> frame_da == 48'hFF_FF_FF_FF_FF_FF;
      (addr_class == ADDR_CLASS_RANDOM_UNI) -> {
        frame_da != local_addr;
        frame_da != group_addr;
        frame_da != 48'hFF_FF_FF_FF_FF_FF;
        frame_da != 48'h01_80_C2_00_00_01;
        frame_da[40] == 1'b0;
      }
    }
  }

  // DA must match the selected boundary pattern
  constraint c_da_matches_pattern {
    (seq_mode == MODE_BOUNDARY_PATTERN) -> {
      (da_pattern == PAT_ZERO)      -> frame_da == 48'h00_00_00_00_00_00;
      (da_pattern == PAT_ALL_ONES)  -> frame_da == 48'hFF_FF_FF_FF_FF_FF;
      (da_pattern == PAT_ALT_55)    -> frame_da == 48'h55_55_55_55_55_55;
      (da_pattern == PAT_ALT_AA)    -> frame_da == 48'hAA_AA_AA_AA_AA_AA;
      (da_pattern == PAT_TARGET_M2) -> frame_da == (local_addr - 48'd2);
      (da_pattern == PAT_TARGET_M1) -> frame_da == (local_addr - 48'd1);
      (da_pattern == PAT_TARGET)    -> frame_da == local_addr;
      (da_pattern == PAT_TARGET_P1) -> frame_da == (local_addr + 48'd1);
      (da_pattern == PAT_TARGET_P2) -> frame_da == (local_addr + 48'd2);
      (da_pattern == PAT_RANDOM) -> {
        frame_da != local_addr;
        frame_da != group_addr;
        frame_da != 48'hFF_FF_FF_FF_FF_FF;
        frame_da != 48'h01_80_C2_00_00_01;
        frame_da != (local_addr - 48'd2);
        frame_da != (local_addr - 48'd1);
        frame_da != (local_addr + 48'd1);
        frame_da != (local_addr + 48'd2);
        frame_da[40] == 1'b0;
      }
    }
  }

  // =========================================================================
  // Function / task declarations
  // =========================================================================
  extern function new(string name = "rs_addr_filter_sequence_c");
  extern task body();

  // Frame-sending helpers
  extern task send_directed_frame(bit [47:0] da, bit [47:0] sa);
  extern task send_boundary_frame(bit [47:0] da, bit [47:0] sa);

  // Mode body tasks
  extern task body_basic_config();
  extern task body_addr_classes();
  extern task body_promiscuous();
  extern task body_boundary_pattern();
  extern task body_toggle_stress();
  extern task body_random_combined();
endclass

// =============================================================================
// Constructor
// =============================================================================
function rs_addr_filter_sequence_c::new(string name = "rs_addr_filter_sequence_c");
  super.new(name);
endfunction

// =============================================================================
// Main body — dispatches to mode-specific sub-task
// =============================================================================
task rs_addr_filter_sequence_c::body();
  payload_min = 46;
  payload_max = 1500;
  case (seq_mode)
    MODE_BASIC_CONFIG:     body_basic_config();
    MODE_ADDR_CLASSES:     body_addr_classes();
    MODE_PROMISCUOUS:      body_promiscuous();
    MODE_BOUNDARY_PATTERN: body_boundary_pattern();
    MODE_TOGGLE_STRESS:    body_toggle_stress();
    default:               body_random_combined();
  endcase
endtask

// =============================================================================
// Frame-sending helpers
// =============================================================================

/**
 * @brief Drives one frame with explicit DA and SA using send_clean_frame.
 */
task rs_addr_filter_sequence_c::send_directed_frame(
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

/**
 * @brief Drives one frame with explicit DA and SA, building the frame
 *        manually with computed FCS (for boundary-pattern testing).
 */
task rs_addr_filter_sequence_c::send_boundary_frame(
    bit [47:0] da, bit [47:0] sa);
  frame_xtn_c frm;
  frm            = frame_xtn_c::type_id::create("frm");
  frm.dst_addr   = da;
  frm.src_addr   = sa;
  frm.ether_type = 16'h0800;
  frm.payload    = new[46];
  foreach (frm.payload[i]) frm.payload[i] = 8'hA5;
  frm.insert_fcs      = 1'b1;
  frm.crc_error       = 1'b0;
  frm.length_error    = 1'b0;
  frm.alignment_error = 1'b0;
  frm.fcs             = frm.compute_fcs();
  do_rs_frame(frm);
  if (inter_frame_delay > 0) #inter_frame_delay;
endtask

// =============================================================================
// MODE 0: Basic configuration — valid local-unicast DA, SA, ET, payload, FCS
//
// 5 deterministic frames verifying default address filtering:
//   Frame 1: DA = local_addr       → accepted
//   Frame 2: DA = broadcast        → accepted
//   Frame 3: DA = group_addr       → accepted
//   Frame 4: DA = unrelated        → dropped
//   Frame 5: DA = local_addr ^ 01  → dropped (1-bit near-miss)
// =============================================================================
task rs_addr_filter_sequence_c::body_basic_config();
  send_directed_frame(local_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01);
  send_directed_frame(group_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hDE_AD_BE_EF_00_01, 48'h02_00_00_00_00_01);
  send_directed_frame(local_addr ^ 48'h00_00_00_00_00_01, 48'h02_00_00_00_00_01);
endtask

// =============================================================================
// MODE 1: Address classes — deterministic coverage of all address classes
//
// 6 frames covering local unicast, unrelated unicast, broadcast,
// active multicast, inactive/unconfigured multicast, and near-miss unicast.
//
// Frame 5 uses a multicast address NOT in the group table so it is
// dropped without needing mid-sequence APB reconfiguration.
//
// Expected: 3 accepted (local + bcast + active mcast)
//           3 dropped   (unrelated + inactive mcast + near-miss)
// =============================================================================
task rs_addr_filter_sequence_c::body_addr_classes();
  send_directed_frame(local_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hDE_AD_BE_EF_00_01, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01);
  send_directed_frame(group_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'h01_00_00_00_00_01, 48'h02_00_00_00_00_01);
  send_directed_frame(local_addr ^ 48'h00_00_00_00_00_01, 48'h02_00_00_00_00_01);
endtask

// =============================================================================
// MODE 2: Promiscuous-mode interaction — non-matching unicast only
//
// Sends num_burst_frames of non-matching unicast.  The TEST controls
// promiscuous mode via APB between separate runs of this mode:
//   Run 1 (promiscuous OFF) → all dropped
//   Run 2 (promiscuous ON)  → all accepted
//   Run 3 (promiscuous OFF) → all dropped
// =============================================================================
task rs_addr_filter_sequence_c::body_promiscuous();
  repeat (num_burst_frames) begin
    send_directed_frame(48'hCA_FE_FA_DE_00_01, 48'h02_00_00_00_00_01);
  end
endtask

// =============================================================================
// MODE 3: Boundary / DA extraction — 10 DA patterns × 3 SA patterns
//
// Iterates all 10 boundary-pattern DAs with 3 SA variants (zero, all-ones,
// alternating-55) to verify 48-bit DA and SA extraction across the full
// bit vector.  Frames are built manually with computed FCS.
//
// DA patterns:
//   PAT_ZERO, PAT_ALL_ONES, PAT_ALT_55, PAT_ALT_AA,
//   PAT_TARGET_M2, PAT_TARGET_M1, PAT_TARGET,
//   PAT_TARGET_P1, PAT_TARGET_P2, PAT_RANDOM
//
// SA patterns:
//   48'h00_00_00_00_00_00 (zero)
//   48'hFF_FF_FF_FF_FF_FF (all-ones)
//   48'h55_55_55_55_55_55 (alternating)
//
// Expected accepted (with local_addr programmed): 6 frames
//   PAT_ALL_ONES (broadcast) × 3 SAs + PAT_TARGET (local) × 3 SAs
// =============================================================================
task rs_addr_filter_sequence_c::body_boundary_pattern();
  bit [47:0] sa_list [3] = '{
    48'h00_00_00_00_00_00,
    48'hFF_FF_FF_FF_FF_FF,
    48'h55_55_55_55_55_55
  };

  for (int unsigned p = 0; p < 10; p++) begin
    if (!randomize() with { da_pattern == pattern_e'(p); })
      `uvm_fatal(get_type_name(),
          $sformatf("Randomization of boundary DA pattern %0d failed", p))
    foreach (sa_list[s]) begin
      send_boundary_frame(frame_da, sa_list[s]);
    end
  end
endtask

// =============================================================================
// MODE 4: Toggle / stress — accepted → rejected → accepted + sustained
//
// Phase 1: 3 accepted (local, group, broadcast)
// Phase 2: 3 dropped  (3 different non-matching unicast)
// Phase 3: 3 accepted (local, broadcast, group)
// Phase 4: 10 sustained with injection — alternating accepted/rejected
//   local, nonmatch, bcast, group, nonmatch,
//   local, nonmatch, bcast, group, nonmatch
//
// Total: 19 frames.  Accepted: ~11.  Dropped: ~8.
// =============================================================================
task rs_addr_filter_sequence_c::body_toggle_stress();
  // Phase 1: accepted
  send_directed_frame(local_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(group_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01);

  // Phase 2: rejected
  send_directed_frame(48'hCA_FE_FA_DE_00_01, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hDE_AD_BE_EF_00_02, 48'h02_00_00_00_00_01);
  send_directed_frame(48'h01_02_03_04_05_06, 48'h02_00_00_00_00_01);

  // Phase 3: accepted
  send_directed_frame(local_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01);
  send_directed_frame(group_addr, 48'h02_00_00_00_00_01);

  // Phase 4: sustained with injection
  send_directed_frame(local_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hCA_FE_FA_DE_00_03, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01);
  send_directed_frame(group_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hDE_AD_BE_EF_00_04, 48'h02_00_00_00_00_01);
  send_directed_frame(local_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hCA_FE_FA_DE_00_05, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01);
  send_directed_frame(group_addr, 48'h02_00_00_00_00_01);
  send_directed_frame(48'hDE_AD_BE_EF_00_06, 48'h02_00_00_00_00_01);
endtask

// =============================================================================
// MODE 5: Constrained-random combined — existing 4-class behavior
//
// Default mode.  Randomly selects address classes with weighted distribution
// and sends constrained-random frames.  Backward-compatible with all existing
// tests that instantiate this sequence without setting seq_mode.
// =============================================================================
task rs_addr_filter_sequence_c::body_random_combined();
  repeat (num_addr_frames) begin
    if (!randomize()) `uvm_fatal(get_type_name(),
        "Randomization of addr_filter frame failed")
    send_clean_frame(-1, frame_da);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask
