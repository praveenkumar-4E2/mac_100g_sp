`default_nettype none
module stats_counters (
    input wire clk,
    input wire rst,
    input wire invalid_event,
    input wire oversize_event,
    input wire unsupported_event,
    input wire [2:0] clear_mask,
    input wire clear,
    output reg [31:0] invalid_count,
    output reg [31:0] oversize_count,
    output reg [31:0] unsupported_count
);
  always @(posedge clk) begin
    if (rst) begin
      invalid_count <= 32'd0;
      oversize_count <= 32'd0;
      unsupported_count <= 32'd0;
    end else begin
      if (clear_mask[0] && clear) invalid_count <= 32'd0;
      else if (invalid_event) invalid_count <= invalid_count + 32'd1;
      if (clear_mask[1] && clear) oversize_count <= 32'd0;
      else if (oversize_event) oversize_count <= oversize_count + 32'd1;
      if (clear_mask[2] && clear) unsupported_count <= 32'd0;
      else if (unsupported_event) unsupported_count <= unsupported_count + 32'd1;
    end
  end
endmodule
`default_nettype wire
