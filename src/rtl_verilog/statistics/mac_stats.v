`default_nettype none
module mac_stats (
    input wire mac_clk,
    input wire mac_rst,
    input wire rx_invalid_event,
    input wire rx_crc_event,
    input wire rx_oversize_event,
    input wire rx_unsupported_control_event,
    input wire pause_active,
    input wire pause_expired,
    input wire tx_error_event,
    input wire irq_enable_update,
    input wire [31:0] interrupt_enable_mac,
    input wire irq_clear,
    input wire [6:0] irq_clear_mask,
    input wire counter_clear,
    input wire [2:0] counter_clear_mask,
    output reg [383:0] status_snapshot_mac
);
  reg [31:0] irq_enable;
  wire [31:0] invalid_count, oversize_count, unsupported_count;
  wire [6:0] interrupt_status;
  always @(posedge mac_clk) begin
    if (mac_rst) irq_enable <= 32'd0;
    else if (irq_enable_update) irq_enable <= interrupt_enable_mac;
  end
  stats_counters counters_inst (
      .clk(mac_clk),
      .rst(mac_rst),
      .invalid_event(rx_invalid_event),
      .oversize_event(rx_oversize_event),
      .unsupported_event(rx_unsupported_control_event),
      .clear_mask(counter_clear_mask),
      .clear(counter_clear),
      .invalid_count(invalid_count),
      .oversize_count(oversize_count),
      .unsupported_count(unsupported_count)
  );
  stats_aggregator aggregator_inst (
      .clk(mac_clk),
      .rst(mac_rst),
      .rx_invalid_event(rx_invalid_event),
      .rx_crc_event(rx_crc_event),
      .rx_oversize_event(rx_oversize_event),
      .rx_unsupported_control_event(rx_unsupported_control_event),
      .pause_active(pause_active),
      .pause_expired(pause_expired),
      .tx_error_event(tx_error_event),
      .irq_enable(irq_enable),
      .irq_clear(irq_clear),
      .irq_clear_mask(irq_clear_mask),
      .interrupt_status(interrupt_status)
  );
  always @* begin
    status_snapshot_mac = 384'd0;
    status_snapshot_mac[31:0] = invalid_count;
    status_snapshot_mac[63:32] = oversize_count;
    status_snapshot_mac[95:64] = unsupported_count;
    status_snapshot_mac[127:96] = {25'd0, interrupt_status};
    status_snapshot_mac[159:128] = {31'd0, pause_active};
    status_snapshot_mac[191:160] = {31'd0, pause_expired};
    status_snapshot_mac[223:192] = {31'd0, tx_error_event};
  end
endmodule
`default_nettype wire
