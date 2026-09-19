`default_nettype none
module stats_aggregator (
    input wire clk,
    input wire rst,
    input wire rx_invalid_event,
    input wire rx_crc_event,
    input wire rx_oversize_event,
    input wire rx_unsupported_control_event,
    input wire pause_active,
    input wire pause_expired,
    input wire tx_error_event,
    input wire [31:0] irq_enable,
    input wire irq_clear,
    input wire [6:0] irq_clear_mask,
    output wire [6:0] interrupt_status
);
  reg [6:0] causes;
  always @(posedge clk) begin
    if (rst) causes <= 7'd0;
    else begin
      if (irq_clear) causes <= causes & ~irq_clear_mask;
      if (rx_invalid_event) causes[0] <= 1'b1;
      if (rx_crc_event) causes[1] <= 1'b1;
      if (rx_oversize_event) causes[2] <= 1'b1;
      if (rx_unsupported_control_event) causes[3] <= 1'b1;
      if (pause_active) causes[4] <= 1'b1;
      if (pause_expired) causes[5] <= 1'b1;
      if (tx_error_event) causes[6] <= 1'b1;
    end
  end
  assign interrupt_status = causes & irq_enable[6:0];
endmodule
`default_nettype wire
