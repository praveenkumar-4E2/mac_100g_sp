`default_nettype none
`include "mac_params.vh"
module rx_axi4_stream_adapter #(
    parameter DATA_WIDTH = `AXIS_DATA_WIDTH,
    parameter KEEP_WIDTH = `AXIS_KEEP_WIDTH,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire mac_valid,
    output wire mac_ready,
    input wire [DATA_WIDTH-1:0] mac_data,
    input wire [KEEP_WIDTH-1:0] mac_keep,
    input wire mac_sop,
    input wire mac_eop,
    input wire [frame_end_byte_index_W-1:0] mac_frame_end_byte_index,
    input wire mac_error,
    input wire mac_fcs_valid,
    // AXI egress from the RX MAC path toward the client.
    output wire [DATA_WIDTH-1:0] egress_rx_axis_tdata,
    output wire [KEEP_WIDTH-1:0] egress_rx_axis_tkeep,
    output wire egress_rx_axis_tvalid,
    input wire egress_rx_axis_tready,
    output wire egress_rx_axis_tlast,
    output wire [7:0] egress_rx_axis_tuser
);
  assign mac_ready = egress_rx_axis_tready;
  assign egress_rx_axis_tdata  = mac_data;
  assign egress_rx_axis_tvalid = mac_valid;
  assign egress_rx_axis_tlast  = mac_eop;
  assign egress_rx_axis_tuser  = {6'b0, mac_fcs_valid, mac_error};
  assign egress_rx_axis_tkeep  = mac_eop ? mac_keep : {KEEP_WIDTH{1'b1}};
endmodule
`default_nettype wire
