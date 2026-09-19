`default_nettype none
module pause_tx #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire pause_tx_enable,
    input wire data_pause_active,
    input wire pause_req_valid,
    output wire pause_req_ready,
    input wire [47:0] source_addr,
    input wire [15:0] pause_time,
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
  reg active, beat_index;
  reg [47:0] source_addr_reg;
  reg [15:0] pause_time_reg;
  reg [31:0] pause_fcs;
  integer byte_index, wire_index;
  function [KEEP_WIDTH-1:0] keep_mask;
    input integer n;
    integer lane;
    begin
      keep_mask = {KEEP_WIDTH{1'b0}};
      for (lane = 0; lane < KEEP_WIDTH; lane = lane + 1) if (lane < n) keep_mask[lane] = 1'b1;
    end
  endfunction
  function [7:0] pause_body_byte;
    input integer index;
    begin
      if (index < 6) begin
        case (index)
          0: pause_body_byte = 8'h01;
          1: pause_body_byte = 8'h80;
          2: pause_body_byte = 8'hc2;
          3: pause_body_byte = 8'h00;
          4: pause_body_byte = 8'h00;
          default: pause_body_byte = 8'h01;
        endcase
      end else if (index < 12) pause_body_byte = source_addr_reg[47-8*(index-6)-:8];
      else if (index < 14) pause_body_byte = (index == 12) ? 8'h88 : 8'h08;
      else if (index < 16) pause_body_byte = (index == 14) ? 8'h00 : 8'h01;
      // Keep the PAUSE time byte selection explicit.  This avoids a
      // variable indexed part-select in the frame-data path and guarantees
      // that the low quanta byte appears on the wire after the opcode.
      else if (index == 16) pause_body_byte = pause_time_reg[15:8];
      else if (index == 17) pause_body_byte = pause_time_reg[7:0];
      else pause_body_byte = 8'h00;
    end
  endfunction
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
  assign pause_req_ready = pause_tx_enable && !active;
  assign out_valid = active;
  assign out_sop = active && !beat_index;
  assign out_eop = active && beat_index;
  assign out_frame_end_byte_index = beat_index ? 8 : {frame_end_byte_index_W{1'b0}};
  assign out_dest_addr = 48'h0180c2000001;
  assign out_src_addr = source_addr_reg;
  assign out_length_type = 16'h8808;
  always @* begin
    pause_fcs = 32'hFFFFFFFF;
    for (byte_index = 0; byte_index < 60; byte_index = byte_index + 1)
    pause_fcs = update_byte(pause_fcs, pause_body_byte(byte_index));
    pause_fcs = ~pause_fcs;
    out_data  = {DATA_WIDTH{1'b0}};
    out_keep  = keep_mask(beat_index ? 8 : KEEP_WIDTH);
    for (byte_index = 0; byte_index < KEEP_WIDTH; byte_index = byte_index + 1) begin
      wire_index = (beat_index ? KEEP_WIDTH : 0) + byte_index;
      if (wire_index < 7) out_data[8*byte_index+:8] = 8'h55;
      else if (wire_index == 7) out_data[8*byte_index+:8] = 8'hd5;
      else if (wire_index < 68) out_data[8*byte_index+:8] = pause_body_byte(wire_index - 8);
      else if (wire_index < 72) out_data[8*byte_index+:8] = pause_fcs[8*(wire_index-68)+:8];
    end
    // PAUSE quanta occupies body bytes 16 and 17, which are lanes 24 and
    // 25 of the first RS beat after the preamble/SFD and Ethernet header.
    // Drive these protocol fields directly at their wire lanes.
    if (!beat_index) begin
      out_data[8*24+:8] = pause_time_reg[15:8];
      out_data[8*25+:8] = pause_time_reg[7:0];
    end
  end
  always @(posedge clk) begin
    if (rst) begin
      active <= 1'b0;
      beat_index <= 1'b0;
      source_addr_reg <= 48'd0;
      pause_time_reg <= 16'd0;
    end else if (!active && pause_req_valid && pause_req_ready) begin
      active <= 1'b1;
      beat_index <= 1'b0;
      source_addr_reg <= source_addr;
      pause_time_reg <= pause_time;
    end else if (out_valid && out_ready) begin
      if (beat_index) active <= 1'b0;
      else beat_index <= 1'b1;
    end
  end
endmodule
`default_nettype wire
