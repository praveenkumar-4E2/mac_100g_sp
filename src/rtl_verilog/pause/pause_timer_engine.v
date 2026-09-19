`default_nettype none
module pause_timer_engine #(
    parameter QUANTUM_BITS = 9
) (
    input wire clk,
    input wire rst,
    input wire load_valid,
    input wire [15:0] load_time,
    input wire bit_time_tick,
    input wire [2:0] speed,
    output wire paused,
    output reg timer_done,
    output wire [15+QUANTUM_BITS:0] remaining_bit_times
);
  localparam COUNTER_WIDTH = 16 + QUANTUM_BITS;
  reg  [COUNTER_WIDTH-1:0] count;
  wire [COUNTER_WIDTH-1:0] load_count = {{QUANTUM_BITS{1'b0}}, load_time} << QUANTUM_BITS;
  assign paused = (count != {COUNTER_WIDTH{1'b0}});
  assign remaining_bit_times = count;
  always @(posedge clk) begin
    if (rst) begin
      count <= {COUNTER_WIDTH{1'b0}};
      timer_done <= 1'b0;
    end else begin
      timer_done <= 1'b0;
      if (load_valid) count <= load_count;
      else if (bit_time_tick && (count != {COUNTER_WIDTH{1'b0}})) begin
        if (count == {{(COUNTER_WIDTH - 1) {1'b0}}, 1'b1}) begin
          count <= {COUNTER_WIDTH{1'b0}};
          timer_done <= 1'b1;
        end else count <= count - 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
