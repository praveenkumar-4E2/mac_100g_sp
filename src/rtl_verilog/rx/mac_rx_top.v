`default_nettype none
`include "mac_params.vh"
module mac_rx_top #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1),
    parameter GROUP_TABLE_SIZE = 4,
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
    input wire client_ready,
    output wire client_valid,
    output wire [DATA_WIDTH-1:0] client_data,
    output wire [KEEP_WIDTH-1:0] client_keep,
    output wire client_sop,
    output wire client_eop,
    output wire [frame_end_byte_index_W-1:0] client_frame_end_byte_index,
    output wire client_error,
    output wire client_fcs_present,
    input wire [47:0] local_addr,
    input wire promiscuous_en,
    input wire pause_en,
    input wire [15:0] max_frame_size,
    input wire [15:0] min_frame_size,
    input wire [GROUP_TABLE_SIZE*48-1:0] group_addrs,
    input wire [GROUP_TABLE_SIZE-1:0] group_valid,
    output wire [47:0] dest_addr,
    output wire [47:0] src_addr,
    output wire [15:0] length_type,
    output wire [31:0] received_fcs,
    output wire frame_valid,
    output wire frame_drop,
    output wire crc_error,
    output wire length_error,
    output wire oversize_error,
    output wire alignment_error,
    output wire filter_hit,
    output wire busy
);
  wire filter_accept;
  wire [47:0] filter_dest_addr;
  address_filter #(
      .GROUP_TABLE_SIZE(GROUP_TABLE_SIZE)
  ) destination_filter (
      .local_addr(local_addr),
      .dest_addr(filter_dest_addr),
      .promiscuous_en(promiscuous_en),
      .pause_en(pause_en),
      .group_addrs(group_addrs),
      .group_valid(group_valid),
      .accept(filter_accept)
  );
  rx_pipeline #(
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH),
      .frame_end_byte_index_W(frame_end_byte_index_W),
      .MAX_BODY_OCTETS(MAX_BODY_OCTETS)
  ) pipeline_inst (
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
      .filter_accept(filter_accept),
      .max_frame_size(max_frame_size),
      .min_frame_size(min_frame_size),
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
      .filter_dest_addr(filter_dest_addr),
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
