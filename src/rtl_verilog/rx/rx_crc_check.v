`default_nettype none
module rx_crc_check #(
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
    input wire in_fcs_present,
    output reg frame_done,
    input wire frame_done_ready,
    output reg crc_good,
    output reg crc_error,
    output reg [31:0] received_fcs
);
  reg [31:0] crc_state, last4;
  // The largest supported MAC frame is 16,384 octets.  A 12-bit total
  // wraps at 4,096 and falsely reports a CRC failure for jumbo profiles.
  reg [15:0] total;
  reg [31:0] next_crc, next_last4;
  reg [15:0] next_total;
  assign in_ready = !frame_done || frame_done_ready;
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
  function [31:0] next_crc_val;
    input sop;
    input [31:0] crc;
    input [DATA_WIDTH-1:0] data;
    input [KEEP_WIDTH-1:0] keep;
    reg [31:0] value;
    integer lane;
    begin
      value = sop ? 32'hFFFFFFFF : crc;
      for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1)
      if (keep[lane]) value = update_byte(value, data[lane*8+:8]);
      next_crc_val = value;
    end
  endfunction
  function [31:0] shift_last4;
    input [31:0] cur;
    input [DATA_WIDTH-1:0] data;
    input [KEEP_WIDTH-1:0] keep;
    reg [31:0] value;
    integer lane;
    begin
      value = cur;
      for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1)
      if (keep[lane]) value = {value[23:0], data[lane*8+:8]};
      shift_last4 = value;
    end
  endfunction
  function [15:0] count_lanes;
    input [KEEP_WIDTH-1:0] keep;
    integer lane;
    begin
      count_lanes = 16'd0;
      for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1)
      if (keep[lane]) count_lanes = count_lanes + 16'd1;
    end
  endfunction
  always @(posedge clk) begin
    if (rst) begin
      crc_state <= 32'hFFFFFFFF;
      last4 <= 32'd0;
      total <= 16'd0;
      frame_done <= 1'b0;
      crc_good <= 1'b0;
      crc_error <= 1'b0;
      received_fcs <= 32'd0;
    end else begin
      if (frame_done && frame_done_ready) frame_done <= 1'b0;
      if (in_valid && in_ready) begin
        next_crc   = next_crc_val(in_sop, crc_state, in_data, in_keep);
        next_last4 = shift_last4(last4, in_data, in_keep);
        next_total = in_sop ? count_lanes(in_keep) : total + count_lanes(in_keep);
        crc_state <= next_crc;
        last4 <= next_last4;
        total <= next_total;
        if (in_eop) begin
          if (in_fcs_present) begin
            crc_good  <= !in_error && (next_total >= 16'd4) && (next_crc == 32'hDEBB20E3);
            crc_error <= in_error || (next_total < 16'd4) || (next_crc != 32'hDEBB20E3);
          end else begin
            crc_good  <= !in_error;
            crc_error <= in_error;
          end
          received_fcs <= next_last4;
          frame_done   <= 1'b1;
        end
      end
    end
  end
endmodule
`default_nettype wire
