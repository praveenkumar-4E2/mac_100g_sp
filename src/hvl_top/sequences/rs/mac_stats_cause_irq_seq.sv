class mac_stats_cause_irq_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_stats_cause_irq_seq_c)

  typedef enum int {
    STIM_RX_INVALID,
    STIM_RX_CRC,
    STIM_RX_OVERSIZE,
    STIM_RX_UNSUPPORTED_CTRL,
    STIM_PAUSE_ACTIVE,
    STIM_PAUSE_EXPIRED,
    STIM_CLEAN_DATA,
    STIM_RANDOM_BURST
  } stimulus_kind_e;

  stimulus_kind_e stimulus_kind = STIM_RX_INVALID;
  int unsigned     burst_count   = 3;
  bit [15:0]       pause_quanta_val = 16'h0100;

  extern function new(string name = "mac_stats_cause_irq_seq_c");
  extern task body();
  extern task send_rx_invalid_frame();
  extern task send_rx_crc_frame();
  extern task send_rx_oversize_frame();
  extern task send_unsupported_ctrl_frame();
  extern task send_clean_data_frame();
endclass

function mac_stats_cause_irq_seq_c::new(string name = "mac_stats_cause_irq_seq_c");
  super.new(name);
endfunction

task mac_stats_cause_irq_seq_c::body();
  case (stimulus_kind)
    STIM_RX_INVALID:         send_rx_invalid_frame();
    STIM_RX_CRC:             send_rx_crc_frame();
    STIM_RX_OVERSIZE:        send_rx_oversize_frame();
    STIM_RX_UNSUPPORTED_CTRL: send_unsupported_ctrl_frame();
    STIM_PAUSE_ACTIVE:       send_pause_frame(pause_quanta_val);
    STIM_PAUSE_EXPIRED:      send_pause_frame(pause_quanta_val);
    STIM_CLEAN_DATA:         send_clean_data_frame();
    STIM_RANDOM_BURST: begin
      repeat (burst_count) begin
        case ($urandom_range(0, 3))
          0: send_rx_invalid_frame();
          1: send_rx_crc_frame();
          2: send_rx_oversize_frame();
          3: send_unsupported_ctrl_frame();
        endcase
      end
    end
    default: `uvm_fatal(get_type_name(), $sformatf("Unsupported stimulus_kind: %0d", stimulus_kind))
  endcase
endtask

task mac_stats_cause_irq_seq_c::send_rx_invalid_frame();
  frame_xtn_c frm;
  frm = frame_xtn_c::type_id::create("rx_invalid_frm");
  if (!frm.randomize() with {
    dst_addr == 48'hFF_FF_FF_FF_FF_FF;
    ether_type == 16'd100;
    payload.size() == 46;
    insert_fcs == 1'b1;
    crc_error == 1'b0;
    length_error == 1'b0;
    alignment_error == 1'b0;
  })
    `uvm_fatal(get_type_name(), "RX invalid frame randomization failed")
  do_rs_frame(frm);
endtask

task mac_stats_cause_irq_seq_c::send_rx_crc_frame();
  frame_xtn_c frm;
  frm = frame_xtn_c::type_id::create("rx_crc_frm");
  if (!frm.randomize() with {
    dst_addr == 48'hFF_FF_FF_FF_FF_FF;
    ether_type == 16'h0800;
    payload.size() inside {[46 : 200]};
    insert_fcs == 1'b1;
    crc_error == 1'b1;
    length_error == 1'b0;
    alignment_error == 1'b0;
  })
    `uvm_fatal(get_type_name(), "RX CRC frame randomization failed")
  do_rs_frame(frm);
endtask

task mac_stats_cause_irq_seq_c::send_rx_oversize_frame();
  frame_xtn_c frm;
  frm = frame_xtn_c::type_id::create("rx_oversize_frm");
  if (!frm.randomize() with {
    dst_addr == 48'hFF_FF_FF_FF_FF_FF;
    ether_type == 16'h0800;
    payload.size() == 1501;
    insert_fcs == 1'b1;
    crc_error == 1'b0;
    length_error == 1'b0;
    alignment_error == 1'b0;
  })
    `uvm_fatal(get_type_name(), "RX oversize frame randomization failed")
  do_rs_frame(frm);
endtask

task mac_stats_cause_irq_seq_c::send_unsupported_ctrl_frame();
  frame_xtn_c frm;
  bit [15:0] opcode;
  opcode = 16'h0002;
  frm = frame_xtn_c::type_id::create("unsup_ctrl_frm");
  frm.dst_addr   = 48'h01_80_C2_00_00_01;
  frm.src_addr   = 48'h02_00_00_00_00_01;
  frm.ether_type = 16'h8808;
  frm.payload    = new[46];
  frm.payload[0] = opcode[15:8];
  frm.payload[1] = opcode[7:0];
  foreach (frm.payload[i])
    if (i > 1) frm.payload[i] = 8'h00;
  frm.insert_fcs      = 1'b1;
  frm.crc_error       = 1'b0;
  frm.length_error    = 1'b0;
  frm.alignment_error = 1'b0;
  frm.fcs             = frm.compute_fcs();
  do_rs_frame(frm);
endtask

task mac_stats_cause_irq_seq_c::send_clean_data_frame();
  frame_xtn_c frm;
  frm = frame_xtn_c::type_id::create("clean_data_frm");
  if (!frm.randomize() with {
    dst_addr == 48'hFF_FF_FF_FF_FF_FF;
    ether_type == 16'h0800;
    payload.size() inside {[46 : 200]};
    insert_fcs == 1'b1;
    crc_error == 1'b0;
    length_error == 1'b0;
    alignment_error == 1'b0;
  })
    `uvm_fatal(get_type_name(), "Clean data frame randomization failed")
  do_rs_frame(frm);
endtask
