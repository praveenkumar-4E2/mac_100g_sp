`default_nettype none
module pause_admission_gate #(
    parameter MAX_START_DELAY_QUANTA = 394
) (
    input wire clk,
    input wire rst,
    input wire paused,
    input wire pause_event_accepted,
    input wire [15:0] pause_time,
    input wire data_req_valid,
    output wire data_req_ready,
    input wire data_frame_active,
    input wire data_frame_done,
    input wire control_req_valid,
    output wire control_req_ready,
    output wire data_admit,
    output wire control_admit,
    input wire timing_quantum_tick,
    input wire new_data_frame_start,
    input wire [2:0] speed,
    output reg timing_check_active,
    output reg timing_check_pass,
    output reg timing_check_violation,
    output reg [9:0] timing_elapsed_quanta
);
  reg [9:0] max_start_delay;
  always @* begin
    case (speed)
      3'b010, 3'b011: max_start_delay = 10'd118;
      3'b100: max_start_delay = 10'd60;
      default: max_start_delay = 10'd394;
    endcase
  end
  assign data_admit = !paused;
  assign control_admit = 1'b1;
  assign data_req_ready = !paused && !data_frame_active;
  assign control_req_ready = 1'b1;
  always @(posedge clk) begin
    if (rst) begin
      timing_check_active <= 1'b0;
      timing_check_pass <= 1'b0;
      timing_check_violation <= 1'b0;
      timing_elapsed_quanta <= 10'd0;
    end else begin
      timing_check_pass <= 1'b0;
      timing_check_violation <= 1'b0;
      if (pause_event_accepted && (pause_time != 16'd0)) begin
        timing_check_active   <= 1'b1;
        timing_elapsed_quanta <= 10'd0;
      end else if (timing_check_active) begin
        if (new_data_frame_start) begin
          timing_check_active <= 1'b0;
          if (timing_elapsed_quanta <= max_start_delay) timing_check_pass <= 1'b1;
          else timing_check_violation <= 1'b1;
        end else if (timing_quantum_tick && (timing_elapsed_quanta < (max_start_delay + 1'b1)))
          timing_elapsed_quanta <= timing_elapsed_quanta + 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
