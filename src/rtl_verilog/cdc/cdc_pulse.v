`default_nettype none
module cdc_pulse (
    input  wire clk_src,
    input  wire rst_src,
    input  wire pulse_src,
    input  wire clk_dst,
    input  wire rst_dst,
    output reg  pulse_dst
);
  reg toggle_src, sync1, sync2, seen;
  always @(posedge clk_src) begin
    if (rst_src) toggle_src <= 1'b0;
    else if (pulse_src) toggle_src <= ~toggle_src;
  end
  always @(posedge clk_dst) begin
    if (rst_dst) begin
      sync1 <= 1'b0;
      sync2 <= 1'b0;
      seen <= 1'b0;
      pulse_dst <= 1'b0;
    end else begin
      sync1 <= toggle_src;
      sync2 <= sync1;
      pulse_dst <= sync2 ^ seen;
      seen <= sync2;
    end
  end
endmodule
`default_nettype wire
