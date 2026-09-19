`default_nettype none
module control_frame_builder #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire control_req_valid,
    output wire control_req_ready,
    input wire [47:0] dest_addr,
    input wire [47:0] src_addr,
    input wire [15:0] opcode,
    input wire param_valid,
    output wire param_ready,
    input wire [7:0] param_data,
    input wire param_last,
    output wire out_valid,
    input wire out_ready,
    output reg [DATA_WIDTH-1:0] out_data,
    output reg [KEEP_WIDTH-1:0] out_keep,
    output wire out_sop,
    output wire out_eop,
    output wire [frame_end_byte_index_W-1:0] out_frame_end_byte_index,
    output wire [47:0] out_dest_addr,
    output wire [47:0] out_src_addr,
    output wire [15:0] out_length_type
);
  localparam PARAM_OCTETS = 44;
  localparam IDLE = 2'd0, COLLECT = 2'd1, EMIT = 2'd2;
  reg [1:0] state;
  reg [5:0] param_index;
  reg [7:0] param_buf[0:PARAM_OCTETS-1];
  reg [47:0] dest_addr_r, src_addr_r;
  reg [15:0] opcode_r;
  integer byte_index;
  function [KEEP_WIDTH-1:0] keep_mask;
    input integer count;
    integer lane;
    begin
      keep_mask = {KEEP_WIDTH{1'b0}};
      for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) if (lane < count) keep_mask[lane] = 1'b1;
    end
  endfunction
  assign control_req_ready = (state == IDLE);
  assign param_ready = (state == COLLECT) && (param_index < PARAM_OCTETS);
  assign out_valid = (state == EMIT);
  assign out_sop = (state == EMIT);
  assign out_eop = (state == EMIT);
  assign out_frame_end_byte_index = 60;
  assign out_dest_addr = dest_addr_r;
  assign out_src_addr = src_addr_r;
  assign out_length_type = 16'h8808;
  always @* begin
    out_data = {DATA_WIDTH{1'b0}};
    out_keep = keep_mask(60);
    for (byte_index = 0; byte_index < KEEP_WIDTH; byte_index = byte_index + 1) begin
      if (byte_index < 6) out_data[8*byte_index+:8] = dest_addr_r[47-8*byte_index-:8];
      else if (byte_index < 12) out_data[8*byte_index+:8] = src_addr_r[47-8*(byte_index-6)-:8];
      else if (byte_index < 14) out_data[8*byte_index+:8] = (byte_index == 12) ? 8'h88 : 8'h08;
      else if (byte_index < 16) out_data[8*byte_index+:8] = opcode_r[15-8*(byte_index-14)-:8];
      else if (byte_index < 60) out_data[8*byte_index+:8] = param_buf[byte_index-16];
    end
  end
  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      param_index <= 6'd0;
      dest_addr_r <= 48'd0;
      src_addr_r <= 48'd0;
      opcode_r <= 16'd0;
    end else begin
      case (state)
        IDLE:
        if (control_req_valid) begin
          state <= COLLECT;
          param_index <= 6'd0;
          dest_addr_r <= dest_addr;
          src_addr_r <= src_addr;
          opcode_r <= opcode;
        end
        COLLECT:
        if (param_valid && param_ready) begin
          param_buf[param_index] <= param_data;
          param_index <= param_index + 1'b1;
          if (param_last || (param_index == PARAM_OCTETS - 1)) state <= EMIT;
        end
        EMIT: if (out_valid && out_ready) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end
endmodule
`default_nettype wire
