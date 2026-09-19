`default_nettype none
module tx_arbiter #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire data_valid,
    output reg data_ready,
    input wire [DATA_WIDTH-1:0] data_data,
    input wire [KEEP_WIDTH-1:0] data_keep,
    input wire data_sop,
    input wire data_eop,
    input wire [frame_end_byte_index_W-1:0] data_frame_end_byte_index,
    input wire data_error,
    input wire pause_valid,
    output reg pause_ready,
    input wire [DATA_WIDTH-1:0] pause_data,
    input wire [KEEP_WIDTH-1:0] pause_keep,
    input wire pause_sop,
    input wire pause_eop,
    input wire [frame_end_byte_index_W-1:0] pause_frame_end_byte_index,
    output reg out_valid,
    input wire out_ready,
    output reg [DATA_WIDTH-1:0] out_data,
    output reg [KEEP_WIDTH-1:0] out_keep,
    output reg out_sop,
    output reg out_eop,
    output reg [frame_end_byte_index_W-1:0] out_frame_end_byte_index,
    output reg out_error,
    output wire busy,
    output wire frame_done
);
  localparam IDLE = 2'd0, DATA = 2'd1, PAUSE = 2'd2, WAIT_IPG = 2'd3;
  reg [1:0] state, state_next;
  reg select_pause, last_eop;
  wire output_transfer = out_valid && out_ready;
  assign busy = (state != IDLE);
  assign frame_done = last_eop && output_transfer;
  always @* begin
    select_pause = 1'b0;
    data_ready   = 1'b0;
    pause_ready  = 1'b0;
    state_next   = state;
    case (state)
      IDLE:
      if (data_valid) state_next = DATA;
      else if (pause_valid) begin
        select_pause = 1'b1;
        pause_ready  = out_ready;
        state_next   = (pause_eop && out_ready) ? IDLE : PAUSE;
      end
      DATA: begin
        data_ready = out_ready;
        if (data_eop && output_transfer) state_next = WAIT_IPG;
      end
      PAUSE: begin
        select_pause = 1'b1;
        pause_ready  = out_ready;
        if (pause_eop && output_transfer) state_next = IDLE;
      end
      WAIT_IPG: state_next = IDLE;
      default:  state_next = IDLE;
    endcase
  end
  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      last_eop <= 1'b0;
    end else begin
      state <= state_next;
      last_eop <= (state == DATA) && data_eop && output_transfer;
    end
  end
  always @* begin
    out_valid = 1'b0;
    out_data = {DATA_WIDTH{1'b0}};
    out_keep = {KEEP_WIDTH{1'b0}};
    out_sop = 1'b0;
    out_eop = 1'b0;
    out_frame_end_byte_index = {frame_end_byte_index_W{1'b0}};
    out_error = 1'b0;
    if (select_pause) begin
      out_valid = pause_valid;
      out_data = pause_data;
      out_keep = pause_keep;
      out_sop = pause_sop;
      out_eop = pause_eop;
      out_frame_end_byte_index = pause_frame_end_byte_index;
    end else if (state == DATA) begin
      out_valid = data_valid;
      out_data = data_data;
      out_keep = data_keep;
      out_sop = data_sop;
      out_eop = data_eop;
      out_frame_end_byte_index = data_frame_end_byte_index;
      out_error = data_error;
    end
  end
endmodule
`default_nettype wire
