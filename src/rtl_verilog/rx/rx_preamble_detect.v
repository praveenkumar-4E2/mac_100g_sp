`default_nettype none
module rx_preamble_detect #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire in_valid,
    output reg in_ready,
    input wire [DATA_WIDTH-1:0] in_data,
    input wire [KEEP_WIDTH-1:0] in_keep,
    input wire in_sop,
    input wire in_eop,
    input wire [frame_end_byte_index_W-1:0] in_frame_end_byte_index,
    input wire in_error,
    input wire in_fcs_present,
    output wire out_valid,
    input wire out_ready,
    output reg [DATA_WIDTH-1:0] out_data,
    output wire [KEEP_WIDTH-1:0] out_keep,
    output wire out_sop,
    output wire out_eop,
    output wire [frame_end_byte_index_W-1:0] out_frame_end_byte_index,
    output wire out_error,
    output wire out_fcs_present
);
  localparam SEARCH = 2'd0, BODY = 2'd1, FLUSH = 2'd2;
  reg [1:0] state;
  reg [7:0] hist[0:6], out_buf[0:127], emit_buf[0:63];
  reg [frame_end_byte_index_W-1:0] out_cnt, emit_pos;
  reg [KEEP_WIDTH-1:0] emit_keep;
  reg emit_sop, emit_eop, emit_error, emit_valid, body_first, error_q, flush_remain, fcs_present_q;
  reg [6:0] beat_count;
  reg sfd_found;
  reg [5:0] sfd_lane;
  reg [7:0] hist_update[0:6];
  integer i, j, k, p, s, total, body_cnt, lane;
  reg [7:0] tmp_buf[0:63];
  reg [7:0] c[0:70];
  reg [70:0] c_vld;
  reg found;
  function [KEEP_WIDTH-1:0] keep_mask;
    input integer n;
    integer x;
    begin
      keep_mask = {KEEP_WIDTH{1'b0}};
      for (x = 0; x < KEEP_WIDTH; x = x + 1) if (x < n) keep_mask[x] = 1'b1;
    end
  endfunction
  task stage_full;
    input [DATA_WIDTH-1:0] data;
    input integer cnt;
    input integer off;
    input sop;
    integer x, src;
    begin
      for (x = 0; x < 64; x = x + 1) begin
        if (x < cnt) emit_buf[x] = out_buf[x];
        else begin
          src = off + x - cnt;
          emit_buf[x] = (src < 64) ? data[src*8+:8] : 8'd0;
        end
      end
      emit_keep  = {KEEP_WIDTH{1'b1}};
      emit_pos   = 64;
      emit_sop   = sop;
      emit_eop   = 1'b0;
      emit_error = 1'b0;
    end
  endtask
  task stage_partial;
    input integer n;
    input [DATA_WIDTH-1:0] data;
    input integer cnt;
    input integer off;
    input eop;
    integer x, src;
    begin
      for (x = 0; x < 64; x = x + 1) begin
        if (x < n) begin
          if (x < cnt) emit_buf[x] = out_buf[x];
          else begin
            src = off + x - cnt;
            emit_buf[x] = (src < 64) ? data[src*8+:8] : 8'd0;
          end
        end else emit_buf[x] = 8'd0;
      end
      emit_keep  = keep_mask(n);
      emit_pos   = n;
      emit_eop   = eop;
      emit_error = error_q;
    end
  endtask
  always @* begin
    for (i = 0; i < 7; i = i + 1) begin
      c[i] = hist[i];
      c_vld[i] = 1'b1;
    end
    for (i = 0; i < 64; i = i + 1) begin
      c[7+i] = in_data[i*8+:8];
      c_vld[7+i] = in_keep[i];
    end
    found = 1'b0;
    sfd_found = 1'b0;
    sfd_lane = 6'd0;
    for (p = 7; p <= 70; p = p + 1)
    if (!found && c_vld[p] && (c[p] == 8'hd5) && (c[p-1] == 8'h55) && (c[p-2] == 8'h55) &&
        (c[p-3] == 8'h55) && (c[p-4] == 8'h55) && (c[p-5] == 8'h55) && (c[p-6] == 8'h55) &&
        (c[p-7] == 8'h55)) begin
      found = 1'b1;
      sfd_found = 1'b1;
      sfd_lane = p - 7;
    end
    beat_count = 7'd0;
    for (k = 0; k < 64; k = k + 1) if (in_keep[k]) beat_count = beat_count + 1'b1;
    for (j = 0; j < 7; j = j + 1)
    if (j + beat_count < 7) hist_update[j] = hist[j+beat_count];
    else hist_update[j] = in_data[(j+beat_count-7)*8+:8];
    in_ready = 1'b0;
    if (state == SEARCH) in_ready = 1'b1;
    else if (state == BODY) in_ready = !(emit_valid && !out_ready);
    out_data = {DATA_WIDTH{1'b0}};
    for (j = 0; j < 64; j = j + 1) out_data[j*8+:8] = emit_buf[j];
  end
  assign out_valid = emit_valid;
  assign out_keep = emit_keep;
  assign out_sop = emit_sop;
  assign out_eop = emit_eop;
  assign out_frame_end_byte_index = emit_pos;
  assign out_error = emit_error;
  assign out_fcs_present = fcs_present_q;
  always @(posedge clk) begin
    if (rst) begin
      state <= SEARCH;
      for (i = 0; i < 7; i = i + 1) hist[i] <= 8'd0;
      for (i = 0; i < 128; i = i + 1) out_buf[i] <= 8'd0;
      for (i = 0; i < 64; i = i + 1) emit_buf[i] <= 8'd0;
      emit_keep <= {KEEP_WIDTH{1'b0}};
      emit_pos <= {frame_end_byte_index_W{1'b0}};
      emit_sop <= 1'b0;
      emit_eop <= 1'b0;
      emit_error <= 1'b0;
      emit_valid <= 1'b0;
      out_cnt <= {frame_end_byte_index_W{1'b0}};
      body_first <= 1'b0;
      error_q <= 1'b0;
      flush_remain <= 1'b0;
      fcs_present_q <= 1'b0;
    end else begin
      if (emit_valid && out_ready) begin
        emit_valid <= 1'b0;
        emit_sop   <= 1'b0;
        emit_eop   <= 1'b0;
      end
      case (state)
        SEARCH:
        if (in_valid && in_ready) begin
          for (i = 0; i < 7; i = i + 1) hist[i] <= hist_update[i];
          if (sfd_found && !in_error) begin
            s = sfd_lane + 1;
            body_cnt = beat_count - s;
            fcs_present_q <= in_fcs_present;
            if (body_cnt > 0) begin
              for (i = 0; i < body_cnt; i = i + 1)
              if (s + i < 64) out_buf[i] <= in_data[(s+i)*8+:8];
              out_cnt <= body_cnt;
              body_first <= 1'b1;
              error_q <= 1'b0;
              if (in_eop) begin
                stage_partial(body_cnt, in_data, 0, s, 1'b1);
                emit_valid <= 1'b1;
                emit_sop <= 1'b1;
                emit_eop <= 1'b1;
                state <= FLUSH;
              end else if (body_cnt >= 64) begin
                stage_full(in_data, 0, s, 1'b1);
                emit_valid <= 1'b1;
                state <= BODY;
              end else state <= BODY;
            end else begin
              body_first <= 1'b0;
              error_q <= 1'b0;
              fcs_present_q <= 1'b0;
              state <= SEARCH;
            end
          end else begin
            error_q <= 1'b0;
            body_first <= 1'b0;
            state <= SEARCH;
          end
        end
        BODY:
        if (in_valid && in_ready) begin
          for (i = 0; i < 7; i = i + 1) hist[i] <= hist_update[i];
          if (in_error) error_q <= 1'b1;
          for (i = 0; i < beat_count; i = i + 1) out_buf[out_cnt+i] <= in_data[i*8+:8];
          total = out_cnt + beat_count;
          if (in_eop) begin
            if (total > 64) begin
              stage_full(in_data, out_cnt, 0, body_first);
              emit_valid <= 1'b1;
              for (i = 0; i < total - 64; i = i + 1) tmp_buf[i] = in_data[(64-out_cnt+i)*8+:8];
              for (i = 0; i < total - 64; i = i + 1) out_buf[i] <= tmp_buf[i];
              out_cnt <= total - 64;
              flush_remain <= 1'b1;
              body_first <= 1'b0;
              state <= FLUSH;
            end else begin
              stage_partial(total, in_data, out_cnt, 0, 1'b1);
              emit_valid <= 1'b1;
              emit_sop <= body_first;
              emit_eop <= 1'b1;
              emit_error <= error_q | in_error;
              emit_keep <= keep_mask(total);
              emit_pos <= total;
              body_first <= 1'b0;
              flush_remain <= 1'b0;
              state <= FLUSH;
            end
          end else if (total >= 64) begin
            stage_full(in_data, out_cnt, 0, body_first);
            emit_valid <= 1'b1;
            for (i = 0; i < total - 64; i = i + 1) tmp_buf[i] = in_data[(64-out_cnt+i)*8+:8];
            for (i = 0; i < total - 64; i = i + 1) out_buf[i] <= tmp_buf[i];
            out_cnt <= total - 64;
            body_first <= 1'b0;
            state <= BODY;
          end else begin
            out_cnt <= total;
            body_first <= 1'b0;
            state <= BODY;
          end
        end
        FLUSH:
        // A frame that crosses the 64-byte output boundary has one final
        // buffered fragment.  Issue it only after the preceding beat has
        // retired, and do not admit the next input frame until the fragment
        // has itself been accepted.
        if (!emit_valid && flush_remain) begin
          stage_partial(out_cnt, {DATA_WIDTH{1'b0}}, out_cnt, 0, 1'b1);
          emit_valid <= 1'b1;
          emit_sop <= 1'b0;
          emit_eop <= 1'b1;
          emit_error <= error_q;
          emit_keep <= keep_mask(out_cnt);
          emit_pos <= out_cnt;
          flush_remain <= 1'b0;
          out_cnt <= {frame_end_byte_index_W{1'b0}};
          error_q <= 1'b0;
          body_first <= 1'b0;
          state <= FLUSH;
        end else if (!emit_valid && !flush_remain) begin
          error_q <= 1'b0;
          fcs_present_q <= 1'b0;
          body_first <= 1'b0;
          state <= SEARCH;
        end
        default: state <= SEARCH;
      endcase
    end
  end
endmodule
`default_nettype wire
