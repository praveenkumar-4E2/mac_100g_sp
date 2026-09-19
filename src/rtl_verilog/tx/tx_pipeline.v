`default_nettype none
`include "mac_params.vh"
module tx_pipeline #(
    parameter BUFFER_BYTES = `MAC_TX_BUFFER_BYTES,
    parameter COUNT_WIDTH = $clog2(BUFFER_BYTES + 1),
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1),
    parameter WORD_ADDR_WIDTH = $clog2(BUFFER_BYTES / KEEP_WIDTH)
) (
    input wire clk,
    input wire rst,
    input wire start,
    output wire req_ready,
    input wire [47:0] dest_addr,
    input wire [47:0] src_addr,
    input wire [15:0] length_type,
    input wire client_valid,
    output wire client_ready,
    input wire [DATA_WIDTH-1:0] client_data,
    input wire [KEEP_WIDTH-1:0] client_keep,
    input wire client_eop,
    input wire [frame_end_byte_index_W-1:0] client_frame_end_byte_index,
    input wire client_fcs_present,
    input wire carrier_sense,
    input wire collision_detect,
    input wire tick,
    input wire [2:0] speed,
    output wire out_valid,
    input wire out_ready,
    output wire [DATA_WIDTH-1:0] out_data,
    output wire [KEEP_WIDTH-1:0] out_keep,
    output wire out_sop,
    output wire out_eop,
    output wire [frame_end_byte_index_W-1:0] out_frame_end_byte_index,
    output wire out_error,
    output wire busy,
    output wire frame_done
);
  wire builder_req_ready, scheduled_start, ipg_done, capture_active, capture_done;
  wire [COUNT_WIDTH-1:0] captured_bytes;
  wire [WORD_ADDR_WIDTH-1:0] capture_read_addr, capture_read_addr_1;
  wire [DATA_WIDTH-1:0] capture_read_data, capture_read_data_1;
  wire [31:0] supplied_fcs;
  wire [6:0] ipg_remaining;
  wire end_of_frame = out_valid && out_ready && out_eop;
  tx_ipg_timer_stage ipg_inst (
      .clk(clk),
      .rst(rst),
      .start(end_of_frame),
      .frame_end_byte_index(out_frame_end_byte_index),
      .enable(1'b1),
      .tick(tick),
      .speed(speed),
      .done(ipg_done),
      .remaining(ipg_remaining)
  );
  tx_scheduler scheduler_inst (
      .start(start),
      .request_ready(builder_req_ready && !capture_active),
      .ipg_done(ipg_done),
      .accept_start(scheduled_start),
      .request_ready_out(req_ready)
  );
  tx_client_capture #(
      .BUFFER_BYTES(BUFFER_BYTES),
      .COUNT_WIDTH(COUNT_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH),
      .frame_end_byte_index_W(frame_end_byte_index_W)
  ) capture_inst (
      .clk(clk),
      .rst(rst),
      .start_capture(scheduled_start),
      .client_valid(client_valid),
      .client_data(client_data),
      .client_keep(client_keep),
      .client_eop(client_eop),
      .client_frame_end_byte_index(client_frame_end_byte_index),
      .client_ready(client_ready),
      .capture_active(capture_active),
      .capture_done(capture_done),
      .captured_bytes(captured_bytes),
      .supplied_fcs(supplied_fcs),
      .read_addr(capture_read_addr),
      .read_data(capture_read_data),
      .read_addr_1(capture_read_addr_1),
      .read_data_1(capture_read_data_1)
  );
  tx_frame_builder #(
      .BUFFER_BYTES(BUFFER_BYTES),
      .COUNT_WIDTH(COUNT_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH),
      .frame_end_byte_index_W(frame_end_byte_index_W)
  ) builder_inst (
      .clk(clk),
      .rst(rst),
      .start_capture(scheduled_start),
      .req_ready(builder_req_ready),
      .capture_done(capture_done),
      .captured_bytes(captured_bytes),
      .supplied_fcs(supplied_fcs),
      .capture_read_addr(capture_read_addr),
      .capture_read_data(capture_read_data),
      .capture_read_addr_1(capture_read_addr_1),
      .capture_read_data_1(capture_read_data_1),
      .ready(out_ready),
      .dest_addr(dest_addr),
      .src_addr(src_addr),
      .length_type(length_type),
      .client_fcs_present(client_fcs_present),
      .out_valid(out_valid),
      .out_data(out_data),
      .out_keep(out_keep),
      .out_sop(out_sop),
      .out_eop(out_eop),
      .out_frame_end_byte_index(out_frame_end_byte_index),
      .out_error(out_error),
      .busy(busy),
      .frame_done(frame_done)
  );
endmodule
`default_nettype wire
