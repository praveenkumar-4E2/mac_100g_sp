/**
 * @brief Constrained-random RS sequence targeting I/G x U/L bit combinations
 *        with extended coverage modes for address-filtering verification.
 *
 * Systematically generates frames with destination addresses drawn from
 * address classes defined by the I/G (bit 40) and U/L (bit 41) bits of the
 * first DA octet:
 *
 *   IG0_UL0: Global unicast           (I/G=0, U/L=0)
 *   IG0_UL1: Locally administered unicast (I/G=0, U/L=1)
 *   IG1_UL0: Globally administered multicast (I/G=1, U/L=0)
 *   IG1_UL1: Locally administered multicast  (I/G=1, U/L=1)
 *   BROADCAST: All-ones broadcast     (48'hFF_FF_FF_FF_FF_FF)
 *
 * The caller programs the DUT with a local unicast address and group
 * table entries, then passes those values so the sequence can generate
 * matching/non-matching traffic respecting the I/G and U/L bit semantics.
 *
 * Extended modes cover:
 *   - receiveEnabled toggling with local/broadcast/multicast traffic
 *   - Broadcast-only traffic (all-ones DA)
 *   - Consecutive local -> group -> broadcast class switching
 *   - Dynamic multicast table management via APB
 *   - Runtime filter configuration changes
 *   - Directed LSB-first serialization patterns
 *
 * Usage:
 *   rs_addr_filter_ig_ul_seq_c seq;
 *   seq = rs_addr_filter_ig_ul_seq_c::type_id::create("seq");
 *   seq.local_addr    = 48'h00_00_02_00_00_AA;
 *   seq.group_addr    = 48'h00_5E_00_01_00_01;
 *   seq.p_apb_seqr    = apb_seqr_h;       // optional: enables register access
 *   seq.start(rs_seqr_h);
 */
class rs_addr_filter_ig_ul_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(rs_addr_filter_ig_ul_seq_c)

  // ---- Address class enumeration (I/G x U/L + broadcast) ----
  typedef enum bit [2:0] {
    IG0_UL0_UNICAST_GLOBAL   = 3'b000,  // I/G=0, U/L=0: global unicast
    IG0_UL1_UNICAST_LOCAL    = 3'b001,  // I/G=0, U/L=1: locally administered unicast
    IG1_UL0_MULTICAST_GLOBAL = 3'b010,  // I/G=1, U/L=0: globally administered multicast
    IG1_UL1_MULTICAST_LOCAL  = 3'b011,  // I/G=1, U/L=1: locally administered multicast
    ADDR_CLASS_BROADCAST     = 3'b100   // FF:FF:FF:FF:FF:FF broadcast
  } addr_ig_ul_class_e;

  // ---- Sequence mode enumeration ----
  typedef enum bit [2:0] {
    MODE_RANDOM_IG_UL   = 3'b000,  // random I/G x U/L + broadcast (default)
    MODE_BROADCAST_ONLY = 3'b001,  // broadcast-only traffic
    MODE_CLASS_SEQUENCE = 3'b010,  // local -> group -> broadcast switching
    MODE_RX_TOGGLE      = 3'b011,  // toggle receiveEnabled mid-traffic
    MODE_MGMT_DYNAMIC   = 3'b100,  // add/remove multicast via APB
    MODE_CONFIG_CHANGES = 3'b101,  // randomize filter config between bursts
    MODE_LB_FIRST       = 3'b110   // directed LSB-first DA/SA patterns
  } seq_mode_e;

  // ---- Caller-set addresses ----
  bit [47:0] local_addr = 48'h02_00_00_00_00_01;
  bit [47:0] group_addr = 48'h00_5E_00_01_00_01;

  // ---- Optional APB sequencer handle (null = no register access) ----
  apb_sequencer_c p_apb_seqr;

  // ---- Multicast table entries to program (managed via APB) ----
  bit [47:0] multicast_table[];
  int unsigned num_multicast_entries = 1;

  // ---- Constrained-random knobs ----
  rand addr_ig_ul_class_e  addr_class;
  rand bit [47:0]          frame_da;
  rand int unsigned        num_addr_frames;
  rand seq_mode_e          seq_mode;

  // ---- Configuration randomization knobs (for MODE_CONFIG_CHANGES) ----
  rand bit cfg_rx_enable;
  rand bit cfg_promiscuous;

  // ---- Filter config distribution knobs ----
  constraint c_knob_bounds {
    num_addr_frames inside {[1 : 50]};
  }

  constraint c_payload_bounds {
    payload_min == 46;
    payload_max == 1500;
  }

  // Mode distribution: weighted toward random I/G x U/L (default mode)
  constraint c_mode_dist {
    seq_mode dist {
      MODE_RANDOM_IG_UL   := 35,
      MODE_BROADCAST_ONLY := 10,
      MODE_CLASS_SEQUENCE := 15,
      MODE_RX_TOGGLE      := 10,
      MODE_MGMT_DYNAMIC   := 10,
      MODE_CONFIG_CHANGES := 10,
      MODE_LB_FIRST       := 10
    };
  }

  // Address-class distribution: 20% each for 5 classes (broadcast included)
  constraint c_ig_ul_dist {
    (seq_mode == MODE_RANDOM_IG_UL) -> {
      addr_class dist {
        IG0_UL0_UNICAST_GLOBAL   := 20,
        IG0_UL1_UNICAST_LOCAL    := 20,
        IG1_UL0_MULTICAST_GLOBAL := 20,
        IG1_UL1_MULTICAST_LOCAL  := 20,
        ADDR_CLASS_BROADCAST     := 20
      };
    }
  }

  // DA must match the selected I/G x U/L class.
  // Bit 40 = I/G bit (0=unicast, 1=multicast)
  // Bit 41 = U/L bit (0=global, 1=locally administered)
  constraint c_da_matches_class {
    (addr_class == IG0_UL0_UNICAST_GLOBAL) -> {
      frame_da[40] == 1'b0;  // I/G = 0 (unicast)
      frame_da[41] == 1'b0;  // U/L = 0 (global)
      frame_da != local_addr;
      frame_da != group_addr;
      frame_da != 48'hFF_FF_FF_FF_FF_FF;
      frame_da != 48'h01_80_C2_00_00_01;
    }
    (addr_class == IG0_UL1_UNICAST_LOCAL) -> {
      frame_da[40] == 1'b0;  // I/G = 0 (unicast)
      frame_da[41] == 1'b1;  // U/L = 1 (locally administered)
      frame_da != local_addr;
      frame_da != group_addr;
      frame_da != 48'hFF_FF_FF_FF_FF_FF;
      frame_da != 48'h01_80_C2_00_00_01;
    }
    (addr_class == IG1_UL0_MULTICAST_GLOBAL) -> {
      frame_da[40] == 1'b1;  // I/G = 1 (multicast)
      frame_da[41] == 1'b0;  // U/L = 0 (global)
      frame_da != group_addr;
      frame_da != 48'hFF_FF_FF_FF_FF_FF;
      frame_da != 48'h01_80_C2_00_00_01;
    }
    (addr_class == IG1_UL1_MULTICAST_LOCAL) -> {
      frame_da[40] == 1'b1;  // I/G = 1 (multicast)
      frame_da[41] == 1'b1;  // U/L = 1 (locally administered)
      frame_da != group_addr;
      frame_da != 48'hFF_FF_FF_FF_FF_FF;
      frame_da != 48'h01_80_C2_00_00_01;
    }
    (addr_class == ADDR_CLASS_BROADCAST) -> {
      frame_da == 48'hFF_FF_FF_FF_FF_FF;
    }
  }

  extern function new(string name = "rs_addr_filter_ig_ul_seq_c");
  extern task body();

  // ---- APB register-access helpers ----
  extern task apb_write_reg(bit [15:0] addr, bit [31:0] data);
  extern task program_initial_config();
  extern task write_global_control(bit rx_en, bit promiscuous);
  extern task write_group_entry(int unsigned index, bit [47:0] addr, bit valid);
  extern task clear_group_entry(int unsigned index);

  // ---- Mode-specific body sub-tasks ----
  extern task body_random_ig_ul();
  extern task body_broadcast_only();
  extern task body_class_sequence();
  extern task body_rx_toggle();
  extern task body_mgmt_dynamic();
  extern task body_config_changes();
  extern task body_lb_first();

  // ---- Directed pattern helpers ----
  extern task send_directed_frame(bit [47:0] da, bit [47:0] sa);
  extern task send_directed_frame_with_sa(bit [47:0] da, bit [47:0] sa);
endclass

function rs_addr_filter_ig_ul_seq_c::new(string name = "rs_addr_filter_ig_ul_seq_c");
  super.new(name);
endfunction

// ============================================================================
// APB register-access helpers
// ============================================================================

/**
 * @brief Writes one 32-bit APB register.
 *
 * Creates and starts an apb_write_sequence_c on the caller-supplied
 * APB sequencer.  Silently skipped when p_apb_seqr is null.
 */
task rs_addr_filter_ig_ul_seq_c::apb_write_reg(bit [15:0] addr, bit [31:0] data);
  apb_write_sequence_c wr;
  if (p_apb_seqr == null) return;
  wr = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  wr.m_addr  = addr;
  wr.m_wdata = data;
  wr.start(p_apb_seqr);
endtask

/**
 * @brief Programs the DUT with initial address-filter configuration.
 *
 * Programs the local MAC address, multicast group table entries, and
 * global control register (RX enable, promiscuous off).
 */
task rs_addr_filter_ig_ul_seq_c::program_initial_config();
  // Program local MAC address
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW,  {32{1'b0}} | local_addr[31:0]);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, {32{1'b0}} | local_addr[47:32]);

  // Program multicast group table entries
  foreach (multicast_table[i]) begin
    if (i < num_multicast_entries)
      write_group_entry(i, multicast_table[i], 1'b1);
  end

  // Enable RX, disable promiscuous
  write_global_control(1'b1, 1'b0);
endtask

/**
 * @brief Writes the REG_GLOBAL_CONTROL register.
 *
 * Bit 0 = CTRL_RX (receive enable), Bit 7 = CTRL_PROMISCUOUS.
 */
task rs_addr_filter_ig_ul_seq_c::write_global_control(bit rx_en, bit promiscuous);
  bit [31:0] ctrl_val;
  ctrl_val = (32'h1 << reg_map_pkg::CTRL_RX_BIT);
  if (promiscuous)
    ctrl_val |= (32'h1 << reg_map_pkg::CTRL_PROMISCUOUS_BIT);
  if (!rx_en)
    ctrl_val &= ~(32'h1 << reg_map_pkg::CTRL_RX_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl_val);
endtask

/**
 * @brief Programs one multicast group table entry.
 *
 * Register encoding:
 *   group_low  [31:0] = addr[31:0]
 *   group_high [15:0] = addr[47:32],  group_high[16] = valid
 */
task rs_addr_filter_ig_ul_seq_c::write_group_entry(
    int unsigned index, bit [47:0] addr, bit valid);
  bit [31:0] high_word;
  high_word = {15'b0, valid, addr[47:32]};
  apb_write_reg(reg_map_pkg::group_low_addr(index),  {32{1'b0}} | addr[31:0]);
  apb_write_reg(reg_map_pkg::group_high_addr(index), high_word);
endtask

/**
 * @brief Clears one multicast group table entry (valid=0, addr=0).
 */
task rs_addr_filter_ig_ul_seq_c::clear_group_entry(int unsigned index);
  apb_write_reg(reg_map_pkg::group_low_addr(index),  32'h0);
  apb_write_reg(reg_map_pkg::group_high_addr(index), 32'h0);
endtask

// ============================================================================
// Frame-sending helpers
// ============================================================================

/**
 * @brief Drives one clean frame with explicit DA and default SA.
 */
task rs_addr_filter_ig_ul_seq_c::send_directed_frame(bit [47:0] da, bit [47:0] sa);
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
 * @brief Drives one clean frame with explicit DA and SA (LSB-first check).
 */
task rs_addr_filter_ig_ul_seq_c::send_directed_frame_with_sa(
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
    `uvm_fatal(get_type_name(), "Randomization of directed frame with SA failed")
  do_rs_frame(frm);
  if (inter_frame_delay > 0) #inter_frame_delay;
endtask

// ============================================================================
// Main body: dispatches to mode-specific sub-tasks
// ============================================================================

task rs_addr_filter_ig_ul_seq_c::body();
  payload_min = 46;
  payload_max = 1500;

  // Program initial DUT configuration if APB is available
  if (p_apb_seqr != null)
    program_initial_config();

  // Dispatch to mode-specific sub-task
  case (seq_mode)
    MODE_RANDOM_IG_UL:   body_random_ig_ul();
    MODE_BROADCAST_ONLY: body_broadcast_only();
    MODE_CLASS_SEQUENCE: body_class_sequence();
    MODE_RX_TOGGLE:      body_rx_toggle();
    MODE_MGMT_DYNAMIC:   body_mgmt_dynamic();
    MODE_CONFIG_CHANGES: body_config_changes();
    MODE_LB_FIRST:       body_lb_first();
    default:             body_random_ig_ul();
  endcase
endtask

// ============================================================================
// MODE 0: Random I/G x U/L + broadcast (original behavior, 5-class variant)
// ============================================================================

task rs_addr_filter_ig_ul_seq_c::body_random_ig_ul();
  repeat (num_addr_frames) begin
    if (!randomize()) `uvm_fatal(get_type_name(), "Randomization of ig_ul frame failed")
    send_clean_frame(-1, frame_da);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

// ============================================================================
// MODE 1: Broadcast-only traffic (iteration 2 fix: all-ones broadcast)
// ============================================================================

task rs_addr_filter_ig_ul_seq_c::body_broadcast_only();
  repeat (num_addr_frames) begin
    send_clean_frame(-1, 48'hFF_FF_FF_FF_FF_FF);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

// ============================================================================
// MODE 2: Consecutive class switching: local -> group -> broadcast (iteration 5 fix)
// ============================================================================

task rs_addr_filter_ig_ul_seq_c::body_class_sequence();
  int unsigned frames_per_class;
  int unsigned total_sent;

  frames_per_class = (num_addr_frames + 2) / 3;
  total_sent = 0;

  // Phase 1: local unicast frames
  repeat (frames_per_class) begin
    if (total_sent >= num_addr_frames) break;
    send_clean_frame(-1, local_addr);
    total_sent++;
  end

  // Phase 2: group (active multicast) frames
  repeat (frames_per_class) begin
    if (total_sent >= num_addr_frames) break;
    send_clean_frame(-1, group_addr);
    total_sent++;
  end

  // Phase 3: broadcast frames
  repeat (frames_per_class) begin
    if (total_sent >= num_addr_frames) break;
    send_clean_frame(-1, 48'hFF_FF_FF_FF_FF_FF);
    total_sent++;
  end
endtask

// ============================================================================
// MODE 3: Toggle receiveEnabled with local/broadcast/multicast (iteration 1 fix)
// ============================================================================

task rs_addr_filter_ig_ul_seq_c::body_rx_toggle();
  int unsigned frames_per_phase;

  if (p_apb_seqr == null) begin
    `uvm_warning(get_type_name(),
      "MODE_RX_TOGGLE requires p_apb_seqr; falling back to random I/G x U/L")
    body_random_ig_ul();
    return;
  end

  frames_per_phase = (num_addr_frames + 3) / 4;

  // Phase 1: RX enabled, send local unicast
  write_global_control(1'b1, 1'b0);
  repeat (frames_per_phase) begin
    send_clean_frame(-1, local_addr);
  end

  // Phase 2: RX enabled, send broadcast
  repeat (frames_per_phase) begin
    send_clean_frame(-1, 48'hFF_FF_FF_FF_FF_FF);
  end

  // Phase 3: RX enabled, send active multicast (group_addr)
  repeat (frames_per_phase) begin
    send_clean_frame(-1, group_addr);
  end

  // Phase 4: RX DISABLED, send local + broadcast + multicast
  write_global_control(1'b0, 1'b0);
  send_clean_frame(-1, local_addr);
  send_clean_frame(-1, 48'hFF_FF_FF_FF_FF_FF);
  send_clean_frame(-1, group_addr);

  // Phase 5: RX re-enabled, send same traffic again
  write_global_control(1'b1, 1'b0);
  repeat (2) begin
    send_clean_frame(-1, local_addr);
    send_clean_frame(-1, 48'hFF_FF_FF_FF_FF_FF);
    send_clean_frame(-1, group_addr);
  end

  // Phase 6: RX disabled then re-enabled mid-burst
  write_global_control(1'b0, 1'b0);
  send_clean_frame(-1, local_addr);
  write_global_control(1'b1, 1'b0);
  send_clean_frame(-1, local_addr);
endtask

// ============================================================================
// MODE 4: Add/remove multicast via management (iteration 3 fix)
// ============================================================================

task rs_addr_filter_ig_ul_seq_c::body_mgmt_dynamic();
  bit [47:0] temp_group;

  if (p_apb_seqr == null) begin
    `uvm_warning(get_type_name(),
      "MODE_MGMT_DYNAMIC requires p_apb_seqr; falling back to random I/G x U/L")
    body_random_ig_ul();
    return;
  end

  // Step 1: Program a new multicast entry (index 0) via APB
  write_group_entry(0, group_addr, 1'b1);

  // Step 2: Send frames matching the new entry
  repeat (num_addr_frames / 3) begin
    send_clean_frame(-1, group_addr);
  end

  // Step 3: Remove the multicast entry (clear valid bit)
  clear_group_entry(0);

  // Step 4: Send frames matching the now-inactive entry
  repeat (num_addr_frames / 3) begin
    send_clean_frame(-1, group_addr);
  end

  // Step 5: Re-add the entry with a different address
  temp_group = group_addr ^ 48'h00_00_00_00_00_01;  // toggle LSB
  write_group_entry(0, temp_group, 1'b1);

  // Step 6: Send frames matching the new address
  repeat (num_addr_frames / 3) begin
    send_clean_frame(-1, temp_group);
  end

  // Step 7: Add a second entry (index 1) while index 0 is still active
  write_group_entry(1, group_addr, 1'b1);

  // Step 8: Send mixed traffic for both entries
  repeat (num_addr_frames / 3) begin
    send_clean_frame(-1, temp_group);
    send_clean_frame(-1, group_addr);
  end

  // Step 9: Remove both entries
  clear_group_entry(0);
  clear_group_entry(1);

  // Step 10: Send traffic that no longer matches any entry
  repeat (num_addr_frames / 4) begin
    send_clean_frame(-1, temp_group);
    send_clean_frame(-1, group_addr);
  end
endtask

// ============================================================================
// MODE 5: Configuration changes between transactions (iteration 6/7 fix)
// ============================================================================

task rs_addr_filter_ig_ul_seq_c::body_config_changes();
  bit [31:0] ctrl_val;

  if (p_apb_seqr == null) begin
    `uvm_warning(get_type_name(),
      "MODE_CONFIG_CHANGES requires p_apb_seqr; falling back to random I/G x U/L")
    body_random_ig_ul();
    return;
  end

  // Burst 1: RX on, promiscuous off, local traffic
  write_global_control(1'b1, 1'b0);
  repeat (num_addr_frames / 5) begin
    send_clean_frame(-1, local_addr);
  end

  // Burst 2: RX on, promiscuous ON, random non-matching unicast
  write_global_control(1'b1, 1'b1);
  repeat (num_addr_frames / 5) begin
    send_clean_frame(-1, 48'h0A_00_00_00_00_01);
  end

  // Burst 3: Randomize rx_enable and promiscuous between each frame
  repeat (num_addr_frames / 5) begin
    if (!randomize(cfg_rx_enable, cfg_promiscuous))
      `uvm_fatal(get_type_name(), "Randomization of filter config failed")
    write_global_control(cfg_rx_enable, cfg_promiscuous);
    send_clean_frame(-1, local_addr);
  end

  // Burst 4: Toggle promiscuous on/off between frames
  repeat (num_addr_frames / 5) begin
    write_global_control(1'b1, 1'b1);
    send_clean_frame(-1, 48'h0A_00_00_00_00_02);
    write_global_control(1'b1, 1'b0);
    send_clean_frame(-1, 48'h0A_00_00_00_00_03);
  end

  // Burst 5: Toggle RX enable between frames with multicast traffic
  repeat (num_addr_frames / 5) begin
    write_global_control(1'b1, 1'b0);
    send_clean_frame(-1, group_addr);
    write_global_control(1'b0, 1'b0);
    send_clean_frame(-1, group_addr);
  end

  // Restore normal operation
  write_global_control(1'b1, 1'b0);
endtask

// ============================================================================
// MODE 6: Directed LSB-first DA/SA serialization checking (iteration 4 fix)
// ============================================================================

task rs_addr_filter_ig_ul_seq_c::body_lb_first();
  bit [47:0] lb_patterns[];
  bit [47:0] sa_pattern;

  // LSB-first directed bit patterns for serialization verification
  lb_patterns = '{
    48'h00_00_00_00_00_01,  // bit 0 set (LSB-first: first bit on wire)
    48'h00_00_00_00_00_02,  // bit 1
    48'h00_00_00_00_00_04,  // bit 2
    48'h00_00_00_00_00_08,  // bit 3
    48'h00_00_00_00_00_10,  // bit 4
    48'h00_00_00_00_00_20,  // bit 5
    48'h00_00_00_00_00_40,  // bit 6
    48'h00_00_00_00_00_80,  // bit 7 (end of first octet)
    48'h00_00_00_00_01_00,  // bit 8 (start of second octet)
    48'h00_00_00_00_02_00,  // bit 9
    48'h00_00_00_01_00_00,  // bit 16
    48'h00_00_01_00_00_00,  // bit 24
    48'h00_01_00_00_00_00,  // bit 32
    48'h01_00_00_00_00_00,  // bit 40 (I/G bit = 0, U/L bit varies)
    48'hFF_FF_FF_FF_FF_FF,  // all ones
    48'h00_00_00_00_00_00,  // all zeros
    48'h55_55_55_55_55_55,  // alternating 01
    48'hAA_AA_AA_AA_AA_AA   // alternating 10
  };

  // Alternate SA pattern between two values for cross-checking
  sa_pattern = 48'h02_00_00_00_00_01;

  // Drive each directed pattern
  foreach (lb_patterns[i]) begin
    // Alternate SA to stress serialization
    if (i[0])
      sa_pattern = 48'h02_00_00_00_00_02;
    else
      sa_pattern = 48'h02_00_00_00_00_01;

    send_directed_frame_with_sa(lb_patterns[i], sa_pattern);
  end

  // Additional: neighbor-of-local pattern (local_addr +/- 1)
  send_directed_frame(local_addr - 1, 48'h02_00_00_00_00_01);
  send_directed_frame(local_addr + 1, 48'h02_00_00_00_00_01);

  // Additional: single-bit-different patterns (Hamming distance 1 from local)
  send_directed_frame(local_addr ^ 48'h00_00_00_00_00_01, 48'h02_00_00_00_00_01);
  send_directed_frame(local_addr ^ 48'h00_00_00_00_01_00, 48'h02_00_00_00_00_01);
  send_directed_frame(local_addr ^ 48'h00_00_00_01_00_00, 48'h02_00_00_00_00_01);
  send_directed_frame(local_addr ^ 48'h00_00_01_00_00_00, 48'h02_00_00_00_00_01);
  send_directed_frame(local_addr ^ 48'h00_01_00_00_00_00, 48'h02_00_00_00_00_01);
  send_directed_frame(local_addr ^ 48'h01_00_00_00_00_00, 48'h02_00_00_00_00_01);

  // Constrained-random remaining frames (fill rest of num_addr_frames)
  if (num_addr_frames > lb_patterns.size() + 8) begin
    repeat (num_addr_frames - lb_patterns.size() - 8) begin
      if (!randomize()) `uvm_fatal(get_type_name(), "Randomization of lb_first frame failed")
      send_clean_frame(-1, frame_da);
    end
  end
endtask
