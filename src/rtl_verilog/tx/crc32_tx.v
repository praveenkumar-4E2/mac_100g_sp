`default_nettype none
module crc32_tx (
    input wire clk,
    input wire rst,
    input wire init,
    input wire data_valid,
    input wire [7:0] data,
    output wire [31:0] crc_out
);
  reg [31:0] crc;
  reg [31:0] next_crc;
  integer i;
  reg feedback;
  always @* begin
    next_crc = crc;
    if (data_valid)
      for (i = 0; i < 8; i = i + 1) begin
        feedback = next_crc[0] ^ data[i];
        next_crc = next_crc >> 1;
        if (feedback) next_crc = next_crc ^ 32'hEDB88320;
      end
  end
  always @(posedge clk)
    if (rst || init) crc <= 32'hffffffff;
    else crc <= next_crc;
  assign crc_out = ~crc;
endmodule
`default_nettype wire
