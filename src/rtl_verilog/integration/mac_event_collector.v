`default_nettype none
module mac_event_collector (
    input wire rx_invalid_event,
    input wire rx_crc_event,
    input wire rx_oversize_event,
    input wire rx_unsupported_control_event,
    input wire pause_expired,
    input wire tx_error_event,
    output wire [5:0] event_vector
);
  assign event_vector = {
    tx_error_event,
    pause_expired,
    rx_unsupported_control_event,
    rx_oversize_event,
    rx_crc_event,
    rx_invalid_event
  };
endmodule
`default_nettype wire
