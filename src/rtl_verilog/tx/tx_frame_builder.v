`default_nettype none
`include "mac_params.vh"
module tx_frame_builder #(
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
    output wire req_ready,
    input wire capture_done,
    input wire [COUNT_WIDTH-1:0] captured_bytes,
    input wire [31:0] supplied_fcs,
    output reg [WORD_ADDR_WIDTH-1:0] capture_read_addr,
    input wire [DATA_WIDTH-1:0] capture_read_data,
    output reg [WORD_ADDR_WIDTH-1:0] capture_read_addr_1,
    input wire [DATA_WIDTH-1:0] capture_read_data_1,
    input wire ready,
    input wire [47:0] dest_addr,
    input wire [47:0] src_addr,
    input wire [15:0] length_type,
    input wire client_fcs_present,
    output reg out_valid,
    output reg [DATA_WIDTH-1:0] out_data,
    output reg [KEEP_WIDTH-1:0] out_keep,
    output reg out_sop,
    output reg out_eop,
    output reg [frame_end_byte_index_W-1:0] out_frame_end_byte_index,
    output reg out_error,
    output wire busy,
    output reg frame_done
);
  localparam IDLE = 2'd0, WAIT_CAPTURE = 2'd1, EMIT = 2'd2;
  localparam PREAMBLE_OCTETS = 7, PREAMBLE_SFD_OCTETS = 8, FCS_OCTETS = 4, FIXED_OCTETS = 12;
  reg [1:0] state;
  reg fcs_present_reg;
  wire [COUNT_WIDTH-1:0] body_len = (captured_bytes >= (fcs_present_reg ? FCS_OCTETS : 0)) ?
      captured_bytes - (fcs_present_reg ? FCS_OCTETS : 0) : {COUNT_WIDTH{1'b0}};
  wire [COUNT_WIDTH-1:0] payload_len, pad_len;
  reg [COUNT_WIDTH-1:0] beat_index;
  wire [COUNT_WIDTH:0] frame_len = FIXED_OCTETS + body_len + pad_len;
  reg [KEEP_WIDTH-1:0] crc_keep;
  wire [31:0] fcs_word;
  reg transfer;
  integer
      lane,
      remaining,
      beat_bytes,
      payload_emitted,
      payload_base,
      global_byte,
      payload_off,
      payload_word,
      fcs_off;
  function [KEEP_WIDTH-1:0] keep_mask;
    input integer count;
    integer index;
    begin
      keep_mask = {KEEP_WIDTH{1'b0}};
      for (index = 0; index < KEEP_WIDTH; index = index + 1)
      if (index < count) keep_mask[index] = 1'b1;
    end
  endfunction
  tx_pad_calc #(
      .COUNT_WIDTH(COUNT_WIDTH)
  ) pad_calc_inst (
      .client_bytes(captured_bytes),
      .fcs_present(fcs_present_reg),
      .payload_bytes(payload_len),
      .pad_bytes(pad_len)
  );
  tx_crc_insert #(
      .DATA_WIDTH(DATA_WIDTH),
      .KEEP_WIDTH(KEEP_WIDTH)
  ) crc_insert_inst (
      .clk(clk),
      .rst(rst),
      .crc_accum(transfer),
      .crc_init(beat_index == {COUNT_WIDTH{1'b0}}),
      .crc_data(out_data),
      .crc_keep(crc_keep),
      .client_fcs_present(fcs_present_reg),
      .supplied_fcs(supplied_fcs),
      .generated_fcs(),
      .selected_fcs(fcs_word)
  );
  assign req_ready = (state == IDLE);
  assign busy = (state != IDLE);
  always @* begin
    remaining = frame_len - (beat_index << 6);
    beat_bytes = (remaining >= 64) ? 64 : ((remaining > 0) ? remaining : 0);
    payload_emitted = (beat_index << 6) - PREAMBLE_SFD_OCTETS;
    if (payload_emitted < 0) payload_emitted = 0;
    if (payload_emitted > body_len) payload_emitted = body_len;
    payload_base = payload_emitted >> 6;
    out_valid = (state == EMIT) && (remaining > 0);
    out_sop = out_valid && (beat_index == 0);
    out_eop = out_valid && (remaining <= 64);
    out_frame_end_byte_index = out_eop ? beat_bytes : {frame_end_byte_index_W{1'b0}};
    out_keep = keep_mask(beat_bytes);
    out_error = 1'b0;
    out_data = {DATA_WIDTH{1'b0}};
    transfer = out_valid && ready;
    if (out_valid)
      for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) begin
        global_byte = (beat_index << 6) + lane;
        if (global_byte < PREAMBLE_OCTETS) out_data[lane*8+:8] = 8'h55;
        else if (global_byte < PREAMBLE_SFD_OCTETS) out_data[lane*8+:8] = 8'hd5;
        else if (global_byte < PREAMBLE_SFD_OCTETS + body_len) begin
          payload_off  = global_byte - PREAMBLE_SFD_OCTETS;
          payload_word = payload_off >> 6;
          if (payload_word == payload_base)
            out_data[lane*8+:8] = capture_read_data[(payload_off&63)*8+:8];
          else out_data[lane*8+:8] = capture_read_data_1[(payload_off&63)*8+:8];
        end else if (global_byte < frame_len - FCS_OCTETS) out_data[lane*8+:8] = 8'h00;
        else if (global_byte < frame_len) begin
          fcs_off = global_byte - (frame_len - FCS_OCTETS);
          out_data[lane*8+:8] = fcs_word[8*fcs_off+:8];
        end
      end
  end
  always @* begin
    payload_emitted = (beat_index << 6) - PREAMBLE_SFD_OCTETS;
    if (payload_emitted < 0) payload_emitted = 0;
    if (payload_emitted > body_len) payload_emitted = body_len;
    payload_base = payload_emitted >> 6;
    if (payload_base >= BUFFER_WORDS) payload_base = BUFFER_WORDS - 1;
    capture_read_addr = payload_base;
    capture_read_addr_1 = (payload_base + 1 >= BUFFER_WORDS) ? BUFFER_WORDS - 1 : payload_base + 1;
    crc_keep = {KEEP_WIDTH{1'b0}};
    for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) begin
      global_byte = (beat_index << 6) + lane;
      if ((global_byte >= 8) && (global_byte < frame_len - FCS_OCTETS)) crc_keep[lane] = 1'b1;
    end
  end
  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      fcs_present_reg <= 1'b0;
      beat_index <= {COUNT_WIDTH{1'b0}};
      frame_done <= 1'b0;
    end else begin
      frame_done <= 1'b0;
      case (state)
        IDLE:
        if (start_capture) begin
          fcs_present_reg <= client_fcs_present;
          state <= WAIT_CAPTURE;
        end
        WAIT_CAPTURE:
        if (capture_done) begin
          beat_index <= {COUNT_WIDTH{1'b0}};
          state <= EMIT;
        end
        EMIT:
        if (transfer) begin
          if (out_eop) begin
            beat_index <= {COUNT_WIDTH{1'b0}};
            state <= IDLE;
            frame_done <= 1'b1;
          end else beat_index <= beat_index + 1'b1;
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
`default_nettype wire
