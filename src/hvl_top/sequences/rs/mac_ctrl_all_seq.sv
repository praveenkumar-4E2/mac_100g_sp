/**
 * @brief Consolidated MAC Control sequence file.
 *
 * Contains a single sequence class (mac_ctrl_all_seq_c) used by
 * mac_ctrl_all_test_c.  A scenario selector enum routes body() to
 * the appropriate method.  Shared helper tasks eliminate duplicated
 * frame construction while preserving identical behaviour.
 *
 * Each scenario builds frame_xtn_c items with EtherType 0x8808
 * (MAC Control) or 0x002E (normal data) and drives them through
 * do_rs_frame() on the RS line-side interface.
 */
class mac_ctrl_all_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_ctrl_all_seq_c)

  //--------------------------------------------------------------------------
  // Scenario selector
  //--------------------------------------------------------------------------
  typedef enum bit [3:0] {
    SC_RANDOM,               // base-class random frames (I4a)
    SC_PAUSE_OPERAND,        // PAUSE with caller-specified quanta (I1)
    SC_ONE_OPCODE,           // single opcode, zero-reserved (I2)
    SC_OVERSIZED,            // oversized supported-opcode frames (I3)
    SC_DATA_TRANSPARENT,     // mixed data + PAUSE transparency (I1e, I4d)
    SC_ALT_ADDR_CONSEC,      // consecutive address classes (A)
    SC_ADDR_VARY,            // address reconfiguration (B)
    SC_SUSTAINED_NONMATCH,   // sustained traffic + non-matching (C)
    SC_RANDOM_ADDR_FILTER,   // constrained-random addr/filter (D)
    SC_DIRECTED_DA           // directed DA via send_clean_frame (I4b, I4c)
  } scenario_e;

  scenario_e scenario;

  //--------------------------------------------------------------------------
  // SC_PAUSE_OPERAND knobs
  //--------------------------------------------------------------------------
  bit [15:0]  pause_quanta      = 16'h0100;
  bit [47:0]  ctrl_da           = 48'h01_80_C2_00_00_01;
  bit [47:0]  ctrl_sa           = 48'h02_00_00_00_00_01;
  int unsigned frame_payload_len = 46;

  //--------------------------------------------------------------------------
  // SC_ONE_OPCODE knobs
  //--------------------------------------------------------------------------
  bit [15:0]  single_opcode      = 16'h0001;
  bit [47:0]  single_da          = 48'h01_80_C2_00_00_01;
  bit [47:0]  single_sa          = 48'h02_00_00_00_00_01;
  int unsigned single_payload_len = 46;
  bit [15:0]  single_quanta      = 16'h0100;

  //--------------------------------------------------------------------------
  // SC_OVERSIZED knobs
  //--------------------------------------------------------------------------
  int unsigned oversized_payload_len = 200;
  bit [15:0]  overs_opcode          = 16'h0001;
  bit [47:0]  overs_da              = 48'h01_80_C2_00_00_01;
  bit [47:0]  overs_sa              = 48'h02_00_00_00_00_01;
  bit [15:0]  overs_quanta          = 16'h0100;

  //--------------------------------------------------------------------------
  // SC_DATA_TRANSPARENT knobs
  //--------------------------------------------------------------------------
  int unsigned num_data_frames  = 5;
  int unsigned num_pause_frames = 2;
  bit          data_broadcast   = 1'b1;
  int unsigned data_payload_min = 46;
  int unsigned data_payload_max = 100;
  bit          gate_report_implemented = 1'b0;

  //--------------------------------------------------------------------------
  // SC_ALT_ADDR_CONSEC knobs
  //--------------------------------------------------------------------------
  bit [47:0] local_unicast_da = 48'h00_00_02_00_00_AA;
  bit [47:0] group_da         = 48'h00_5E_00_01_00_01;
  bit [47:0] broadcast_da     = 48'hFF_FF_FF_FF_FF_FF;
  bit [47:0] nonmatch_da      = 48'hDE_AD_BE_EF_00_01;
  int unsigned consec_payload_min = 46;
  int unsigned consec_payload_max = 100;

  //--------------------------------------------------------------------------
  // SC_ADDR_VARY knobs
  //--------------------------------------------------------------------------
  bit [47:0]  addr_before = 48'h00_00_02_00_00_AA;
  bit [47:0]  addr_after  = 48'h00_00_03_00_00_BB;
  int unsigned vary_payload_min = 46;
  int unsigned vary_payload_max = 100;

  //--------------------------------------------------------------------------
  // SC_SUSTAINED_NONMATCH knobs
  //--------------------------------------------------------------------------
  int unsigned num_bcast_burst1 = 10;
  int unsigned num_pause        = 3;
  int unsigned num_nonmatch     = 5;
  int unsigned num_bcast_burst2 = 5;
  int unsigned sust_payload_min = 46;
  int unsigned sust_payload_max = 150;

  //--------------------------------------------------------------------------
  // SC_DIRECTED_DA knobs
  //--------------------------------------------------------------------------
  bit [47:0] target_da = 48'hFF_FF_FF_FF_FF_FF;

  //--------------------------------------------------------------------------
  // SC_RANDOM_ADDR_FILTER random fields and constraints
  //--------------------------------------------------------------------------
  typedef enum bit [1:0] {
    RAND_DA_PAUSE_MCAST = 2'b00,
    RAND_DA_UNICAST     = 2'b01,
    RAND_DA_GROUP       = 2'b10,
    RAND_DA_BCAST       = 2'b11
  } rand_da_class_e;

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

  constraint c_da_class_dist {
    rand_da_class dist {
      RAND_DA_PAUSE_MCAST := 50,
      RAND_DA_UNICAST     := 20,
      RAND_DA_GROUP       := 15,
      RAND_DA_BCAST       := 15
    };
  }

  constraint c_da_matches_class {
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

  constraint c_payload_len {
    rand_payload_len inside {[46 : 200]};
  }

  //--------------------------------------------------------------------------
  // Extern declarations
  //--------------------------------------------------------------------------
  extern function new(string name = "mac_ctrl_all_seq_c");
  extern task body();

  // Shared helpers
  extern task build_and_send_ctrl_frame(
      string name, bit [47:0] da, bit [47:0] sa,
      bit [15:0] opcode, int unsigned payload_len,
      bit [15:0] quanta);
  extern task build_and_send_data_frame(
      string name, bit [47:0] da, bit [47:0] sa,
      int unsigned payload_len);

  // Per-scenario methods
  extern task run_pause_operand();
  extern task run_one_opcode();
  extern task run_oversized();
  extern task run_data_transparent();
  extern task run_alt_addr_consec();
  extern task run_addr_vary();
  extern task run_sustained_nonmatch();
  extern task run_random_addr_filter();
  extern task run_directed_da();
  extern task run_random();
endclass

function mac_ctrl_all_seq_c::new(string name = "mac_ctrl_all_seq_c");
  super.new(name);
endfunction

task mac_ctrl_all_seq_c::body();
  case (scenario)
    SC_PAUSE_OPERAND:      run_pause_operand();
    SC_ONE_OPCODE:         run_one_opcode();
    SC_OVERSIZED:          run_oversized();
    SC_DATA_TRANSPARENT:   run_data_transparent();
    SC_ALT_ADDR_CONSEC:    run_alt_addr_consec();
    SC_ADDR_VARY:          run_addr_vary();
    SC_SUSTAINED_NONMATCH: run_sustained_nonmatch();
    SC_RANDOM_ADDR_FILTER: run_random_addr_filter();
    SC_DIRECTED_DA:        run_directed_da();
    SC_RANDOM:             run_random();
    default: `uvm_fatal(get_type_name(), $sformatf("Unknown scenario: %0d", scenario))
  endcase
endtask

// Shared helper: build and send a MAC Control frame (EtherType 0x8808).
// Opcode is placed at payload[0:1].  When opcode == 0x0001 (PAUSE) the
// quanta value is placed at payload[2:3]; all remaining bytes are zero.
task mac_ctrl_all_seq_c::build_and_send_ctrl_frame(
    string name, bit [47:0] da, bit [47:0] sa,
    bit [15:0] opcode, int unsigned payload_len,
    bit [15:0] quanta);
  frame_xtn_c frm;
  frm            = frame_xtn_c::type_id::create(name);
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
  if (inter_frame_delay > 0) #inter_frame_delay;
endtask

// Shared helper: build and send a normal data frame (EtherType 0x002E).
// Payload is filled with random bytes.
task mac_ctrl_all_seq_c::build_and_send_data_frame(
    string name, bit [47:0] da, bit [47:0] sa,
    int unsigned payload_len);
  frame_xtn_c frm;
  frm            = frame_xtn_c::type_id::create(name);
  frm.dst_addr   = da;
  frm.src_addr   = sa;
  frm.ether_type = 16'h00_2E;
  frm.payload    = new[payload_len];
  foreach (frm.payload[i])
    frm.payload[i] = $urandom_range(0, 255);
  frm.insert_fcs      = 1'b1;
  frm.crc_error       = 1'b0;
  frm.length_error    = 1'b0;
  frm.alignment_error = 1'b0;
  frm.fcs             = frm.compute_fcs();
  do_rs_frame(frm);
  if (inter_frame_delay > 0) #inter_frame_delay;
endtask

// SC_PAUSE_OPERAND: drives a PAUSE frame with caller-specified quanta.
task mac_ctrl_all_seq_c::run_pause_operand();
  int actual_count;
  actual_count = (num_frames < 0) ? 1 : num_frames;
  repeat (actual_count) begin
    build_and_send_ctrl_frame(
        "pause_operand_frm", ctrl_da, ctrl_sa,
        16'h0001, frame_payload_len, pause_quanta);
  end
endtask

// SC_ONE_OPCODE: drives exactly one opcode, zero-filled reserved bytes.
task mac_ctrl_all_seq_c::run_one_opcode();
  int actual_count;
  actual_count = (num_frames < 0) ? 1 : num_frames;
  repeat (actual_count) begin
    build_and_send_ctrl_frame(
        "one_opcode_frm", single_da, single_sa,
        single_opcode, single_payload_len, single_quanta);
  end
endtask

// SC_OVERSIZED: drives supported-opcode control frames longer than 46B.
task mac_ctrl_all_seq_c::run_oversized();
  int actual_count;
  actual_count = (num_frames < 0) ? 1 : num_frames;
  repeat (actual_count) begin
    build_and_send_ctrl_frame(
        "oversized_frm", overs_da, overs_sa,
        overs_opcode, oversized_payload_len, overs_quanta);
  end
endtask

// SC_DATA_TRANSPARENT: mixed data + PAUSE frames to verify transparency.
task mac_ctrl_all_seq_c::run_data_transparent();
  int plen;

  repeat (num_data_frames) begin
    plen = data_payload_min + $urandom_range(0, data_payload_max - data_payload_min);
    build_and_send_data_frame(
        "data_frm",
        data_broadcast ? 48'hFF_FF_FF_FF_FF_FF : 48'h00_00_02_00_00_AA,
        48'h02_00_00_00_00_01, plen);
  end

  repeat (num_pause_frames) begin
    build_and_send_ctrl_frame(
        "ctrl_frm", 48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01,
        16'h0001, 46, 16'h0100);
  end

  repeat (num_data_frames) begin
    plen = data_payload_min + $urandom_range(0, data_payload_max - data_payload_min);
    build_and_send_data_frame(
        "data_frm",
        data_broadcast ? 48'hFF_FF_FF_FF_FF_FF : 48'h00_00_02_00_00_AA,
        48'h02_00_00_00_00_01, plen);
  end

  if (gate_report_implemented) begin
    build_and_send_ctrl_frame("gate_frm",      48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01, 16'h0002, 46, 16'h0000);
    build_and_send_ctrl_frame("report_frm",    48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01, 16'h0003, 46, 16'h0000);
    build_and_send_ctrl_frame("reg_req_frm",   48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01, 16'h0004, 46, 16'h0000);
    build_and_send_ctrl_frame("reg_frm",       48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01, 16'h0005, 46, 16'h0000);
    build_and_send_ctrl_frame("reg_ack_frm",   48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01, 16'h0006, 46, 16'h0000);
  end
endtask

// SC_ALT_ADDR_CONSEC: consecutive different address classes back-to-back.
task mac_ctrl_all_seq_c::run_alt_addr_consec();
  bit [47:0] da_queue[$];

  da_queue.push_back(local_unicast_da);
  da_queue.push_back(group_da);
  da_queue.push_back(broadcast_da);
  da_queue.push_back(nonmatch_da);
  da_queue.push_back(local_unicast_da);
  da_queue.push_back(broadcast_da);

  foreach (da_queue[i]) begin
    build_and_send_data_frame(
        $sformatf("consec_frm_%0d", i),
        da_queue[i], 48'h02_00_00_00_00_01,
        consec_payload_min + $urandom_range(0, consec_payload_max - consec_payload_min));
  end
endtask

// SC_ADDR_VARY: PAUSE + data before reconfig + data after + PAUSE.
task mac_ctrl_all_seq_c::run_addr_vary();
  build_and_send_ctrl_frame(
      "vary_pause", 48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01,
      16'h0001, 46, 16'h0100);
  build_and_send_data_frame(
      "vary_data", addr_before, 48'h02_00_00_00_00_01,
      vary_payload_min + $urandom_range(0, vary_payload_max - vary_payload_min));
  build_and_send_data_frame(
      "vary_data", addr_after, 48'h02_00_00_00_00_01,
      vary_payload_min + $urandom_range(0, vary_payload_max - vary_payload_min));
  build_and_send_ctrl_frame(
      "vary_pause", 48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01,
      16'h0001, 46, 16'h0080);
endtask

// SC_SUSTAINED_NONMATCH: broadcast bursts + PAUSE interleave + non-matching.
task mac_ctrl_all_seq_c::run_sustained_nonmatch();
  int plen;

  repeat (num_bcast_burst1) begin
    plen = sust_payload_min + $urandom_range(0, sust_payload_max - sust_payload_min);
    build_and_send_data_frame(
        "sust_bcast1", 48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01, plen);
  end

  repeat (num_pause) begin
    build_and_send_ctrl_frame(
        "sust_pause", 48'h01_80_C2_00_00_01, 48'h02_00_00_00_00_01,
        16'h0001, 46, 16'h0100);
  end

  repeat (num_nonmatch) begin
    plen = sust_payload_min + $urandom_range(0, sust_payload_max - sust_payload_min);
    build_and_send_data_frame(
        "sust_nomatch", nonmatch_da, 48'h02_00_00_00_00_01, plen);
  end

  repeat (num_bcast_burst2) begin
    plen = sust_payload_min + $urandom_range(0, sust_payload_max - sust_payload_min);
    build_and_send_data_frame(
        "sust_bcast2", 48'hFF_FF_FF_FF_FF_FF, 48'h02_00_00_00_00_01, plen);
  end
endtask

// SC_RANDOM_ADDR_FILTER: constrained-random opcode/DA/quanta/payload.
task mac_ctrl_all_seq_c::run_random_addr_filter();
  frame_xtn_c frm;
  int actual_count;
  actual_count = (num_frames < 0) ? 1 : num_frames;
  repeat (actual_count) begin
    if (!randomize())
      `uvm_fatal(get_type_name(), "Randomization of random addr/filter frame failed")
    frm            = frame_xtn_c::type_id::create("cr_ctrl_frm");
    frm.dst_addr   = rand_da;
    frm.src_addr   = rand_sa;
    frm.ether_type = 16'h8808;
    frm.payload    = new[rand_payload_len];
    frm.payload[0] = rand_opcode[15:8];
    frm.payload[1] = rand_opcode[7:0];
    if (rand_opcode == 16'h0001) begin
      frm.payload[2] = rand_quanta[15:8];
      frm.payload[3] = rand_quanta[7:0];
    end else begin
      frm.payload[2] = 8'h00;
      frm.payload[3] = 8'h00;
    end
    foreach (frm.payload[i])
      if (i > 3) frm.payload[i] = 8'h00;
    frm.insert_fcs      = 1'b1;
    frm.crc_error       = 1'b0;
    frm.length_error    = 1'b0;
    frm.alignment_error = 1'b0;
    frm.fcs             = frm.compute_fcs();
    do_rs_frame(frm);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

// SC_DIRECTED_DA: deterministic frames to a caller-specified DA.
task mac_ctrl_all_seq_c::run_directed_da();
  payload_min = 46;
  payload_max = 1500;
  repeat (num_frames) begin
    send_clean_frame(-1, target_da);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

// SC_RANDOM: base-class random frame behaviour.
task mac_ctrl_all_seq_c::run_random();
  send_random_frames();
endtask
