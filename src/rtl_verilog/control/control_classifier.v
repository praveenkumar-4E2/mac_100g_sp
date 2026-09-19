`default_nettype none
module control_classifier (
    input wire [15:0] length_type,
    output wire is_control
);
  assign is_control = (length_type == 16'h8808);
endmodule
`default_nettype wire
