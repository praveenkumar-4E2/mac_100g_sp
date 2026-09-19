/**
 * @brief Consolidated MAC Control frame sequence.
 *
 * Single class with mode-based dispatch.  Builds and drives IEEE 802.3
 * MAC Control frames (EtherType 0x8808) or normal data frames
 * (EtherType 0x002E) on the RS line-side interface.
 *
 * The caller sets the mode and relevant fields, then invokes .start()
 * on an RS active sequencer.  The body() method dispatches to the
 * appropriate scenario method based on the mode setting.
 */
class mac_control_frame_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_control_frame_sequence_c)

  // ---------------------------------------------------------------------------
  // Mode enumeration
  // ---------------------------------------------------------------------------
  typedef enum bit [3:0] {
    MODE_GENERIC            = 4'd0,
    MODE_UNSUPPORTED_OPCODE = 4'd1,
    MODE_ALT_ADDR           = 4'd2,
    MODE_RANDOM             = 4'd3,
    MODE_INDICATION         = 4'd4,
    MODE_TRANSPARENCY       = 4'd5,
    MODE_CLAUSE64           = 4'd6,
    MODE_SUSTAINED          = 4'd7,
    MODE_ADDR_CHANGE        = 4'd8,
    MODE_CONSECUTIVE_ADDR   = 4'd9
  } mode_e;

  // ---------------------------------------------------------------------------
  // Sub-type enumerations
  // ---------------------------------------------------------------------------
  typedef enum bit [1:0] {
    ALT_UNICAST = 2'b00,
    ALT_GROUP   = 2'b01,
    ALT_BCAST   = 2'b10
  } alt_addr_class_e;

  typedef enum bit [1:0] {
    RAND_DA_PAUSE_MCAST = 2'b00,
    RAND_DA_UNICAST     = 2'b01,
    RAND_DA_GROUP       = 2'b10,
    RAND_DA_BCAST       = 2'b11
  } rand_da_class_e;

  typedef enum bit [2:0] {
    CL64_QUANTA_ZERO  = 3'b000,
    CL64_BACK_TO_BACK = 3'b001,
    CL64_MAX_QUANTA   = 3'b010,
    CL64_TIMER_EXPIRY = 3'b011
  } cl64_mode_e;

  // ---------------------------------------------------------------------------
  // Configuration fields
  // ---------------------------------------------------------------------------
  mode_e mode = MODE_GENERIC;

  // Generic / indication / clause64 fields
  bit [15:0]  opcode            = 16'h0001;
  bit [47:0]  ctrl_da           = 48'h01_80_C2_00_00_01;
  bit [47:0]  ctrl_sa           = 48'h02_00_00_00_00_01;
  bit [15:0]  pause_quanta      = 16'h0100;
  int unsigned frame_payload_len = 46;

  // Unsupported opcode fields
  rand bit [15:0]  unsup_opcode;
  bit [47:0]       unsup_da           = 48'h01_80_C2_00_00_01;
  bit [47:0]       unsup_sa           = 48'h02_00_00_00_00_01;
  int unsigned     unsup_payload_len  = 46;

  constraint c_unsup_opcode {
    unsup_opcode inside {
      16'h0002, 16'h0003, 16'h0004, 16'h0005,
      16'h0006, 16'h0007, 16'h0008, 16'h00FF,
      16'hFFFE, 16'hFFFF
    };
  }

  // Alt addr fields
  rand alt_addr_class_e  alt_addr_class;
  rand bit [47:0]        alt_da;
  bit [47:0]             alt_sa           = 48'h02_00_00_00_00_01;
  bit [15:0]             alt_opcode       = 16'h0001;
  bit [15:0]             alt_quanta       = 16'h0100;
  int unsigned           alt_payload_len  = 46;

  constraint c_addr_class_dist {
    alt_addr_class dist {
      ALT_UNICAST := 40,
      ALT_GROUP   := 30,
      ALT_BCAST   := 30
    };
  }

  constraint c_da_matches_class {
    (alt_addr_class == ALT_UNICAST) -> {
      alt_da[40] == 1'b0;
      alt_da != 48'h01_80_C2_00_00_01;
    }
    (alt_addr_class == ALT_GROUP) -> {
      alt_da[40] == 1'b1;
      alt_da != 48'hFF_FF_FF_FF_FF_FF;
      alt_da != 48'h01_80_C2_00_00_01;
    }
    (alt_addr_class == ALT_BCAST) -> {
      alt_da == 48'hFF_FF_FF_FF_FF_FF;
    }
  }

  // Random frame fields
  rand bit [15:0]       rand_opcode;
  rand rand_da_class_e  rand_da_class;
  rand bit [47:0]       rand_da;
  rand bit [47:0]       rand_sa;
  rand bit [15:0]       rand_quanta;
  rand int unsigned     rand_payload_len;

  constraint c_opcode_dist {
    rand_opcode dist {
      16'h0001 := 60,
      16'h0002 := 5,
      16'h0003 := 5,
      16'h0004 := 5,
      16'h0005 := 5,
      16'h0007 := 5,
      16'h00FF := 5,
      16'hFFFF := 5,
      16'hFFFE := 5
    };
  }

  constraint c_rand_da_class_dist {
    rand_da_class dist {
      RAND_DA_PAUSE_MCAST := 50,
      RAND_DA_UNICAST     := 20,
      RAND_DA_GROUP       := 15,
      RAND_DA_BCAST       := 15
    };
  }

  constraint c_rand_da_matches_class {
    (rand_da_class == RAND_DA_PAUSE_MCAST) -> rand_da == 48'h01_80_C2_00_00_01;
    (rand_da_class == RAND_DA_UNICAST) -> {
      rand_da[40] == 1'b0;
      rand_da != 48'h01_80_C2_00_00_01;
      rand_da != 48'hFF_FF_FF_FF_FF_FF;
    }
    (rand_da_class == RAND_DA_GROUP) -> {
      rand_da[40] == 1'b1;
      rand_da != 48'hFF_FF_FF_FF_FF_FF;
      rand_da != 48'h01_80_C2_00_00_01;
    }
    (rand_da_class == RAND_DA_BCAST) -> rand_da == 48'hFF_FF_FF_FF_FF_FF;
  }

  constraint c_sa_not_pause {
    rand_sa != 48'h01_80_C2_00_00_01;
  }

  constraint c_rand_payload_len {
    rand_payload_len inside {[46 : 200]};
  }

  // Clause64 fields
  rand cl64_mode_e  cl64_mode;
  bit [47:0]        cl64_da           = 48'h01_80_C2_00_00_01;
  bit [47:0]        cl64_sa           = 48'h02_00_00_00_00_01;
  int unsigned      cl64_payload_len  = 46;

  constraint c_cl64_mode_dist {
    cl64_mode dist {
      CL64_QUANTA_ZERO  := 25,
      CL64_BACK_TO_BACK := 25,
      CL64_MAX_QUANTA   := 25,
      CL64_TIMER_EXPIRY := 25
    };
  }

  // Transparency fields
  int unsigned num_data_frames  = 5;
  int unsigned num_pause_frames = 2;
  bit          data_broadcast   = 1'b1;
  int unsigned data_payload_min = 46;
  int unsigned data_payload_max = 100;

  // Sustained traffic fields
  int unsigned num_bcast_burst1 = 10;
  int unsigned num_pause        = 3;
  int unsigned num_nonmatch     = 5;
  int unsigned num_bcast_burst2 = 5;
  bit [47:0]   nonmatch_da      = 48'hDE_AD_BE_EF_00_01;
  int unsigned sust_payload_min = 46;
  int unsigned sust_payload_max = 150;

  // Address change fields
  bit [47:0]  target_da_before = 48'h00_00_02_00_00_AA;
  bit [47:0]  target_da_after  = 48'h00_00_03_00_00_BB;
  int unsigned chg_payload_min = 46;
  int unsigned chg_payload_max = 100;

  // Indication fields
  bit [47:0]  ind_da           = 48'h01_80_C2_00_00_01;
  bit [47:0]  ind_sa           = 48'h02_00_00_00_00_01;
  bit [15:0]  ind_pause_quanta = 16'h0100;

  // Consecutive address class fields
  bit [47:0] local_unicast_da = 48'h00_00_02_00_00_AA;
  bit [47:0] group_da         = 48'h00_5E_00_01_00_01;
  bit [47:0] broadcast_da     = 48'hFF_FF_FF_FF_FF_FF;
  bit [47:0] nonmatch_uc_da   = 48'hDE_AD_BE_EF_00_01;
  int unsigned consec_payload_min = 46;
  int unsigned consec_payload_max = 100;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  extern function new(string name = "mac_control_frame_sequence_c");

  // ---------------------------------------------------------------------------
  // Main body — dispatches to scenario method
  // ---------------------------------------------------------------------------
  extern task body();

  // ---------------------------------------------------------------------------
  // Helper: build and drive a single MAC Control frame (EtherType 0x8808)
  // ---------------------------------------------------------------------------
  extern task drive_ctrl_frame(bit [15:0] opcode,
                               bit [47:0] da,
                               bit [47:0] sa,
                               bit [15:0] quanta,
                               int unsigned payload_len);

  // ---------------------------------------------------------------------------
  // Helper: build and drive a single normal data frame (EtherType 0x002E)
  // ---------------------------------------------------------------------------
  extern task drive_data_frame(bit [47:0] da,
                               bit [47:0] sa,
                               int unsigned payload_len);

  // ---------------------------------------------------------------------------
  // Helper: build and drive a PAUSE frame (opcode 0x0001)
  // ---------------------------------------------------------------------------
  extern task drive_pause_frame(bit [47:0] da, bit [47:0] sa, bit [15:0] quanta);

  // ---------------------------------------------------------------------------
  // Scenario methods
  // ---------------------------------------------------------------------------
  extern local task run_generic();
  extern local task run_unsupported_opcode();
  extern local task run_alt_addr();
  extern local task run_random();
  extern local task run_indication();
  extern local task run_transparency();
  extern local task run_clause64();
  extern local task run_sustained();
  extern local task run_addr_change();
  extern local task run_consecutive_addr();
endclass

// =============================================================================
// Constructor
// =============================================================================
function mac_control_frame_sequence_c::new(string name = "mac_control_frame_sequence_c");
  super.new(name);
endfunction

// =============================================================================
// body — dispatch based on mode
// =============================================================================
task mac_control_frame_sequence_c::body();
  case (mode)
    MODE_GENERIC:            run_generic();
    MODE_UNSUPPORTED_OPCODE: run_unsupported_opcode();
    MODE_ALT_ADDR:           run_alt_addr();
    MODE_RANDOM:             run_random();
    MODE_INDICATION:         run_indication();
    MODE_TRANSPARENCY:       run_transparency();
    MODE_CLAUSE64:           run_clause64();
    MODE_SUSTAINED:          run_sustained();
    MODE_ADDR_CHANGE:        run_addr_change();
    MODE_CONSECUTIVE_ADDR:   run_consecutive_addr();
    default:                 run_generic();
  endcase
endtask

// =============================================================================
// Helpers
// =============================================================================
task mac_control_frame_sequence_c::drive_ctrl_frame(
    bit [15:0] opcode,
    bit [47:0] da,
    bit [47:0] sa,
    bit [15:0] quanta,
    int unsigned payload_len);
  frame_xtn_c frm;
  frm            = frame_xtn_c::type_id::create("ctrl_frm");
  frm.dst_addr   = da;
  frm.src_addr   = sa;
  frm.ether_type = 16'h8808;
  frm.payload    = new[payload_len];
  frm.payload[0] = opcode[15:8];
  frm.payload[1] = opcode[7:0];

  if (opcode == 16'h0001) begin
    frm.payload[2] = quanta[15:8];
    frm.payload[3] = quanta[7:0];
  end
  foreach (frm.payload[i])
    if (i > 3) frm.payload[i] = 8'h00;
  frm.insert_fcs      = 1'b1;
  frm.crc_error       = 1'b0;
  frm.length_error    = 1'b0;
  frm.alignment_error = 1'b0;
  frm.fcs             = frm.compute_fcs();
  do_rs_frame(frm);
endtask

task mac_control_frame_sequence_c::drive_data_frame(
    bit [47:0] da,
    bit [47:0] sa,
    int unsigned payload_len);
  frame_xtn_c frm;
  frm            = frame_xtn_c::type_id::create("data_frm");
  frm.dst_addr   = da;
  frm.src_addr   = sa;
  frm.ether_type = 16'h00_2E;
  frm.payload = new[payload_len];
  foreach (frm.payload[i])
  frm.payload[i] = $urandom_range(0, 255);
  frm.insert_fcs      = 1'b1;
  frm.crc_error       = 1'b0;
  frm.length_error    = 1'b0;
  frm.alignment_error = 1'b0;
  frm.fcs             = frm.compute_fcs();
  do_rs_frame(frm);
endtask

task mac_control_frame_sequence_c::drive_pause_frame(
    bit [47:0] da, bit [47:0] sa, bit [15:0] quanta);
  drive_ctrl_frame(16'h0001, da, sa, quanta, 46);
endtask

// =============================================================================
// Scenario methods
// =============================================================================
task mac_control_frame_sequence_c::run_generic();
  drive_ctrl_frame(opcode, ctrl_da, ctrl_sa, pause_quanta, frame_payload_len);
endtask

task mac_control_frame_sequence_c::run_unsupported_opcode();
  drive_ctrl_frame(unsup_opcode, unsup_da, unsup_sa, 16'h0000, unsup_payload_len);
endtask

task mac_control_frame_sequence_c::run_alt_addr();
  if (!randomize())
    `uvm_fatal(get_type_name(), "Randomization of alt_addr frame failed")
  drive_ctrl_frame(alt_opcode, alt_da, alt_sa, alt_quanta, alt_payload_len);
endtask

task mac_control_frame_sequence_c::run_random();
  int actual_count;
  actual_count = (num_frames < 0) ? 1 : num_frames;
  repeat (actual_count) begin
    if (!randomize())
      `uvm_fatal(get_type_name(), "Randomization of MAC control random frame failed")
    drive_ctrl_frame(rand_opcode, rand_da, rand_sa, rand_quanta, rand_payload_len);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

task mac_control_frame_sequence_c::run_indication();
  drive_pause_frame(ind_da, ind_sa, ind_pause_quanta);
endtask

task mac_control_frame_sequence_c::run_transparency();
  int plen;
  repeat (num_data_frames) begin
    plen = data_payload_min + $urandom_range(0, data_payload_max - data_payload_min);
    drive_data_frame(
      data_broadcast ? 48'hFF_FF_FF_FF_FF_FF : 48'h00_00_02_00_00_AA,
      48'h02_00_00_00_00_01, plen);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
  repeat (num_pause_frames) begin
    drive_pause_frame(48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01, 16'h0100);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

task mac_control_frame_sequence_c::run_clause64();
  if (!randomize())
    `uvm_fatal(get_type_name(), "Randomization of cl64_mode failed")
  case (cl64_mode)
    CL64_QUANTA_ZERO:
      drive_ctrl_frame(16'h0001, cl64_da, cl64_sa, 16'h0000, cl64_payload_len);
    CL64_BACK_TO_BACK: begin
      drive_ctrl_frame(16'h0001, cl64_da, cl64_sa, 16'h0010, cl64_payload_len);
      if (inter_frame_delay > 0) #inter_frame_delay;
      drive_ctrl_frame(16'h0001, cl64_da, cl64_sa, 16'h0020, cl64_payload_len);
    end
    CL64_MAX_QUANTA:
      drive_ctrl_frame(16'h0001, cl64_da, cl64_sa, 16'hFFFF, cl64_payload_len);
    CL64_TIMER_EXPIRY:
      drive_ctrl_frame(16'h0001, cl64_da, cl64_sa, 16'h0004, cl64_payload_len);
  endcase
endtask

task mac_control_frame_sequence_c::run_sustained();
  int plen;
  repeat (num_bcast_burst1) begin
    plen = sust_payload_min + $urandom_range(0, sust_payload_max - sust_payload_min);
    drive_data_frame(48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01, plen);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
  repeat (num_pause) begin
    drive_pause_frame(48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01, 16'h0100);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
  repeat (num_nonmatch) begin
    plen = sust_payload_min + $urandom_range(0, sust_payload_max - sust_payload_min);
    drive_data_frame(nonmatch_da, 48'h02_00_00_00_00_01, plen);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
  repeat (num_bcast_burst2) begin
    plen = sust_payload_min + $urandom_range(0, sust_payload_max - sust_payload_min);
    drive_data_frame(48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01, plen);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

task mac_control_frame_sequence_c::run_addr_change();
  drive_pause_frame(48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01, 16'h0100);
  if (inter_frame_delay > 0) #inter_frame_delay;
  drive_data_frame(target_da_before, 48'h02_00_00_00_00_01,
    chg_payload_min + $urandom_range(0, chg_payload_max - chg_payload_min));
  if (inter_frame_delay > 0) #inter_frame_delay;
  drive_data_frame(target_da_after, 48'h02_00_00_00_00_01,
    chg_payload_min + $urandom_range(0, chg_payload_max - chg_payload_min));
  if (inter_frame_delay > 0) #inter_frame_delay;
  drive_pause_frame(48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01, 16'h0080);
endtask

task mac_control_frame_sequence_c::run_consecutive_addr();
  bit [47:0] da_queue[$];
  da_queue.push_back(local_unicast_da);
  da_queue.push_back(group_da);
  da_queue.push_back(broadcast_da);
  da_queue.push_back(nonmatch_uc_da);
  da_queue.push_back(local_unicast_da);
  da_queue.push_back(broadcast_da);
  foreach (da_queue[i]) begin
    drive_data_frame(da_queue[i], 48'h02_00_00_00_00_01,
      consec_payload_min + $urandom_range(0, consec_payload_max - consec_payload_min));
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask
