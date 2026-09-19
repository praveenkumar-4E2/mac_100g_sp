`default_nettype none
module cdc_handshake #(
    parameter WIDTH = 32
) (
    input wire clk_src,
    input wire rst_src,
    input wire req_src,
    input wire [WIDTH-1:0] data_src,
    output wire ready_src,
    input wire clk_dst,
    input wire rst_dst,
    output reg valid_dst,
    output reg [WIDTH-1:0] data_dst,
    input wire ack_dst
);
  reg req_toggle, ack_toggle, req_sync1, req_sync2, ack_sync1, ack_sync2;
  reg req_seen, ack_seen;
  reg [WIDTH-1:0] hold_data;
  assign ready_src = (ack_sync2 == ack_seen);
  always @(posedge clk_src) begin
    if (rst_src) begin
      req_toggle <= 1'b0;
      ack_seen   <= 1'b0;
      hold_data  <= {WIDTH{1'b0}};
      ack_sync1  <= 1'b0;
      ack_sync2  <= 1'b0;
    end else begin
      ack_sync1 <= ack_toggle;
      ack_sync2 <= ack_sync1;
      ack_seen  <= ack_sync2;
      if (req_src && ready_src) begin
        hold_data  <= data_src;
        req_toggle <= ~req_toggle;
      end
    end
  end
  always @(posedge clk_dst) begin
    if (rst_dst) begin
      req_sync1  <= 1'b0;
      req_sync2  <= 1'b0;
      req_seen   <= 1'b0;
      ack_toggle <= 1'b0;
      valid_dst  <= 1'b0;
      data_dst   <= {WIDTH{1'b0}};
    end else begin
      req_sync1 <= req_toggle;
      req_sync2 <= req_sync1;
      valid_dst <= 1'b0;
      if (req_sync2 != req_seen) begin
        data_dst  <= hold_data;
        req_seen  <= req_sync2;
        valid_dst <= 1'b1;
      end
      if (ack_dst) ack_toggle <= req_seen;
    end
  end
endmodule
`default_nettype wire
