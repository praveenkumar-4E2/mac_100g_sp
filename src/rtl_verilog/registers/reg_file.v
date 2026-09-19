`default_nettype none
`include "registers/mac_reg_map.vh"
module reg_file #(
    parameter GROUP_COUNT = 4
) (
    input wire apb_clk,
    input wire apb_rst,
    input wire write_valid,
    input wire [15:0] write_addr,
    input wire [31:0] write_data,
    output reg cfg_write,
    output reg [31:0] cfg_control,
    output reg [47:0] cfg_mac_addr,
    output reg [15:0] cfg_max_client_data,
    output reg cfg_pause_tx_enable,
    output reg cfg_pause_tx_soft_req,
    output reg [15:0] cfg_pause_quanta,
    output reg cfg_promiscuous_mode,
    output reg [2:0] cfg_mac_speed,
    output reg cfg_speed_override,
    output reg [15:0] cfg_max_frame_size,
    output reg [15:0] cfg_min_frame_size,
    output reg [GROUP_COUNT*48-1:0] cfg_group_addr,
    output reg [GROUP_COUNT-1:0] cfg_group_valid
);
  integer group_index;
  function is_valid_address;
    input [15:0] address;
    integer index;
    begin
      is_valid_address = (address == `REG_VERSION) ||
          ((address >= `REG_GLOBAL_CONTROL) && (address <= `REG_RX_UNSUPPORTED_COUNT)) ||
          (address == `REG_PAUSE_TX_CONFIG) || (address == `REG_MAC_SPEED_CONFIG) ||
          (address == `REG_MAX_FRAME_SIZE) || (address == `REG_MIN_FRAME_SIZE) ||
          (address == `REG_FRAME_SIZE_STATUS);
      for (index = 0; index < GROUP_COUNT; index = index + 1)
      is_valid_address = is_valid_address ||
          (address == (`REG_GROUP_BASE + index * `REG_GROUP_STRIDE)) ||
          (address == (`REG_GROUP_BASE + index * `REG_GROUP_STRIDE + 16'h0004));
    end
  endfunction
  always @(posedge apb_clk) begin
    if (apb_rst) begin
      cfg_write <= 1'b0;
      cfg_control <= 32'h00000040;
      cfg_mac_addr <= 48'd0;
      cfg_max_client_data <= 16'd1500;
      cfg_pause_tx_enable <= 1'b0;
      cfg_pause_tx_soft_req <= 1'b0;
      cfg_pause_quanta <= 16'd0;
      cfg_promiscuous_mode <= 1'b0;
      cfg_mac_speed <= 3'b100;
      cfg_speed_override <= 1'b0;
      cfg_max_frame_size <= 16'd1518;
      cfg_min_frame_size <= 16'd64;
      cfg_group_addr <= {GROUP_COUNT * 48{1'b0}};
      cfg_group_valid <= {GROUP_COUNT{1'b0}};
    end else begin
      cfg_write <= 1'b0;
      if (write_valid && is_valid_address(write_addr)) begin
        cfg_write <= 1'b1;
        case (write_addr)
          `REG_GLOBAL_CONTROL: cfg_control <= write_data;
          `REG_MAC_ADDR_LOW: cfg_mac_addr[31:0] <= write_data;
          `REG_MAC_ADDR_HIGH: cfg_mac_addr[47:32] <= write_data[15:0];
          `REG_MAX_CLIENT_DATA: cfg_max_client_data <= write_data[15:0];
          `REG_PAUSE_TX_CONFIG: begin
            // Legacy control aliases bits 0/1 of quanta. The extended
            // command bits preserve that ABI while allowing exact quanta.
            cfg_pause_tx_enable <= (write_data[17:16] != 2'b00) ? write_data[16] : write_data[0];
            cfg_pause_tx_soft_req <= (write_data[17:16] != 2'b00) ? write_data[17] : write_data[1];
            cfg_pause_quanta <= write_data[15:0];
          end
          `REG_MAC_SPEED_CONFIG: begin
            cfg_mac_speed <= write_data[2:0];
            cfg_speed_override <= write_data[3];
          end
          `REG_MAX_FRAME_SIZE: cfg_max_frame_size <= write_data[15:0];
          `REG_MIN_FRAME_SIZE: cfg_min_frame_size <= write_data[15:0];
          default: begin
          end
        endcase
        for (group_index = 0; group_index < GROUP_COUNT; group_index = group_index + 1) begin
          if (write_addr == (`REG_GROUP_BASE + group_index * `REG_GROUP_STRIDE))
            cfg_group_addr[group_index*48+:32] <= write_data;
          if (write_addr == (`REG_GROUP_BASE + group_index * `REG_GROUP_STRIDE + 16'h0004)) begin
            cfg_group_addr[group_index*48+32+:16] <= write_data[15:0];
            cfg_group_valid[group_index] <= write_data[16];
          end
        end
      end
    end
  end
endmodule
`default_nettype wire
