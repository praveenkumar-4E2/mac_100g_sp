`default_nettype none
module bit_time_counter #(
    parameter WIDTH = 8,
    parameter [WIDTH-1:0] TERMINAL_COUNT = {WIDTH{1'b1}}
) (
    input wire clk,
    input wire rst,
    input wire clear,
    input wire enable,
    input wire tick,
    output reg [WIDTH-1:0] count,
    output wire terminal
);
  always @(posedge clk) begin
    if (rst || clear) count <= {WIDTH{1'b0}};
    else if (enable && tick && (count < TERMINAL_COUNT)) count <= count + 1'b1;
  end
  assign terminal = (count == TERMINAL_COUNT);
endmodule
`default_nettype wire
