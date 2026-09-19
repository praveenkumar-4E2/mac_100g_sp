`default_nettype none
`include "mac_params.vh"
module tx_pad_calc #(
    parameter COUNT_WIDTH = 12
) (
    input wire [COUNT_WIDTH-1:0] client_bytes,
    input wire fcs_present,
    output reg [COUNT_WIDTH-1:0] payload_bytes,
    output reg [COUNT_WIDTH-1:0] pad_bytes
);
  localparam [COUNT_WIDTH-1:0] HEADER_OCTETS = `MAC_HEADER_OCTETS;
  localparam [COUNT_WIDTH-1:0] FCS_OCTETS = `MAC_FCS_OCTETS;
  localparam [COUNT_WIDTH-1:0] MIN_CLIENT_AND_PAD_OCTETS =
      `MAC_MIN_FRAME_OCTETS - `MAC_HEADER_OCTETS - `MAC_FCS_OCTETS;
  always @* begin
    payload_bytes = (client_bytes >= HEADER_OCTETS) ?
        client_bytes - HEADER_OCTETS : {COUNT_WIDTH{1'b0}};
    if (fcs_present) begin
      if (payload_bytes >= FCS_OCTETS) payload_bytes = payload_bytes - FCS_OCTETS;
      pad_bytes = {COUNT_WIDTH{1'b0}};
    end else
      pad_bytes = (payload_bytes < MIN_CLIENT_AND_PAD_OCTETS) ?
          MIN_CLIENT_AND_PAD_OCTETS - payload_bytes : {COUNT_WIDTH{1'b0}};
  end
endmodule
`default_nettype wire
