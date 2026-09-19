`default_nettype none
module rx_header_extract #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire in_valid,
    output wire in_ready,
    input wire [DATA_WIDTH-1:0] in_data,
    input wire [KEEP_WIDTH-1:0] in_keep,
    input wire in_sop,
    input wire in_eop,
    input wire [frame_end_byte_index_W-1:0] in_frame_end_byte_index,
    input wire in_error,
    output reg frame_done,
    input wire frame_done_ready,
    output reg [47:0] dest_addr,
    output reg [47:0] src_addr,
    output reg [15:0] length_type
);
  assign in_ready = !frame_done || frame_done_ready;
  always @(posedge clk) begin
    if (rst) begin
      frame_done <= 1'b0;
      dest_addr <= 48'd0;
      src_addr <= 48'd0;
      length_type <= 16'd0;
    end else begin
      if (frame_done && frame_done_ready) frame_done <= 1'b0;
      if (in_valid && in_ready) begin
        if (in_sop) begin
          dest_addr <= {
            in_data[7:0],
            in_data[15:8],
            in_data[23:16],
            in_data[31:24],
            in_data[39:32],
            in_data[47:40]
          };
          src_addr <= {
            in_data[55:48],
            in_data[63:56],
            in_data[71:64],
            in_data[79:72],
            in_data[87:80],
            in_data[95:88]
          };
          length_type <= {in_data[103:96], in_data[111:104]};
        end
        if (in_eop) frame_done <= 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
