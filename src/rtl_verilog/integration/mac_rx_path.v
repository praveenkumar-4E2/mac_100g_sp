`default_nettype none
`include "mac_params.vh"
// RX datapath from native MAC/RS traffic to accepted client payload.
module mac_rx_path #(
    parameter DATA_WIDTH = `AXIS_DATA_WIDTH,
    parameter KEEP_WIDTH = `AXIS_KEEP_WIDTH,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1),
    parameter GROUP_TABLE_SIZE = 4,
    parameter MAX_BODY_OCTETS = `MAC_RX_BUFFER_BYTES
) (
    input wire clk,
    input wire rst,
    input wire ingress_rx_mac_valid,
    output wire ingress_rx_mac_ready,
    input wire [DATA_WIDTH-1:0] ingress_rx_mac_data,
    input wire [KEEP_WIDTH-1:0] ingress_rx_mac_keep,
    input wire ingress_rx_mac_sop,
    input wire ingress_rx_mac_eop,
    input wire [frame_end_byte_index_W-1:0] ingress_rx_mac_frame_end_byte_index,
    input wire ingress_rx_mac_error,
    input wire ingress_rx_mac_fcs_present,
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
    output wire busy,
    output reg control_frame_valid,
    output reg control_frame_error
);
  mac_rx_top #(
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH),
      .frame_end_byte_index_W(frame_end_byte_index_W),
      .GROUP_TABLE_SIZE(GROUP_TABLE_SIZE),
      .MAX_BODY_OCTETS(MAX_BODY_OCTETS)
  ) rx_path_inst (
      .clk(clk),
      .rst(rst),
      .in_valid(ingress_rx_mac_valid),
      .in_ready(ingress_rx_mac_ready),
      .in_data(ingress_rx_mac_data),
      .in_keep(ingress_rx_mac_keep),
      .in_sop(ingress_rx_mac_sop),
      .in_eop(ingress_rx_mac_eop),
      .in_frame_end_byte_index(ingress_rx_mac_frame_end_byte_index),
      .in_error(ingress_rx_mac_error),
      .in_fcs_present(ingress_rx_mac_fcs_present),
      .client_ready(client_ready),
      .client_valid(client_valid),
      .client_data(client_data),
      .client_keep(client_keep),
      .client_sop(client_sop),
      .client_eop(client_eop),
      .client_frame_end_byte_index(client_frame_end_byte_index),
      .client_error(client_error),
      .client_fcs_present(client_fcs_present),
      .local_addr(local_addr),
      .promiscuous_en(promiscuous_en),
      .pause_en(pause_en),
      .max_frame_size(max_frame_size),
      .min_frame_size(min_frame_size),
      .group_addrs(group_addrs),
      .group_valid(group_valid),
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
  always @(posedge clk) begin
    if (rst) begin
      control_frame_valid <= 1'b0;
      control_frame_error <= 1'b0;
    end else begin
      // Frame completion indications are pulses.  In particular, a dropped
      // frame must not poison the payload-ready path for later frames.
      control_frame_error <= 1'b0;
      if (frame_valid) begin
        control_frame_valid <= 1'b1;
        control_frame_error <= 1'b0;
      end else if (client_valid && client_ready && client_eop) control_frame_valid <= 1'b0;
      if (frame_drop) control_frame_error <= 1'b1;
    end
  end
endmodule
`default_nettype wire
