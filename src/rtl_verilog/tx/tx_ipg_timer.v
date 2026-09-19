`default_nettype none
module tx_ipg_timer_stage #(
    parameter IPG_VALUE = 96,
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [frame_end_byte_index_W-1:0] frame_end_byte_index,
    input wire enable,
    input wire tick,
    input wire [2:0] speed,
    output wire done,
    output reg [6:0] remaining
);
  localparam IPG_BYTES = (IPG_VALUE + 7) / 8;
  reg active;
  wire needs_idle_beat = (frame_end_byte_index > (KEEP_WIDTH - IPG_BYTES));
  always @(posedge clk) begin
    if (rst) begin
      remaining <= 7'd0;
      active <= 1'b0;
    end else if (start) begin
      // The unused lanes of the previous final beat already occupy line
      // time.  At a 512-bit boundary only a single whole idle beat is ever
      // needed for the 96-bit Ethernet IPG.
      remaining <= needs_idle_beat ? 7'd1 : 7'd0;
      active <= needs_idle_beat;
    end else if (active && enable && tick) begin
      if (remaining == 7'd1) begin
        remaining <= 7'd0;
        active <= 1'b0;
      end else remaining <= remaining - 1'b1;
    end
  end
  assign done = !active;
endmodule
`default_nettype wire
