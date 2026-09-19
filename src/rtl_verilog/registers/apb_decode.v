`default_nettype none
`include "registers/mac_reg_map.vh"
module apb_decode #(
    parameter GROUP_COUNT = 4
) (
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire [15:0] paddr,
    output reg access_valid,
    output wire read_valid,
    output wire write_valid,
    output wire status_access,
    output wire status_setup,
    output reg [GROUP_COUNT-1:0] group_low_select,
    output reg [GROUP_COUNT-1:0] group_high_select
);
  integer index;
  reg status_addr;
  function is_valid_address;
    input [15:0] address;
    integer group_index;
    begin
      is_valid_address = (address == `REG_VERSION) ||
          ((address >= `REG_GLOBAL_CONTROL) && (address <= `REG_RX_UNSUPPORTED_COUNT)) ||
          (address == `REG_PAUSE_TX_CONFIG) || (address == `REG_MAC_SPEED_CONFIG) ||
          (address == `REG_MAX_FRAME_SIZE) || (address == `REG_MIN_FRAME_SIZE) ||
          (address == `REG_FRAME_SIZE_STATUS);
      for (group_index = 0; group_index < GROUP_COUNT; group_index = group_index + 1)
      is_valid_address = is_valid_address ||
          (address == (`REG_GROUP_BASE + group_index * `REG_GROUP_STRIDE)) ||
          (address == (`REG_GROUP_BASE + group_index * `REG_GROUP_STRIDE + 16'h0004));
    end
  endfunction
  assign read_valid = psel && penable && !pwrite;
  assign write_valid = psel && penable && pwrite;
  assign status_access = read_valid && status_addr;
  assign status_setup = psel && !penable && !pwrite && status_addr;
  always @* begin
    access_valid = is_valid_address(paddr);
    status_addr = (paddr == `REG_PAUSE_STATUS) || (paddr == `REG_RX_STATUS) ||
        (paddr == `REG_TX_STATUS) || (paddr == `REG_INTERRUPT_STATUS) ||
        (paddr == `REG_RX_INVALID_COUNT) || (paddr == `REG_RX_OVERSIZE_COUNT) ||
        (paddr == `REG_RX_UNSUPPORTED_COUNT);
    group_low_select = {GROUP_COUNT{1'b0}};
    group_high_select = {GROUP_COUNT{1'b0}};
    for (index = 0; index < GROUP_COUNT; index = index + 1) begin
      group_low_select[index] = (paddr == (`REG_GROUP_BASE + index * `REG_GROUP_STRIDE));
      group_high_select[index] = (paddr ==
                                  (`REG_GROUP_BASE + index * `REG_GROUP_STRIDE + 16'h0004));
    end
  end
endmodule
`default_nettype wire
