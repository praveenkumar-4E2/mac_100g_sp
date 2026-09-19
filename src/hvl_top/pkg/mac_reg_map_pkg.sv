// HVL register-map package sourced from the pure-Verilog RTL definition.
`default_nettype none
package reg_map_pkg;
  // Kept value-for-value aligned with rtl_verilog/registers/mac_reg_map.vh.
  // Register offsets, kept value-for-value aligned with the Verilog RTL map.
  localparam logic [15:0] REG_VERSION = 16'h0000;
  localparam logic [15:0] REG_GLOBAL_CONTROL = 16'h0004;
  localparam logic [15:0] REG_MAC_ADDR_LOW = 16'h0008;
  localparam logic [15:0] REG_MAC_ADDR_HIGH = 16'h000c;
  localparam logic [15:0] REG_MAX_CLIENT_DATA = 16'h0010;
  localparam logic [15:0] REG_OVERSIZE_CONTROL = 16'h0014;
  localparam logic [15:0] REG_PAUSE_CONTROL = 16'h0018;
  localparam logic [15:0] REG_PAUSE_STATUS = 16'h001c;
  localparam logic [15:0] REG_RX_STATUS = 16'h0020;
  localparam logic [15:0] REG_TX_STATUS = 16'h0024;
  localparam logic [15:0] REG_INTERRUPT_ENABLE = 16'h0028;
  localparam logic [15:0] REG_INTERRUPT_STATUS = 16'h002c;
  localparam logic [15:0] REG_RX_INVALID_COUNT = 16'h0030;
  localparam logic [15:0] REG_RX_OVERSIZE_COUNT = 16'h0034;
  localparam logic [15:0] REG_RX_UNSUPPORTED_COUNT = 16'h0038;
  localparam logic [15:0] REG_PAUSE_TX_CONFIG = 16'h003c;
  localparam logic [15:0] REG_MAC_SPEED_CONFIG = 16'h0040;
  localparam logic [15:0] REG_MAX_FRAME_SIZE = 16'h0044;
  localparam logic [15:0] REG_MIN_FRAME_SIZE = 16'h0048;
  localparam logic [15:0] REG_FRAME_SIZE_STATUS = 16'h004c;
  localparam logic [15:0] REG_GROUP_BASE = 16'h0050;
  localparam logic [15:0] REG_GROUP_STRIDE = 16'h0008;
  localparam int unsigned CTRL_RX_BIT = 0, CTRL_TX_BIT = 2, CTRL_CARRIER_BIT = 3,
      CTRL_PAUSE_BIT = 4, CTRL_COLLISION_BIT = 5, CTRL_OVERSIZE_BIT = 6, CTRL_PROMISCUOUS_BIT = 7;
  localparam int unsigned INT_RX_INVALID_BIT = 0,
      INT_RX_CRC_BIT = 1, INT_RX_OVERSIZE_BIT = 2, INT_RX_UNSUPPORTED_BIT = 3,
      INT_PAUSE_ACTIVE_BIT = 4, INT_PAUSE_EXPIRED_BIT = 5, INT_TX_ERROR_BIT = 6;
  localparam int unsigned PAUSE_TX_ENABLE_BIT = 0,
      PAUSE_TX_SOFT_REQ_BIT = 1, RX_PROMISCUOUS_ACTIVE_BIT = 0, SPEED_OVERRIDE_BIT = 3;
  // Extended PAUSE-TX command bits leave all 16 quanta bits independently
  // programmable. Bits 0/1 remain supported for legacy software.
  localparam int unsigned PAUSE_TX_EXT_ENABLE_BIT = 16,
      PAUSE_TX_EXT_SOFT_REQ_BIT = 17;
  function automatic logic [15:0] group_low_addr(input int unsigned index);
    return REG_GROUP_BASE + index * REG_GROUP_STRIDE;
  endfunction
  function automatic logic [15:0] group_high_addr(input int unsigned index);
    return REG_GROUP_BASE + index * REG_GROUP_STRIDE + 16'h0004;
  endfunction
  function automatic bit is_valid_address(input logic [15:0] address, input int unsigned groups);
    int unsigned index;
    begin
      is_valid_address = (address == REG_VERSION) ||
          ((address >= REG_GLOBAL_CONTROL) && (address <= REG_RX_UNSUPPORTED_COUNT)) ||
          (address == REG_PAUSE_TX_CONFIG) || (address == REG_MAC_SPEED_CONFIG) ||
          (address == REG_MAX_FRAME_SIZE) || (address == REG_MIN_FRAME_SIZE) ||
          (address == REG_FRAME_SIZE_STATUS);
      for (index = 0; index < groups; index = index + 1)
      is_valid_address |= (address == group_low_addr(index)) || (address == group_high_addr(index));
    end
  endfunction
endpackage
`default_nettype wire
