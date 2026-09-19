`default_nettype none
module pause_rx (
    input wire clk,
    input wire rst,
    input wire pause_event_valid,
    input wire [15:0] pause_opcode,
    input wire [47:0] pause_dest_addr,
    input wire [15:0] pause_time,
    input wire transmission_in_progress,
    input wire [47:0] local_addr,
    output reg timer_load_valid,
    output reg [15:0] timer_load_time,
    output reg pause_event_accepted,
    output wire pending_event
);
  reg [15:0] pending_time;
  reg event_is_pending;
  assign pending_event = event_is_pending;
  always @(posedge clk) begin
    if (rst) begin
      timer_load_valid <= 1'b0;
      timer_load_time <= 16'd0;
      pause_event_accepted <= 1'b0;
      pending_time <= 16'd0;
      event_is_pending <= 1'b0;
    end else begin
      timer_load_valid <= 1'b0;
      pause_event_accepted <= 1'b0;
      if (pause_event_valid && (pause_opcode == 16'h0001) &&
          ((pause_dest_addr == 48'h0180c2000001) || (pause_dest_addr == local_addr))) begin
        pending_time <= pause_time;
        event_is_pending <= 1'b1;
      end else if (event_is_pending && !transmission_in_progress) begin
        timer_load_valid <= 1'b1;
        timer_load_time <= pending_time;
        pause_event_accepted <= 1'b1;
        event_is_pending <= 1'b0;
      end
    end
  end
endmodule
`default_nettype wire
