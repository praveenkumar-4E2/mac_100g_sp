`default_nettype none
`include "mac_params.vh"
module rx_frame_emit #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1),
    parameter MAX_BODY_OCTETS = `MAC_RX_BUFFER_BYTES,
    parameter BODY_CNT_WIDTH = $clog2(MAX_BODY_OCTETS + 1)
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
    input wire header_done,
    output wire header_done_ready,
    input wire [47:0] header_dest_addr,
    input wire [47:0] header_src_addr,
    input wire [15:0] header_length_type,
    input wire crc_done,
    output wire crc_done_ready,
    input wire crc_good,
    input wire crc_error_in,
    input wire [31:0] received_fcs_in,
    input wire length_done,
    output wire length_done_ready,
    input wire length_good,
    input wire length_error_in,
    input wire oversize_error_in,
    input wire alignment_error_in,
    input wire [15:0] payload_octets_in,
    input wire filter_accept,
    input wire [15:0] max_frame_size,
    output reg client_valid,
    input wire client_ready,
    output reg [DATA_WIDTH-1:0] client_data,
    output reg [KEEP_WIDTH-1:0] client_keep,
    output reg client_sop,
    output reg client_eop,
    output reg [frame_end_byte_index_W-1:0] client_frame_end_byte_index,
    output reg client_error,
    output reg client_fcs_present,
    output reg [47:0] dest_addr,
    output reg [47:0] src_addr,
    output reg [15:0] length_type,
    output reg [31:0] received_fcs,
    output reg frame_valid,
    output reg frame_drop,
    output reg crc_error,
    output reg length_error,
    output reg oversize_error,
    output reg alignment_error,
    output reg filter_hit,
    output wire busy
);
  localparam CAPTURE = 2'd0, DECIDE = 2'd1, EMIT = 2'd2;
  reg [1:0] state;
  reg [BODY_CNT_WIDTH-1:0] body_count, emit_index, emit_length;
  reg [7:0] frame_buffer[0:MAX_BODY_OCTETS-1];
  integer lane, idx, remaining, beat_bytes;
  reg [BODY_CNT_WIDTH-1:0] next_emit_length;
  function [BODY_CNT_WIDTH-1:0] count_lanes;
    input [KEEP_WIDTH-1:0] keep;
    integer k;
    begin
      count_lanes = {BODY_CNT_WIDTH{1'b0}};
      for (k = 0; k < KEEP_WIDTH; k = k + 1) if (keep[k]) count_lanes = count_lanes + 1'b1;
    end
  endfunction
  function [KEEP_WIDTH-1:0] keep_mask;
    input integer n;
    integer k;
    begin
      keep_mask = {KEEP_WIDTH{1'b0}};
      for (k = 0; k < KEEP_WIDTH; k = k + 1) if (k < n) keep_mask[k] = 1'b1;
    end
  endfunction
  assign in_ready = (state == CAPTURE);
  // Header/CRC/length completion channels are independent valid/ready
  // handshakes.  They must be acknowledged while the emitter is available
  // to capture or decide a frame.  Restricting ready to the aggregate
  // all-done condition can leave all three `frame_done` flags asserted after
  // the emitter returns to CAPTURE; their in_ready signals then remain low
  // and the RX ingress deadlocks on the next frame.
  assign header_done_ready = (state != EMIT);
  assign crc_done_ready = header_done_ready;
  assign length_done_ready = header_done_ready;
  assign busy = (state != CAPTURE);
  always @* begin
    remaining = emit_length - emit_index;
    if (remaining >= KEEP_WIDTH) beat_bytes = KEEP_WIDTH;
    else if (remaining > 0) beat_bytes = remaining;
    else beat_bytes = 0;
    client_valid = (state == EMIT) && (emit_index < emit_length);
    client_sop = client_valid && (emit_index == 0);
    client_eop = client_valid && (remaining <= KEEP_WIDTH);
    client_frame_end_byte_index = beat_bytes;
    client_keep = keep_mask(beat_bytes);
    client_error = 1'b0;
    client_fcs_present = 1'b0;
    client_data = {DATA_WIDTH{1'b0}};
    if (client_valid)
      for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) begin
        idx = emit_index + lane;
        if ((emit_index + lane < emit_length) && (idx < MAX_BODY_OCTETS))
          client_data[lane*8+:8] = frame_buffer[idx];
      end
  end
  always @(posedge clk) begin
    if (rst) begin
      state <= CAPTURE;
      body_count <= {BODY_CNT_WIDTH{1'b0}};
      emit_index <= {BODY_CNT_WIDTH{1'b0}};
      emit_length <= {BODY_CNT_WIDTH{1'b0}};
      dest_addr <= 48'd0;
      src_addr <= 48'd0;
      length_type <= 16'd0;
      received_fcs <= 32'd0;
      frame_valid <= 1'b0;
      frame_drop <= 1'b0;
      crc_error <= 1'b0;
      length_error <= 1'b0;
      oversize_error <= 1'b0;
      alignment_error <= 1'b0;
      filter_hit <= 1'b0;
    end else begin
      frame_valid <= 1'b0;
      frame_drop <= 1'b0;
      crc_error <= 1'b0;
      length_error <= 1'b0;
      oversize_error <= 1'b0;
      alignment_error <= 1'b0;
      filter_hit <= 1'b0;
      case (state)
        CAPTURE:
        if (in_valid && in_ready) begin
          for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1)
          if (in_keep[lane] && (body_count + lane < MAX_BODY_OCTETS) &&
              (body_count + lane < max_frame_size))
            frame_buffer[body_count+lane] <= in_data[lane*8+:8];
          if (in_sop) body_count <= count_lanes(in_keep);
          else body_count <= body_count + count_lanes(in_keep);
          if (in_eop) state <= DECIDE;
        end
        DECIDE:
        if (header_done && crc_done && length_done) begin
          dest_addr <= header_dest_addr;
          src_addr <= header_src_addr;
          length_type <= header_length_type;
          received_fcs <= received_fcs_in;
          crc_error <= crc_error_in;
          length_error <= length_error_in;
          oversize_error <= oversize_error_in;
          alignment_error <= alignment_error_in;
          if (crc_good && length_good && filter_accept) begin
            frame_valid <= 1'b1;
            filter_hit  <= 1'b1;
            next_emit_length = 14 +
                ((header_length_type <= 1500) ? header_length_type : payload_octets_in);
            emit_length <= next_emit_length;
            emit_index <= {BODY_CNT_WIDTH{1'b0}};
            state <= EMIT;
          end else begin
            frame_drop <= 1'b1;
            body_count <= {BODY_CNT_WIDTH{1'b0}};
            state <= CAPTURE;
          end
        end
        EMIT:
        if (client_valid && client_ready) begin
          if (client_eop) begin
            state <= CAPTURE;
            body_count <= {BODY_CNT_WIDTH{1'b0}};
            emit_index <= {BODY_CNT_WIDTH{1'b0}};
          end else emit_index <= emit_index + KEEP_WIDTH;
        end
        default: state <= CAPTURE;
      endcase
    end
  end
endmodule
`default_nettype wire
