`default_nettype none
`include "mac_params.vh"
// TX datapath from admitted client payload to the native MAC/RS stream.
module mac_tx_path #(
    parameter DATA_WIDTH = `AXIS_DATA_WIDTH,
    parameter KEEP_WIDTH = `AXIS_KEEP_WIDTH,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
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
    output wire egress_tx_mac_valid,
    input wire egress_tx_mac_ready,
    output wire [DATA_WIDTH-1:0] egress_tx_mac_data,
    output wire [KEEP_WIDTH-1:0] egress_tx_mac_keep,
    output wire egress_tx_mac_sop,
    output wire egress_tx_mac_eop,
    output wire [frame_end_byte_index_W-1:0] egress_tx_mac_frame_end_byte_index,
    output wire egress_tx_mac_error,
    output wire busy,
    output wire frame_done
);
  mac_tx_top tx_path_inst (
      .clk(clk),
      .rst(rst),
      .start(start),
      .req_ready(req_ready),
      .dest_addr(dest_addr),
      .src_addr(src_addr),
      .length_type(length_type),
      .client_valid(client_valid),
      .client_ready(client_ready),
      .client_data(client_data),
      .client_keep(client_keep),
      .client_eop(client_eop),
      .client_frame_end_byte_index(client_frame_end_byte_index),
      .client_fcs_present(client_fcs_present),
      .carrier_sense(carrier_sense),
      .collision_detect(collision_detect),
      .tick(tick),
      .speed(speed),
      .out_valid(egress_tx_mac_valid),
      .out_ready(egress_tx_mac_ready),
      .out_data(egress_tx_mac_data),
      .out_keep(egress_tx_mac_keep),
      .out_sop(egress_tx_mac_sop),
      .out_eop(egress_tx_mac_eop),
      .out_frame_end_byte_index(egress_tx_mac_frame_end_byte_index),
      .out_error(egress_tx_mac_error),
      .busy(busy),
      .frame_done(frame_done)
  );
endmodule
`default_nettype wire
