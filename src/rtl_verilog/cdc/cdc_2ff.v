`default_nettype none
module cdc_2ff (
    input  wire clk_dst,
    input  wire rst_dst,
    input  wire signal_src,
    output reg  signal_dst
);
  reg sync_meta;
  always @(posedge clk_dst) begin
    if (rst_dst) begin
      sync_meta  <= 1'b0;
      signal_dst <= 1'b0;
    end else begin
      sync_meta  <= signal_src;
      signal_dst <= sync_meta;
    end
  end
endmodule
`default_nettype wire
