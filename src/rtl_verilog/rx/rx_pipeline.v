`default_nettype none
`include "mac_params.vh"
module rx_pipeline #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1),
    parameter MAX_BODY_OCTETS = `MAC_RX_BUFFER_BYTES
) (
    input wire clk,
    input wire rst,
    input wire in_valid,
    output wire in_ready,
    input wire [DATA_WIDTH-1:0] in_data,
    input wire [KEEP_WIDTH-1:0] in_keep,
    input wire in_sop,
    input wire in_eop,
    input wire [frame_end_byte_index_W-1:0] in_frame_end_byte_index,
    input wire in_error,
    input wire in_fcs_present,
    input wire filter_accept,
    input wire [15:0] max_frame_size,
    input wire [15:0] min_frame_size,
    output wire client_valid,
    input wire client_ready,
    output wire [DATA_WIDTH-1:0] client_data,
    output wire [KEEP_WIDTH-1:0] client_keep,
    output wire client_sop,
    output wire client_eop,
    output wire [frame_end_byte_index_W-1:0] client_frame_end_byte_index,
    output wire client_error,
    output wire client_fcs_present,
    output wire [47:0] dest_addr,
    output wire [47:0] src_addr,
    output wire [15:0] length_type,
    output wire [31:0] received_fcs,
    output wire [47:0] filter_dest_addr,
    output wire frame_valid,
    output wire frame_drop,
    output wire crc_error,
    output wire length_error,
    output wire oversize_error,
    output wire alignment_error,
    output wire filter_hit,
    output wire busy
);
  wire pre_stage_valid, pre_stage_ready, pre_stage_sop, pre_stage_eop, pre_stage_error,
      pre_stage_fcs_present;
  wire [DATA_WIDTH-1:0] pre_stage_data;
  wire [KEEP_WIDTH-1:0] pre_stage_keep;
  wire [frame_end_byte_index_W-1:0] pre_stage_frame_end_byte_index;
  wire header_ready, header_done, header_done_ready;
  wire [47:0] header_dest_addr, header_src_addr;
  wire [15:0] header_length_type;
  wire crc_ready, crc_done, crc_done_ready, crc_good, crc_error_int;
  wire [31:0] crc_received_fcs;
  wire length_ready, length_done, length_done_ready, length_good, length_error_int,
      length_alignment_error, length_oversize_error, length_undersize_error;
  wire [15:0] length_payload_octets;
  wire emit_ready;
  rx_preamble_detect #(
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH),
      .frame_end_byte_index_W(frame_end_byte_index_W)
  ) preamble_inst (
      .clk(clk),
      .rst(rst),
      .in_valid(in_valid),
      .in_ready(in_ready),
      .in_data(in_data),
      .in_keep(in_keep),
      .in_sop(in_sop),
      .in_eop(in_eop),
      .in_frame_end_byte_index(in_frame_end_byte_index),
      .in_error(in_error),
      .in_fcs_present(in_fcs_present),
      .out_valid(pre_stage_valid),
      .out_ready(pre_stage_ready),
      .out_data(pre_stage_data),
      .out_keep(pre_stage_keep),
      .out_sop(pre_stage_sop),
      .out_eop(pre_stage_eop),
      .out_frame_end_byte_index(pre_stage_frame_end_byte_index),
      .out_error(pre_stage_error),
      .out_fcs_present(pre_stage_fcs_present)
  );
  assign pre_stage_ready = header_ready && crc_ready && length_ready && emit_ready;
  rx_header_extract #(
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH),
      .frame_end_byte_index_W(frame_end_byte_index_W)
  ) header_inst (
      .clk(clk),
      .rst(rst),
      .in_valid(pre_stage_valid),
      .in_ready(header_ready),
      .in_data(pre_stage_data),
      .in_keep(pre_stage_keep),
      .in_sop(pre_stage_sop),
      .in_eop(pre_stage_eop),
      .in_frame_end_byte_index(pre_stage_frame_end_byte_index),
      .in_error(pre_stage_error),
      .frame_done(header_done),
      .frame_done_ready(header_done_ready),
      .dest_addr(header_dest_addr),
      .src_addr(header_src_addr),
      .length_type(header_length_type)
  );
  assign filter_dest_addr = header_dest_addr;
  rx_crc_check #(
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH),
      .frame_end_byte_index_W(frame_end_byte_index_W)
  ) crc_inst (
      .clk(clk),
      .rst(rst),
      .in_valid(pre_stage_valid),
      .in_ready(crc_ready),
      .in_data(pre_stage_data),
      .in_keep(pre_stage_keep),
      .in_sop(pre_stage_sop),
      .in_eop(pre_stage_eop),
      .in_frame_end_byte_index(pre_stage_frame_end_byte_index),
      .in_error(pre_stage_error),
      .in_fcs_present(pre_stage_fcs_present),
      .frame_done(crc_done),
      .frame_done_ready(crc_done_ready),
      .crc_good(crc_good),
      .crc_error(crc_error_int),
      .received_fcs(crc_received_fcs)
  );
  rx_length_check #(
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH),
      .frame_end_byte_index_W(frame_end_byte_index_W)
  ) length_inst (
      .clk(clk),
      .rst(rst),
      .in_valid(pre_stage_valid),
      .in_ready(length_ready),
      .in_data(pre_stage_data),
      .in_keep(pre_stage_keep),
      .in_sop(pre_stage_sop),
      .in_eop(pre_stage_eop),
      .in_frame_end_byte_index(pre_stage_frame_end_byte_index),
      .in_error(pre_stage_error),
      .in_fcs_present(pre_stage_fcs_present),
      .max_frame_size(max_frame_size),
      .min_frame_size(min_frame_size),
      .frame_done(length_done),
      .frame_done_ready(length_done_ready),
      .length_good(length_good),
      .length_error(length_error_int),
      .alignment_error(length_alignment_error),
      .oversize_error(length_oversize_error),
      .undersize_error(length_undersize_error),
      .payload_octets(length_payload_octets)
  );
  rx_frame_emit #(
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH),
      .frame_end_byte_index_W(frame_end_byte_index_W),
      .MAX_BODY_OCTETS(MAX_BODY_OCTETS)
  ) emit_inst (
      .clk(clk),
      .rst(rst),
      .in_valid(pre_stage_valid),
      .in_ready(emit_ready),
      .in_data(pre_stage_data),
      .in_keep(pre_stage_keep),
      .in_sop(pre_stage_sop),
      .in_eop(pre_stage_eop),
      .in_frame_end_byte_index(pre_stage_frame_end_byte_index),
      .in_error(pre_stage_error),
      .header_done(header_done),
      .header_done_ready(header_done_ready),
      .header_dest_addr(header_dest_addr),
      .header_src_addr(header_src_addr),
      .header_length_type(header_length_type),
      .crc_done(crc_done),
      .crc_done_ready(crc_done_ready),
      .crc_good(crc_good),
      .crc_error_in(crc_error_int),
      .received_fcs_in(crc_received_fcs),
      .length_done(length_done),
      .length_done_ready(length_done_ready),
      .length_good(length_good),
      .length_error_in(length_error_int),
      .oversize_error_in(length_oversize_error),
      .alignment_error_in(length_alignment_error),
      .payload_octets_in(length_payload_octets),
      // Only frames to the reserved MAC Control destination are intercepted
      // before normal client address filtering.
      .filter_accept(filter_accept || ((header_length_type == 16'h8808) &&
          (header_dest_addr == 48'h0180c2000001))),
      .max_frame_size(max_frame_size),
      .client_valid(client_valid),
      .client_ready(client_ready),
      .client_data(client_data),
      .client_keep(client_keep),
      .client_sop(client_sop),
      .client_eop(client_eop),
      .client_frame_end_byte_index(client_frame_end_byte_index),
      .client_error(client_error),
      .client_fcs_present(client_fcs_present),
      .dest_addr(dest_addr),
      .src_addr(src_addr),
      .length_type(length_type),
      .received_fcs(received_fcs),
      .frame_valid(frame_valid),
      .frame_drop(frame_drop),
      .crc_error(crc_error),
      .length_error(length_error),
      .oversize_error(oversize_error),
      .alignment_error(alignment_error),
      .filter_hit(filter_hit),
      .busy(busy)
  );
endmodule
`default_nettype wire
