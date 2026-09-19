`default_nettype none
module mac_control_top #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire frame_valid,
    input wire frame_error,
    input wire [47:0] dest_addr,
    input wire [47:0] src_addr,
    input wire [15:0] length_type,
    input wire [47:0] local_addr,
    input wire payload_valid,
    output wire payload_ready,
    input wire [DATA_WIDTH-1:0] payload_data,
    input wire [KEEP_WIDTH-1:0] payload_keep,
    input wire payload_sop,
    input wire payload_eop,
    input wire [frame_end_byte_index_W-1:0] payload_frame_end_byte_index,
    output wire client_valid,
    input wire client_ready,
    output wire [DATA_WIDTH-1:0] client_data,
    output wire [KEEP_WIDTH-1:0] client_keep,
    output wire client_sop,
    output wire client_eop,
    output wire [frame_end_byte_index_W-1:0] client_frame_end_byte_index,
    output reg control_event_valid,
    output reg [15:0] control_opcode,
    output wire [47:0] control_dest_addr,
    output wire [47:0] control_src_addr,
    output reg control_param_valid,
    output reg [DATA_WIDTH-1:0] control_param_data,
    output reg control_param_eop,
    output reg unsupported_control,
    output reg [15:0] pause_time
);
  localparam [47:0] MAC_CONTROL_DEST_ADDR = 48'h0180c2000001;
  wire is_control, is_control_frame;
  wire payload_beat = payload_valid && payload_ready;
  function [frame_end_byte_index_W-1:0] beat_bytes;
    input eop;
    input [frame_end_byte_index_W-1:0] frame_end_byte_index;
    begin
      beat_bytes = eop ? frame_end_byte_index : KEEP_WIDTH;
    end
  endfunction
  control_classifier classifier_inst (
      .length_type(length_type),
      .is_control (is_control)
  );
  // IEEE PAUSE control frames may be addressed either to the reserved
  // MAC-control multicast address or to this station's individual address.
  // Classifying only the multicast form leaks station-addressed PAUSE frames
  // to the normal client path and prevents pause_rx from seeing the event.
  assign is_control_frame = is_control &&
                            ((dest_addr == MAC_CONTROL_DEST_ADDR) ||
                             (dest_addr == local_addr));
  // The RX emitter owns payload lifetime.  frame_valid is only the one-cycle
  // decision indication and must not gate a later payload handshake.
  assign payload_ready = !frame_error && (is_control_frame || client_ready);
  assign client_valid = payload_valid && !frame_error && !is_control_frame;
  assign client_data = payload_data;
  assign client_keep = payload_keep;
  assign client_sop = client_valid && payload_sop;
  assign client_eop = client_valid && payload_eop;
  assign client_frame_end_byte_index = payload_frame_end_byte_index;
  assign control_dest_addr = dest_addr;
  assign control_src_addr = src_addr;
  always @(posedge clk) begin
    if (rst) begin
      control_event_valid <= 1'b0;
      control_opcode <= 16'd0;
      control_param_valid <= 1'b0;
      control_param_data <= {DATA_WIDTH{1'b0}};
      control_param_eop <= 1'b0;
      unsupported_control <= 1'b0;
      pause_time <= 16'd0;
    end else begin
      control_event_valid <= 1'b0;
      control_param_valid <= 1'b0;
      control_param_eop   <= 1'b0;
      unsupported_control <= 1'b0;
      if (payload_beat && is_control_frame) begin
        if (payload_sop) begin
          control_opcode <= {payload_data[119:112], payload_data[127:120]};
          if (beat_bytes(payload_eop, payload_frame_end_byte_index) >= 4) begin
            pause_time <= {payload_data[135:128], payload_data[143:136]};
            control_event_valid <= ({payload_data[119:112], payload_data[127:120]} == 16'h0001);
            if ({payload_data[119:112], payload_data[127:120]} != 16'h0001)
              unsupported_control <= 1'b1;
          end
          control_param_valid <= 1'b1;
          control_param_data  <= payload_data;
          control_param_eop   <= payload_eop;
        end else begin
          control_param_valid <= 1'b1;
          control_param_data  <= payload_data;
          control_param_eop   <= payload_eop;
        end
      end
    end
  end
endmodule
`default_nettype wire
