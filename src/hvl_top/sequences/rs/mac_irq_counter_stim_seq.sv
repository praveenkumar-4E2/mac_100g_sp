class mac_irq_counter_stim_seq_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_irq_counter_stim_seq_c)

  typedef enum int {INVALID_LENGTH, OVERSIZE} stimulus_kind_e;
  stimulus_kind_e stimulus_kind = INVALID_LENGTH;

  extern function new(string name="mac_irq_counter_stim_seq_c");
  extern task body();
extern task send_invalid_length_frame();
extern task send_oversize_frame();
endclass

function mac_irq_counter_stim_seq_c::new(string name="mac_irq_counter_stim_seq_c");
    super.new(name);
endfunction

task mac_irq_counter_stim_seq_c::body();
  case (stimulus_kind)
    INVALID_LENGTH: send_invalid_length_frame();
    OVERSIZE:       send_oversize_frame();
    default: `uvm_fatal("IRQ_STIM", "Unsupported interrupt stimulus kind")
  endcase
endtask

task mac_irq_counter_stim_seq_c :: send_invalid_length_frame();
    frame_xtn_c frm;

    frm = frame_xtn_c::type_id::create("invalid_length_frame");
    if(!frm.randomize() with{
        dst_addr == 48'hff_ff_ff_ff_ff_ff;
        ether_type == 16'd100;
        payload.size() == 46;
        insert_fcs == 1'b1;
        crc_error == 1'b0;
        length_error == 1'b0;
        alignment_error == 1'b0;
    })
    `uvm_fatal("IRQ_STIM","Invalid-length frame randomization failed")

    do_rs_frame(frm);
endtask

task mac_irq_counter_stim_seq_c :: send_oversize_frame();
    frame_xtn_c frm;

    frm = frame_xtn_c::type_id::create("oversize_frame");

      if (!frm.randomize() with {
        dst_addr == 48'hff_ff_ff_ff_ff_ff;
        ether_type == 16'h0800;
        payload.size() == 1501;      // 14-byte header + 1501 + 4-byte FCS = 1519
        insert_fcs == 1'b1;
        crc_error == 1'b0;
        length_error == 1'b0;
        alignment_error == 1'b0;
      })
    `uvm_fatal("IRQ_STIM", "Oversize frame randomization failed")

  do_rs_frame(frm);

endtask
