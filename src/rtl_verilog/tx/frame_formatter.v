`default_nettype none
`include "mac_params.vh"
module frame_formatter #(
    parameter BUFFER_BYTES = `MAC_TX_BUFFER_BYTES
) (
    input wire clk,
    input wire rst,
    input wire start,
    output wire req_ready,
    input wire ready,
    input wire [47:0] dest_addr,
    input wire [47:0] src_addr,
    input wire [15:0] length_type,
    input wire client_valid,
    output wire client_ready,
    input wire [7:0] client_data,
    input wire client_last,
    input wire client_fcs_present,
    output reg out_valid,
    output reg [7:0] out_data,
    output reg out_sop,
    output reg out_eop,
    output reg out_error,
    output wire busy,
    output reg frame_done
);
  localparam IDLE = 4'd0, CAPTURE = 4'd1, PREAMBLE = 4'd2, SFD = 4'd3, DA = 4'd4, SA = 4'd5,
      LT = 4'd6, DATA = 4'd7, PAD = 4'd8, FCS = 4'd9;
  reg [3:0] state;
  reg [7:0] frame_buffer[0:BUFFER_BYTES-1];
  reg [47:0] da_reg, sa_reg;
  reg [15:0] lt_reg;
  reg fcs_present_reg;
  reg [15:0] client_count, payload_len, out_index, pad_count;
  wire transfer = out_valid && ready;
  wire crc_init = (state == LT) && transfer && (out_index == 1);
  wire crc_valid = transfer && ((state == DA) || (state == SA) || (state == LT) ||
                                (state == DATA) || (state == PAD)) && !crc_init;
  wire [31:0] generated_fcs;
  wire [15:0] fcs_mem_index = payload_len + out_index;
  crc32_tx crc32_tx_inst (
      .clk(clk),
      .rst(rst),
      .init(crc_init),
      .data_valid(crc_valid),
      .data(out_data),
      .crc_out(generated_fcs)
  );
  assign req_ready = (state == IDLE);
  assign busy = (state != IDLE);
  assign client_ready = (state == CAPTURE) && (client_count < BUFFER_BYTES);
  always @* begin
    out_valid = 1'b0;
    out_data  = 8'd0;
    out_sop   = 1'b0;
    out_eop   = 1'b0;
    out_error = 1'b0;
    case (state)
      PREAMBLE: begin
        out_valid = 1'b1;
        out_data  = 8'haa;
        out_sop   = (out_index == 0);
      end
      SFD: begin
        out_valid = 1'b1;
        out_data  = 8'hd5;
      end
      DA: begin
        out_valid = 1'b1;
        out_data  = da_reg[47-8*out_index-:8];
      end
      SA: begin
        out_valid = 1'b1;
        out_data  = sa_reg[47-8*out_index-:8];
      end
      LT: begin
        out_valid = 1'b1;
        out_data  = lt_reg[15-8*out_index-:8];
      end
      DATA: begin
        out_valid = 1'b1;
        out_data  = frame_buffer[out_index];
      end
      PAD: begin
        out_valid = 1'b1;
        out_data  = 8'd0;
      end
      FCS: begin
        out_valid = 1'b1;
        out_data = fcs_present_reg ? frame_buffer[fcs_mem_index] : generated_fcs[31-8*out_index-:8];
        out_eop = (out_index == 3);
      end
      default: begin
      end
    endcase
  end
  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      da_reg <= 48'd0;
      sa_reg <= 48'd0;
      lt_reg <= 16'd0;
      fcs_present_reg <= 1'b0;
      client_count <= 16'd0;
      payload_len <= 16'd0;
      out_index <= 16'd0;
      pad_count <= 16'd0;
      frame_done <= 1'b0;
    end else begin
      frame_done <= 1'b0;
      case (state)
        IDLE:
        if (start) begin
          da_reg <= dest_addr;
          sa_reg <= src_addr;
          lt_reg <= length_type;
          fcs_present_reg <= client_fcs_present;
          client_count <= 16'd0;
          state <= CAPTURE;
        end
        CAPTURE:
        if (client_valid && client_ready) begin
          frame_buffer[client_count] <= client_data;
          if (client_last) begin
            if (fcs_present_reg) begin
              payload_len <= (client_count + 1 >= 4) ? client_count + 1 - 4 : 16'd0;
              pad_count   <= 16'd0;
            end else begin
              payload_len <= client_count + 1;
              pad_count   <= (client_count + 1 < 46) ? 46 - (client_count + 1) : 16'd0;
            end
            out_index <= 16'd0;
            state <= PREAMBLE;
          end else client_count <= client_count + 1'b1;
        end
        PREAMBLE:
        if (transfer)
          if (out_index == 6) begin
            out_index <= 16'd0;
            state <= SFD;
          end else out_index <= out_index + 1'b1;
        SFD:
        if (transfer) begin
          out_index <= 16'd0;
          state <= DA;
        end
        DA:
        if (transfer)
          if (out_index == 5) begin
            out_index <= 16'd0;
            state <= SA;
          end else out_index <= out_index + 1'b1;
        SA:
        if (transfer)
          if (out_index == 5) begin
            out_index <= 16'd0;
            state <= LT;
          end else out_index <= out_index + 1'b1;
        LT:
        if (transfer)
          if (out_index == 1) begin
            out_index <= 16'd0;
            state <= (payload_len == 0) ? FCS : DATA;
          end else out_index <= out_index + 1'b1;
        DATA:
        if (transfer)
          if (out_index == payload_len - 1) begin
            out_index <= 16'd0;
            state <= (pad_count != 0) ? PAD : FCS;
          end else out_index <= out_index + 1'b1;
        PAD:
        if (transfer)
          if (out_index == pad_count - 1) begin
            out_index <= 16'd0;
            state <= FCS;
          end else out_index <= out_index + 1'b1;
        FCS:
        if (transfer)
          if (out_index == 3) begin
            state <= IDLE;
            out_index <= 16'd0;
            frame_done <= 1'b1;
          end else out_index <= out_index + 1'b1;
        default: state <= IDLE;
      endcase
    end
  end
endmodule
`default_nettype wire
