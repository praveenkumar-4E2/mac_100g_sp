`default_nettype none
`include "registers/mac_reg_map.vh"
module apb_interrupt (
    input wire apb_clk,
    input wire apb_rst,
    input wire write_valid,
    input wire [15:0] write_addr,
    input wire [31:0] write_data,
    output reg [31:0] enable,
    output reg enable_write,
    output reg [6:0] clear_mask,
    output reg clear_write,
    output reg [2:0] counter_clear_mask,
    output reg counter_clear_write
);
  always @(posedge apb_clk) begin
    if (apb_rst) begin
      enable <= 32'd0;
      enable_write <= 1'b0;
      clear_mask <= 7'd0;
      clear_write <= 1'b0;
      counter_clear_mask <= 3'd0;
      counter_clear_write <= 1'b0;
    end else begin
      enable_write <= 1'b0;
      clear_write <= 1'b0;
      counter_clear_write <= 1'b0;
      if (write_valid && (write_addr == `REG_INTERRUPT_ENABLE)) begin
        enable <= write_data;
        enable_write <= 1'b1;
      end
      if (write_valid && (write_addr == `REG_INTERRUPT_STATUS)) begin
        clear_mask  <= write_data[6:0];
        clear_write <= 1'b1;
      end
      if (write_valid) begin
        case (write_addr)
          `REG_RX_INVALID_COUNT: begin
            counter_clear_mask  <= {2'b00, write_data[0]};
            counter_clear_write <= write_data[0];
          end
          `REG_RX_OVERSIZE_COUNT: begin
            counter_clear_mask  <= {1'b0, write_data[0], 1'b0};
            counter_clear_write <= write_data[0];
          end
          `REG_RX_UNSUPPORTED_COUNT: begin
            counter_clear_mask  <= {write_data[0], 2'b00};
            counter_clear_write <= write_data[0];
          end
          default: begin
          end
        endcase
      end
    end
  end
endmodule
`default_nettype wire
