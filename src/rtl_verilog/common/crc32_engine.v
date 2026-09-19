`default_nettype none
module crc32_engine #(
    parameter DATA_WIDTH = 8,
    parameter BYTE_LANES = DATA_WIDTH / 8
) (
    input wire clk,
    input wire rst,
    input wire init,
    input wire data_valid,
    input wire [DATA_WIDTH-1:0] data,
    input wire [BYTE_LANES-1:0] keep,
    output reg [31:0] crc_state,
    output wire [31:0] fcs_value
);
  reg [31:0] next_crc;
  integer lane;
  function [31:0] update_byte;
    input [31:0] crc;
    input [7:0] data_byte;
    reg [31:0] value;
    reg feedback;
    integer bit_index;
    begin
      value = crc;
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        feedback = value[0] ^ data_byte[bit_index];
        value = value >> 1;
        if (feedback) value = value ^ 32'hEDB88320;
      end
      update_byte = value;
    end
  endfunction
  always @* begin
    next_crc = crc_state;
    if (data_valid) begin
      for (lane = 0; lane < BYTE_LANES; lane = lane + 1)
      if (keep[lane]) next_crc = update_byte(next_crc, data[lane*8+:8]);
    end
  end
  always @(posedge clk) begin
    if (rst || init) crc_state <= 32'hFFFFFFFF;
    else crc_state <= next_crc;
  end
  assign fcs_value = ~crc_state;
endmodule
`default_nettype wire
