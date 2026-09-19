`default_nettype none
module rx_length_check #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1),
    parameter MAX_CLIENT_DATA = 1500
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
    input wire [15:0] max_frame_size,
    input wire [15:0] min_frame_size,
    output reg frame_done,
    input wire frame_done_ready,
    output reg length_good,
    output reg length_error,
    output reg alignment_error,
    output reg oversize_error,
    output reg undersize_error,
    output reg [15:0] payload_octets
);
  reg [15:0] total, length_type_capture;
  reg frame_alignment;
  reg [15:0] next_total, length_type_value, payload_count;
  reg short_frame, invalid_type_gap, invalid_length;
  integer lane_index;
  function [15:0] count_lanes;
    input [KEEP_WIDTH-1:0] keep;
    integer lane;
    begin
      count_lanes = 16'd0;
      for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1)
      if (keep[lane]) count_lanes = count_lanes + 16'd1;
    end
  endfunction
  assign in_ready = !frame_done || frame_done_ready;
  always @(posedge clk) begin
    if (rst) begin
      total <= 16'd0;
      length_type_capture <= 16'd0;
      frame_alignment <= 1'b0;
      frame_done <= 1'b0;
      length_good <= 1'b0;
      length_error <= 1'b0;
      alignment_error <= 1'b0;
      oversize_error <= 1'b0;
      undersize_error <= 1'b0;
      payload_octets <= 16'd0;
    end else begin
      if (frame_done && frame_done_ready) frame_done <= 1'b0;
      if (in_valid && in_ready) begin
        if (in_sop) begin
          length_type_capture <= {in_data[103:96], in_data[111:104]};
          frame_alignment <= 1'b0;
          total <= count_lanes(in_keep);
        end else total <= total + count_lanes(in_keep);
        if (in_error) frame_alignment <= 1'b1;
        if (in_eop) begin
          next_total = in_sop ? count_lanes(in_keep) : total + count_lanes(in_keep);
          length_type_value = in_sop ? {in_data[103:96], in_data[111:104]} : length_type_capture;
          payload_count = (next_total >= (16'd14 + (in_fcs_present ? 16'd4 : 16'd0))) ?
              next_total - 16'd14 - (in_fcs_present ? 16'd4 : 16'd0) : 16'd0;
          short_frame = next_total < min_frame_size;
          invalid_type_gap = (length_type_value > MAX_CLIENT_DATA) &&
              (length_type_value < 16'd1536);
          invalid_length = (length_type_value <= MAX_CLIENT_DATA) &&
              (payload_count < length_type_value);
          payload_octets <= payload_count;
          alignment_error <= frame_alignment || in_error ||
              (next_total < (16'd14 + (in_fcs_present ? 16'd4 : 16'd0)));
          oversize_error <= next_total > max_frame_size;
          undersize_error <= next_total < min_frame_size;
          length_error <= short_frame || invalid_type_gap || invalid_length ||
              (next_total > max_frame_size);
          length_good <= !(short_frame || invalid_type_gap || invalid_length || frame_alignment ||
                           in_error || (next_total < (16'd14 + (in_fcs_present ? 16'd4 : 16'd0))) ||
                           (next_total > max_frame_size));
          frame_done <= 1'b1;
        end
      end
    end
  end
endmodule
`default_nettype wire
