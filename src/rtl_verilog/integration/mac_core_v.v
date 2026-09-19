`default_nettype none
`include "mac_params.vh"

// MAC integration core: AXI-to-native TX, native-to-AXI RX, and APB control.
module mac_core_v (
    input wire clk_core,
    input wire rst_n,
    input wire pclk,
    input wire presetn,
    input wire apb_psel,
    input wire apb_penable,
    input wire apb_pwrite,
    input wire [15:0] apb_paddr,
    input wire [31:0] apb_pwdata,
    output wire [31:0] apb_prdata,
    output wire apb_pready,
    output wire apb_pslverr,
    input wire [`AXIS_DATA_WIDTH-1:0] ingress_tx_axis_tdata,
    input wire [`AXIS_KEEP_WIDTH-1:0] ingress_tx_axis_tkeep,
    input wire ingress_tx_axis_tvalid,
    output wire ingress_tx_axis_tready,
    input wire ingress_tx_axis_tlast,
    input wire [7:0] ingress_tx_axis_tuser,
    output wire [`AXIS_DATA_WIDTH-1:0] egress_tx_mac_data,
    output wire [`AXIS_KEEP_WIDTH-1:0] egress_tx_mac_keep,
    output wire egress_tx_mac_valid,
    input wire egress_tx_mac_ready,
    output wire egress_tx_mac_sop,
    output wire egress_tx_mac_eop,
    output wire [6:0] egress_tx_mac_frame_end_byte_index,
    output wire egress_tx_mac_error,
    input wire [`AXIS_DATA_WIDTH-1:0] ingress_rx_mac_data,
    input wire [`AXIS_KEEP_WIDTH-1:0] ingress_rx_mac_keep,
    input wire ingress_rx_mac_valid,
    output wire ingress_rx_mac_ready,
    input wire ingress_rx_mac_sop,
    input wire ingress_rx_mac_eop,
    input wire [6:0] ingress_rx_mac_frame_end_byte_index,
    input wire ingress_rx_mac_error,
    input wire ingress_rx_mac_fcs_present,
    output wire [`AXIS_DATA_WIDTH-1:0] egress_rx_axis_tdata,
    output wire [`AXIS_KEEP_WIDTH-1:0] egress_rx_axis_tkeep,
    output wire egress_rx_axis_tvalid,
    input wire egress_rx_axis_tready,
    output wire egress_rx_axis_tlast,
    output wire [7:0] egress_rx_axis_tuser
);
  wire mac_rst = ~rst_n, apb_rst = ~presetn;
  wire cfg_update, cfg_pause_tx_enable, cfg_pause_tx_soft_req, cfg_speed_override, status_request,
      status_ack;
  wire [31:0] cfg_control;
  wire [47:0] cfg_mac_addr;
  wire [15:0] cfg_max_client_data, cfg_pause_quanta, cfg_max_frame_size, cfg_min_frame_size;
  wire [  2:0] cfg_mac_speed;
  wire [191:0] cfg_group_addr;
  wire [  3:0] cfg_group_valid;
  wire [383:0] status_snapshot;
  wire pause_active, pause_expired, pause_timer_load_valid, pause_event_accepted;
  wire rx_frame_drop, rx_crc_error, rx_length_error, rx_oversize_error;
  wire rx_control_frame_valid, rx_control_frame_error, rx_control_payload_ready;
  wire rx_control_client_valid, rx_control_client_sop, rx_control_client_eop;
  wire rx_control_event_valid;
  wire [15:0] rx_control_opcode, rx_control_pause_time;
  wire [47:0] rx_control_dest_addr;
  wire rx_unsupported_control_event;
  wire [511:0] rx_control_client_data;
  wire [63:0] rx_control_client_keep;
  wire [6:0] rx_control_client_frame_end_byte_index;
  wire [47:0] rx_dest_addr, rx_src_addr;
  wire [15:0] rx_length_type;
  wire [15:0] pause_timer_load_time;
  apb_regs #(
      .GROUP_COUNT(4)
  ) regs (
      .apb_clk(pclk),
      .apb_rst(apb_rst),
      .mac_clk(clk_core),
      .mac_rst(mac_rst),
      .psel(apb_psel),
      .penable(apb_penable),
      .pwrite(apb_pwrite),
      .paddr(apb_paddr),
      .pwdata(apb_pwdata),
      .prdata(apb_prdata),
      .pready(apb_pready),
      .pslverr(apb_pslverr),
      .rx_invalid_event(rx_frame_drop && rx_length_error && !rx_oversize_error),
      .rx_crc_event(rx_frame_drop && rx_crc_error),
      .rx_oversize_event(rx_frame_drop && rx_oversize_error),
       .rx_unsupported_control_event(rx_unsupported_control_event),
      .pause_active(pause_active),
      .pause_expired(pause_expired),
      .tx_error_event(1'b0),
      .cfg_update(cfg_update),
      .cfg_control(cfg_control),
      .cfg_mac_addr(cfg_mac_addr),
      .cfg_max_client_data(cfg_max_client_data),
      .cfg_pause_tx_enable(cfg_pause_tx_enable),
      .cfg_pause_tx_soft_req(cfg_pause_tx_soft_req),
      .cfg_pause_quanta(cfg_pause_quanta),
      .cfg_max_frame_size(cfg_max_frame_size),
      .cfg_min_frame_size(cfg_min_frame_size),
      .cfg_mac_speed(cfg_mac_speed),
      .cfg_speed_override(cfg_speed_override),
      .effective_mac_speed(3'b100),
      .cfg_group_addr(cfg_group_addr),
      .cfg_group_valid(cfg_group_valid),
      .status_request(status_request),
      .status_ack(status_ack),
      .status_snapshot(status_snapshot)
  );
  wire tx_native_valid, tx_native_ready, tx_native_sop, tx_native_eop, tx_native_error,
      tx_native_fcs;
  wire [511:0] tx_native_data;
  wire [ 63:0] tx_native_keep;
  wire [  6:0] tx_native_frame_end_byte_index;
  tx_axi4_stream_adapter tx_adapt (
      .clk(clk_core),
      .rst(mac_rst),
      .ingress_tx_axis_tdata(ingress_tx_axis_tdata),
      .ingress_tx_axis_tkeep(ingress_tx_axis_tkeep),
      .ingress_tx_axis_tvalid(ingress_tx_axis_tvalid),
      .ingress_tx_axis_tready(ingress_tx_axis_tready),
      .ingress_tx_axis_tlast(ingress_tx_axis_tlast),
      .ingress_tx_axis_tuser(ingress_tx_axis_tuser),
      .mac_valid(tx_native_valid),
      .mac_ready(tx_native_ready),
      .mac_data(tx_native_data),
      .mac_keep(tx_native_keep),
      .mac_sop(tx_native_sop),
      .mac_eop(tx_native_eop),
      .mac_frame_end_byte_index(tx_native_frame_end_byte_index),
      .mac_error(tx_native_error),
      .mac_fcs_present(tx_native_fcs)
  );
  wire cap_valid, capture_client_ready, pipeline_req_ready, cap_sop, cap_eop, cap_error, cap_fcs,
      start_capture, axi_frame_active;
  wire [511:0] cap_data;
  wire [ 63:0] cap_keep;
  wire [  6:0] cap_frame_end_byte_index;
  tx_axi_admission admit (
      .clk(clk_core),
      .rst(mac_rst),
      .s_valid(tx_native_valid),
      .s_data(tx_native_data),
      .s_keep(tx_native_keep),
      .s_sop(tx_native_sop),
      .s_eop(tx_native_eop),
      .s_frame_end_byte_index(tx_native_frame_end_byte_index),
      .s_error(tx_native_error),
      .s_fcs_present(tx_native_fcs),
      .s_ready(tx_native_ready),
      .c_valid(cap_valid),
      .c_data(cap_data),
      .c_keep(cap_keep),
      .c_sop(cap_sop),
      .c_eop(cap_eop),
      .c_frame_end_byte_index(cap_frame_end_byte_index),
      .c_error(cap_error),
      .c_fcs_present(cap_fcs),
      .c_ready(capture_client_ready),
      .tx_enabled(cfg_control[2]),
      .pause_admit(!pause_active),
      .pipeline_req_ready(pipeline_req_ready),
      .dest_addr(48'd0),
      .src_addr(48'd0),
      .length_type(16'd0),
      .start_capture(start_capture),
      .frame_active(axi_frame_active)
  );
  wire tx_path_valid, tx_path_ready, tx_path_sop, tx_path_eop, tx_path_error, tx_path_busy;
  wire [511:0] tx_path_data;
  wire [63:0] tx_path_keep;
  wire [6:0] tx_path_frame_end_byte_index;
  wire pause_tx_valid, pause_tx_ready, pause_tx_sop, pause_tx_eop;
  wire [511:0] pause_tx_data;
  wire [63:0] pause_tx_keep;
  wire [6:0] pause_tx_frame_end_byte_index;
  // PAUSE_TX_SOFT_REQ is a software register bit, not a one-clock pulse.
  // Convert each rising edge into one pending request so a held APB value
  // cannot generate a stream of identical PAUSE frames.
  reg pause_tx_soft_req_q, pause_tx_pending;
  always @(posedge clk_core) begin
    if (mac_rst) begin
      pause_tx_soft_req_q <= 1'b0;
      pause_tx_pending <= 1'b0;
    end else begin
      pause_tx_soft_req_q <= cfg_pause_tx_soft_req;
      if (cfg_pause_tx_enable && cfg_pause_tx_soft_req && !pause_tx_soft_req_q)
        pause_tx_pending <= 1'b1;
      else if (pause_tx_valid && pause_tx_ready && pause_tx_eop)
        pause_tx_pending <= 1'b0;
    end
  end
  pause_tx pause_tx_inst (
      .clk(clk_core),
      .rst(mac_rst),
      .pause_tx_enable(cfg_pause_tx_enable),
      .data_pause_active(pause_active),
      .pause_req_valid(pause_tx_pending && !tx_path_busy),
      .pause_req_ready(),
      .source_addr(cfg_mac_addr),
      .pause_time(cfg_pause_quanta),
      .out_valid(pause_tx_valid),
      .out_ready(pause_tx_ready),
      .out_data(pause_tx_data),
      .out_keep(pause_tx_keep),
      .out_sop(pause_tx_sop),
      .out_eop(pause_tx_eop),
      .out_frame_end_byte_index(pause_tx_frame_end_byte_index),
      .out_dest_addr(),
      .out_src_addr(),
      .out_length_type()
  );
  assign pause_tx_ready = egress_tx_mac_ready;
  assign tx_path_ready = egress_tx_mac_ready && !pause_tx_valid;
  assign egress_tx_mac_valid = pause_tx_valid ? pause_tx_valid : tx_path_valid;
  assign egress_tx_mac_data = pause_tx_valid ? pause_tx_data : tx_path_data;
  assign egress_tx_mac_keep = pause_tx_valid ? pause_tx_keep : tx_path_keep;
  assign egress_tx_mac_sop = pause_tx_valid ? pause_tx_sop : tx_path_sop;
  assign egress_tx_mac_eop = pause_tx_valid ? pause_tx_eop : tx_path_eop;
  assign egress_tx_mac_frame_end_byte_index = pause_tx_valid ?
      pause_tx_frame_end_byte_index : tx_path_frame_end_byte_index;
  assign egress_tx_mac_error = pause_tx_valid ? 1'b0 : tx_path_error;
  mac_tx_path txpath (
      .clk(clk_core),
      .rst(mac_rst),
      .start(start_capture),
      .req_ready(pipeline_req_ready),
      .dest_addr(48'd0),
      .src_addr(48'd0),
      .length_type(16'd0),
      .client_valid(cap_valid),
      .client_ready(capture_client_ready),
      .client_data(cap_data),
      .client_keep(cap_keep),
      .client_eop(cap_eop),
      .client_frame_end_byte_index(cap_frame_end_byte_index),
      .client_fcs_present(cap_fcs),
      .carrier_sense(1'b0),
      .collision_detect(1'b0),
      .tick(1'b1),
      .speed(3'b100),
      .egress_tx_mac_valid(tx_path_valid),
      .egress_tx_mac_ready(tx_path_ready),
      .egress_tx_mac_data(tx_path_data),
      .egress_tx_mac_keep(tx_path_keep),
      .egress_tx_mac_sop(tx_path_sop),
      .egress_tx_mac_eop(tx_path_eop),
      .egress_tx_mac_frame_end_byte_index(tx_path_frame_end_byte_index),
      .egress_tx_mac_error(tx_path_error),
      .busy(tx_path_busy),
      .frame_done()
  );
  wire rx_valid, rx_native_ready, rx_sop, rx_eop, rx_error, rx_fcs;
  wire [511:0] rx_data;
  wire [ 63:0] rx_keep;
  wire [  6:0] rx_frame_end_byte_index;
  pause_rx pause_rx_inst (
      .clk(clk_core),
      .rst(mac_rst),
      // A PAUSE request is accepted only after the RX pipeline has validated
      // and emitted the control frame.  Detecting it directly at ingress SOP
      // incorrectly honored bad-FCS and undersized frames.
      .pause_event_valid(rx_control_event_valid && cfg_control[4]),
      .pause_opcode(rx_control_opcode),
      .pause_dest_addr(rx_control_dest_addr),
      .pause_time(rx_control_pause_time),
      .transmission_in_progress(tx_path_busy),
      .local_addr(cfg_mac_addr),
      .timer_load_valid(pause_timer_load_valid),
      .timer_load_time(pause_timer_load_time),
      .pause_event_accepted(pause_event_accepted),
      .pending_event()
  );
  pause_timer_engine pause_timer_inst (
      .clk(clk_core),
      .rst(mac_rst),
      .load_valid(pause_timer_load_valid),
      .load_time(pause_timer_load_time),
      .bit_time_tick(1'b1),
      .speed(3'b100),
      .paused(pause_active),
      .timer_done(pause_expired),
      .remaining_bit_times()
  );
  mac_rx_path #(
      .GROUP_TABLE_SIZE(4)
  ) rxpath (
      .clk(clk_core),
      .rst(mac_rst),
      .ingress_rx_mac_valid(ingress_rx_mac_valid),
      .ingress_rx_mac_ready(ingress_rx_mac_ready),
      .ingress_rx_mac_data(ingress_rx_mac_data),
      .ingress_rx_mac_keep(ingress_rx_mac_keep),
      .ingress_rx_mac_sop(ingress_rx_mac_sop),
      .ingress_rx_mac_eop(ingress_rx_mac_eop),
      .ingress_rx_mac_frame_end_byte_index(ingress_rx_mac_frame_end_byte_index),
      .ingress_rx_mac_error(ingress_rx_mac_error),
      .ingress_rx_mac_fcs_present(ingress_rx_mac_fcs_present),
      // mac_control_top consumes reserved MAC Control frames and provides
      // the sole RX payload backpressure path.  Do not bypass it using the
      // line-side PAUSE detector: that detector fires before the buffered
      // frame reaches the RX emitter and can otherwise strand the emitter.
       .client_ready(rx_control_payload_ready),
      .client_valid(rx_valid),
      .client_data(rx_data),
      .client_keep(rx_keep),
      .client_sop(rx_sop),
      .client_eop(rx_eop),
      .client_frame_end_byte_index(rx_frame_end_byte_index),
      .client_error(rx_error),
      .client_fcs_present(rx_fcs),
      .local_addr(cfg_mac_addr),
      .promiscuous_en(cfg_control[7]),
      .pause_en(cfg_control[4]),
      .max_frame_size(cfg_max_frame_size),
      .min_frame_size(cfg_min_frame_size),
      .group_addrs(cfg_group_addr),
      .group_valid(cfg_group_valid),
       .dest_addr(rx_dest_addr),
       .src_addr(rx_src_addr),
       .length_type(rx_length_type),
      .received_fcs(),
      .frame_valid(),
      .frame_drop(rx_frame_drop),
      .crc_error(rx_crc_error),
      .length_error(rx_length_error),
      .oversize_error(rx_oversize_error),
      .alignment_error(),
      .filter_hit(),
      .busy(),
       .control_frame_valid(rx_control_frame_valid),
       .control_frame_error(rx_control_frame_error)
   );
   mac_control_top control_rx_inst (
       .clk(clk_core),
       .rst(mac_rst),
       .frame_valid(rx_control_frame_valid),
       .frame_error(rx_control_frame_error),
       .dest_addr(rx_dest_addr),
       .src_addr(rx_src_addr),
       .length_type(rx_length_type),
       .local_addr(cfg_mac_addr),
       .payload_valid(rx_valid),
       .payload_ready(rx_control_payload_ready),
       .payload_data(rx_data),
       .payload_keep(rx_keep),
       .payload_sop(rx_sop),
       .payload_eop(rx_eop),
       .payload_frame_end_byte_index(rx_frame_end_byte_index),
       .client_valid(rx_control_client_valid),
       .client_ready(rx_native_ready),
       .client_data(rx_control_client_data),
       .client_keep(rx_control_client_keep),
       .client_sop(rx_control_client_sop),
       .client_eop(rx_control_client_eop),
       .client_frame_end_byte_index(rx_control_client_frame_end_byte_index),
       .control_event_valid(rx_control_event_valid),
       .control_opcode(rx_control_opcode),
       .control_dest_addr(rx_control_dest_addr),
       .control_src_addr(),
       .control_param_valid(),
       .control_param_data(),
       .control_param_eop(),
       .unsupported_control(rx_unsupported_control_event),
       .pause_time(rx_control_pause_time)
   );
  rx_axi4_stream_adapter rx_adapt (
      .clk(clk_core),
      .rst(mac_rst),
       .mac_valid(rx_control_client_valid),
       .mac_ready(rx_native_ready),
       .mac_data(rx_control_client_data),
       .mac_keep(rx_control_client_keep),
       .mac_sop(rx_control_client_sop),
       .mac_eop(rx_control_client_eop),
       .mac_frame_end_byte_index(rx_control_client_frame_end_byte_index),
      .mac_error(rx_error),
      .mac_fcs_valid(rx_fcs),
      .egress_rx_axis_tdata(egress_rx_axis_tdata),
      .egress_rx_axis_tkeep(egress_rx_axis_tkeep),
      .egress_rx_axis_tvalid(egress_rx_axis_tvalid),
      .egress_rx_axis_tready(egress_rx_axis_tready),
      .egress_rx_axis_tlast(egress_rx_axis_tlast),
      .egress_rx_axis_tuser(egress_rx_axis_tuser)
  );
endmodule
`default_nettype wire
