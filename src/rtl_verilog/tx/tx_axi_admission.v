`default_nettype none
module tx_axi_admission #(
    parameter DATA_WIDTH = 512,
    parameter KEEP_WIDTH = DATA_WIDTH / 8,
    parameter frame_end_byte_index_W = $clog2(KEEP_WIDTH + 1)
) (
    input wire clk,
    input wire rst,
    input wire s_valid,
    input wire [DATA_WIDTH-1:0] s_data,
    input wire [KEEP_WIDTH-1:0] s_keep,
    input wire s_sop,
    input wire s_eop,
    input wire [frame_end_byte_index_W-1:0] s_frame_end_byte_index,
    input wire s_error,
    input wire s_fcs_present,
    output wire s_ready,
    output wire c_valid,
    output wire [DATA_WIDTH-1:0] c_data,
    output wire [KEEP_WIDTH-1:0] c_keep,
    output wire c_sop,
    output wire c_eop,
    output wire [frame_end_byte_index_W-1:0] c_frame_end_byte_index,
    output wire c_error,
    output wire c_fcs_present,
    input wire c_ready,
    input wire tx_enabled,
    input wire pause_admit,
    input wire pipeline_req_ready,
    input wire [47:0] dest_addr,
    input wire [47:0] src_addr,
    input wire [15:0] length_type,
    output wire start_capture,
    output wire frame_active
);
  reg frame_active_q;
  reg [47:0] meta_dest_q, meta_src_q;
  reg [15:0] meta_length_type_q;
  wire first_beat_ok = tx_enabled && pause_admit && pipeline_req_ready;
  wire admit = s_valid && !frame_active_q && first_beat_ok;
  assign start_capture = admit;
  assign s_ready = frame_active_q ? c_ready : 1'b0;
  assign c_valid = s_valid && s_ready;
  assign c_data = s_data;
  assign c_keep = s_keep;
  assign c_sop = s_sop;
  assign c_eop = s_eop;
  assign c_frame_end_byte_index = s_frame_end_byte_index;
  assign c_error = s_error;
  assign c_fcs_present = s_fcs_present;
  always @(posedge clk) begin
    if (rst) begin
      frame_active_q <= 1'b0;
      meta_dest_q <= 48'd0;
      meta_src_q <= 48'd0;
      meta_length_type_q <= 16'd0;
    end else if (frame_active_q && s_valid && s_ready && s_eop) frame_active_q <= 1'b0;
    else if (admit) begin
      frame_active_q <= 1'b1;
      meta_dest_q <= dest_addr;
      meta_src_q <= src_addr;
      meta_length_type_q <= length_type;
    end
  end
  assign frame_active = frame_active_q;
endmodule
`default_nettype wire
