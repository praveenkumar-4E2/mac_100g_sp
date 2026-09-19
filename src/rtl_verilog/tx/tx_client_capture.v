`default_nettype none
`include "mac_params.vh"
module tx_client_capture #(
    parameter BUFFER_BYTES = `MAC_TX_BUFFER_BYTES,
    parameter COUNT_WIDTH = $clog2(BUFFER_BYTES + 1),
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1),
    parameter BUFFER_WORDS = BUFFER_BYTES / KEEP_WIDTH,
    parameter WORD_ADDR_WIDTH = $clog2(BUFFER_WORDS)
) (
    input wire clk,
    input wire rst,
    input wire start_capture,
    input wire client_valid,
    input wire [DATA_WIDTH-1:0] client_data,
    input wire [KEEP_WIDTH-1:0] client_keep,
    input wire client_eop,
    input wire [frame_end_byte_index_W-1:0] client_frame_end_byte_index,
    output wire client_ready,
    output reg capture_active,
    output reg capture_done,
    output reg [COUNT_WIDTH-1:0] captured_bytes,
    output wire [31:0] supplied_fcs,
    input wire [WORD_ADDR_WIDTH-1:0] read_addr,
    output wire [DATA_WIDTH-1:0] read_data,
    input wire [WORD_ADDR_WIDTH-1:0] read_addr_1,
    output wire [DATA_WIDTH-1:0] read_data_1
);
  reg [ DATA_WIDTH-1:0] frame_buffer[0:BUFFER_WORDS-1];
  reg [COUNT_WIDTH-1:0] write_count;
  reg [31:0] fcs_tail, fcs_tail_next;
  reg [COUNT_WIDTH-1:0] beat_bytes;
  integer lane_index;
  integer write_byte;
  function [COUNT_WIDTH-1:0] count_lanes;
    input [KEEP_WIDTH-1:0] keep;
    integer lane;
    begin
      count_lanes = {COUNT_WIDTH{1'b0}};
      for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1)
      if (keep[lane]) count_lanes = count_lanes + 1'b1;
    end
  endfunction
  always @* begin
    beat_bytes = count_lanes(client_keep);
    fcs_tail_next = fcs_tail;
    for (lane_index = 0; lane_index < KEEP_WIDTH; lane_index = lane_index + 1)
    if (client_keep[lane_index])
      fcs_tail_next = {client_data[lane_index*8+:8], fcs_tail_next[31:8]};
  end
  assign client_ready = capture_active && (write_count + beat_bytes <= BUFFER_BYTES);
  assign read_data = frame_buffer[read_addr];
  assign read_data_1 = frame_buffer[read_addr_1];
  assign supplied_fcs = fcs_tail;
  always @(posedge clk) begin
    if (rst) begin
      capture_active <= 1'b0;
      capture_done <= 1'b0;
      captured_bytes <= {COUNT_WIDTH{1'b0}};
      write_count <= {COUNT_WIDTH{1'b0}};
      fcs_tail <= 32'd0;
    end else begin
      capture_done <= 1'b0;
      if (start_capture) begin
        capture_active <= 1'b1;
        write_count <= {COUNT_WIDTH{1'b0}};
        captured_bytes <= {COUNT_WIDTH{1'b0}};
        fcs_tail <= 32'd0;
      end
      if (client_valid && client_ready) begin
        for (lane_index = 0; lane_index < KEEP_WIDTH; lane_index = lane_index + 1) begin
          if (client_keep[lane_index] && (write_count + lane_index < BUFFER_BYTES)) begin
            write_byte = (write_count + lane_index) & (KEEP_WIDTH - 1);
            frame_buffer[(write_count+lane_index)>>$clog2(
                KEEP_WIDTH
            )][write_byte*8+:8] <= client_data[lane_index*8+:8];
          end
        end
        fcs_tail <= fcs_tail_next;
        if (client_eop) begin
          captured_bytes <= write_count + beat_bytes;
          capture_active <= 1'b0;
          capture_done   <= 1'b1;
        end else write_count <= write_count + beat_bytes;
      end
    end
  end
endmodule
`default_nettype wire
