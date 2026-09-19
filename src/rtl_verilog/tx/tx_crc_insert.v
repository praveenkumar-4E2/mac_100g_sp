`default_nettype none
module tx_crc_insert #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8
) (
    input wire clk,
    input wire rst,
    input wire crc_accum,
    input wire crc_init,
    input wire [DATA_WIDTH-1:0] crc_data,
    input wire [KEEP_WIDTH-1:0] crc_keep,
    input wire client_fcs_present,
    input wire [31:0] supplied_fcs,
    output wire [31:0] generated_fcs,
    output wire [31:0] selected_fcs
);
  reg [31:0] crc_state;
  reg [31:0] crc_curr, crc_next;
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
    crc_curr = crc_init ? 32'hFFFFFFFF : crc_state;
    crc_next = crc_curr;
    for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1)
    if (crc_keep[lane]) crc_next = update_byte(crc_next, crc_data[lane*8+:8]);
  end
  always @(posedge clk) begin
    if (rst) crc_state <= 32'd0;
    else if (crc_accum) crc_state <= crc_next;
  end
  assign generated_fcs = ~crc_next;
  assign selected_fcs  = client_fcs_present ? supplied_fcs : generated_fcs;
endmodule
`default_nettype wire
