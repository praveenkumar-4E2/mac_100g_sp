`default_nettype none
`include "mac_params.vh"
module tx_axi4_stream_adapter #(
    parameter DATA_WIDTH = `AXIS_DATA_WIDTH,
    parameter KEEP_WIDTH = `AXIS_KEEP_WIDTH,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    // AXI ingress from the client into the TX MAC path.
    input wire [DATA_WIDTH-1:0] ingress_tx_axis_tdata,
    input wire [KEEP_WIDTH-1:0] ingress_tx_axis_tkeep,
    input wire ingress_tx_axis_tvalid,
    output wire ingress_tx_axis_tready,
    input wire ingress_tx_axis_tlast,
    input wire [7:0] ingress_tx_axis_tuser,
    output wire mac_valid,
    input wire mac_ready,
    output wire [DATA_WIDTH-1:0] mac_data,
    output wire [KEEP_WIDTH-1:0] mac_keep,
    output wire mac_sop,
    output wire mac_eop,
    output reg [frame_end_byte_index_W-1:0] mac_frame_end_byte_index,
    output wire mac_error,
    output wire mac_fcs_present
);
  reg frame_active;
  integer lane_index;
  always @* begin
    mac_frame_end_byte_index = {frame_end_byte_index_W{1'b0}};
    for (lane_index = 0; lane_index < KEEP_WIDTH; lane_index = lane_index + 1)
    mac_frame_end_byte_index = mac_frame_end_byte_index + ingress_tx_axis_tkeep[lane_index];
  end
  assign ingress_tx_axis_tready = mac_ready;
  assign mac_valid = ingress_tx_axis_tvalid;
  assign mac_data = ingress_tx_axis_tdata;
  assign mac_keep = ingress_tx_axis_tkeep;
  assign mac_sop = ingress_tx_axis_tvalid && !frame_active;
  assign mac_eop = ingress_tx_axis_tlast;
  assign mac_error = ingress_tx_axis_tuser[0];
  assign mac_fcs_present = ingress_tx_axis_tuser[1];
  always @(posedge clk) begin
    if (rst) frame_active <= 1'b0;
    else if (ingress_tx_axis_tvalid && ingress_tx_axis_tready)
      frame_active <= !ingress_tx_axis_tlast;
  end
endmodule
`default_nettype wire
