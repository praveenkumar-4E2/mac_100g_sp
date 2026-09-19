`default_nettype none
module address_filter #(
    parameter GROUP_TABLE_SIZE = 4
) (
    input wire [47:0] local_addr,
    input wire [47:0] dest_addr,
    input wire promiscuous_en,
    input wire pause_en,
    input wire [GROUP_TABLE_SIZE*48-1:0] group_addrs,
    input wire [GROUP_TABLE_SIZE-1:0] group_valid,
    output reg accept
);
  integer group_index;
  always @* begin
    accept = promiscuous_en || (dest_addr == 48'hffffffffffff) || (dest_addr == local_addr) ||
        (pause_en && (dest_addr == 48'h0180c2000001));
    for (group_index = 0; group_index < GROUP_TABLE_SIZE; group_index = group_index + 1)
    if (group_valid[group_index] && (dest_addr == group_addrs[group_index*48+:48])) accept = 1'b1;
  end
endmodule
`default_nettype wire
