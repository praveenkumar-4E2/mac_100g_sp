`default_nettype none
`include "registers/mac_reg_map.vh"
module apb_regs #(
    parameter GROUP_COUNT = 4
) (
    input wire apb_clk,
    input wire apb_rst,
    input wire mac_clk,
    input wire mac_rst,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire [15:0] paddr,
    input wire [31:0] pwdata,
    output reg [31:0] prdata,
    output reg pready,
    output reg pslverr,
    input wire rx_invalid_event,
    input wire rx_crc_event,
    input wire rx_oversize_event,
    input wire rx_unsupported_control_event,
    input wire pause_active,
    input wire pause_expired,
    input wire tx_error_event,
    output wire cfg_update,
    output wire [31:0] cfg_control,
    output wire [47:0] cfg_mac_addr,
    output wire [15:0] cfg_max_client_data,
    output wire cfg_pause_tx_enable,
    output wire cfg_pause_tx_soft_req,
    output wire [15:0] cfg_pause_quanta,
    output wire [15:0] cfg_max_frame_size,
    output wire [15:0] cfg_min_frame_size,
    output wire [2:0] cfg_mac_speed,
    output wire cfg_speed_override,
    input wire [2:0] effective_mac_speed,
    output wire [GROUP_COUNT*48-1:0] cfg_group_addr,
    output wire [GROUP_COUNT-1:0] cfg_group_valid,
    output reg status_request,
    output reg status_ack,
    output wire [383:0] status_snapshot
);
  wire access_valid, read_valid, write_valid, status_access, status_setup;
  wire [GROUP_COUNT-1:0] group_low_select, group_high_select;
  wire [31:0] cfg_control_apb, irq_enable;
  wire [47:0] cfg_mac_addr_apb;
  wire [15:0] cfg_max_client_data_apb, cfg_max_frame_size_apb, cfg_min_frame_size_apb;
  wire [2:0] cfg_mac_speed_apb, cfg_effective_speed_apb;
  wire cfg_speed_override_apb, cfg_pause_tx_enable_apb, cfg_pause_tx_soft_req_apb;
  wire [15:0] cfg_pause_quanta_apb;
  wire [GROUP_COUNT*48-1:0] cfg_group_addr_apb;
  wire [GROUP_COUNT-1:0] cfg_group_valid_apb;
  wire irq_enable_write, irq_clear_write, counter_clear_write, irq_enable_ready, irq_clear_ready,
      counter_clear_ready;
  wire [6:0] irq_clear_mask;
  wire [2:0] counter_clear_mask;
  wire irq_enable_valid, irq_clear_valid, counter_clear_valid;
  wire [31:0] irq_enable_mac;
  wire [6:0] irq_clear_mask_mac;
  wire [2:0] counter_clear_mask_mac;
  wire status_ack_apb;
  wire [383:0] status_snapshot_mac;
  wire pause_active_apb;
  reg command_ready;
  integer group_index;
  apb_decode #(
      .GROUP_COUNT(GROUP_COUNT)
  ) decode_inst (
      .psel(psel),
      .penable(penable),
      .pwrite(pwrite),
      .paddr(paddr),
      .access_valid(access_valid),
      .read_valid(read_valid),
      .write_valid(write_valid),
      .status_access(status_access),
      .status_setup(status_setup),
      .group_low_select(group_low_select),
      .group_high_select(group_high_select)
  );
  apb_cfg_bridge #(
      .GROUP_COUNT(GROUP_COUNT)
  ) cfg_inst (
      .apb_clk(apb_clk),
      .apb_rst(apb_rst),
      .write_valid(write_valid),
      .write_addr(paddr),
      .write_data(pwdata),
      .mac_clk(mac_clk),
      .mac_rst(mac_rst),
      .cfg_update(cfg_update),
      .cfg_control(cfg_control),
      .cfg_mac_addr(cfg_mac_addr),
      .cfg_max_client_data(cfg_max_client_data),
      .cfg_max_frame_size(cfg_max_frame_size),
      .cfg_min_frame_size(cfg_min_frame_size),
      .cfg_group_addr(cfg_group_addr),
      .cfg_group_valid(cfg_group_valid),
      .cfg_control_apb(cfg_control_apb),
      .cfg_mac_addr_apb(cfg_mac_addr_apb),
      .cfg_max_client_data_apb(cfg_max_client_data_apb),
      .cfg_max_frame_size_apb(cfg_max_frame_size_apb),
      .cfg_min_frame_size_apb(cfg_min_frame_size_apb),
      .cfg_group_addr_apb(cfg_group_addr_apb),
      .cfg_group_valid_apb(cfg_group_valid_apb),
      .cfg_pause_tx_enable_apb(cfg_pause_tx_enable_apb),
      .cfg_pause_tx_soft_req_apb(cfg_pause_tx_soft_req_apb),
      .cfg_pause_quanta_apb(cfg_pause_quanta_apb),
      .cfg_mac_speed(cfg_mac_speed),
      .cfg_speed_override(cfg_speed_override),
      .cfg_mac_speed_apb(cfg_mac_speed_apb),
      .cfg_speed_override_apb(cfg_speed_override_apb),
      .cfg_pause_tx_enable(cfg_pause_tx_enable),
      .cfg_pause_tx_soft_req(cfg_pause_tx_soft_req),
      .cfg_pause_quanta(cfg_pause_quanta)
  );
  apb_interrupt irq_inst (
      .apb_clk(apb_clk),
      .apb_rst(apb_rst),
      .write_valid(write_valid),
      .write_addr(paddr),
      .write_data(pwdata),
      .enable(irq_enable),
      .enable_write(irq_enable_write),
      .clear_mask(irq_clear_mask),
      .clear_write(irq_clear_write),
      .counter_clear_mask(counter_clear_mask),
      .counter_clear_write(counter_clear_write)
  );
  cdc_handshake #(
      .WIDTH(32)
  ) irq_enable_cdc (
      .clk_src  (apb_clk),
      .rst_src  (apb_rst),
      .req_src  (irq_enable_write),
      .data_src (irq_enable),
      .ready_src(irq_enable_ready),
      .clk_dst  (mac_clk),
      .rst_dst  (mac_rst),
      .valid_dst(irq_enable_valid),
      .data_dst (irq_enable_mac),
      .ack_dst  (irq_enable_valid)
  );
  cdc_handshake #(
      .WIDTH(7)
  ) irq_clear_cdc (
      .clk_src  (apb_clk),
      .rst_src  (apb_rst),
      .req_src  (irq_clear_write),
      .data_src (irq_clear_mask),
      .ready_src(irq_clear_ready),
      .clk_dst  (mac_clk),
      .rst_dst  (mac_rst),
      .valid_dst(irq_clear_valid),
      .data_dst (irq_clear_mask_mac),
      .ack_dst  (irq_clear_valid)
  );
  cdc_handshake #(
      .WIDTH(3)
  ) counter_clear_cdc (
      .clk_src  (apb_clk),
      .rst_src  (apb_rst),
      .req_src  (counter_clear_write),
      .data_src (counter_clear_mask),
      .ready_src(counter_clear_ready),
      .clk_dst  (mac_clk),
      .rst_dst  (mac_rst),
      .valid_dst(counter_clear_valid),
      .data_dst (counter_clear_mask_mac),
      .ack_dst  (counter_clear_valid)
  );
  mac_stats stats_inst (
      .mac_clk(mac_clk),
      .mac_rst(mac_rst),
      .rx_invalid_event(rx_invalid_event),
      .rx_crc_event(rx_crc_event),
      .rx_oversize_event(rx_oversize_event),
      .rx_unsupported_control_event(rx_unsupported_control_event),
      .pause_active(pause_active),
      .pause_expired(pause_expired),
      .tx_error_event(tx_error_event),
      .irq_enable_update(irq_enable_valid),
      .interrupt_enable_mac(irq_enable_mac),
      .irq_clear(irq_clear_valid),
      .irq_clear_mask(irq_clear_mask_mac),
      .counter_clear(counter_clear_valid),
      .counter_clear_mask(counter_clear_mask_mac),
      .status_snapshot_mac(status_snapshot_mac)
  );
  stats_cdc_bridge #(
      .WIDTH(384)
  ) stats_bridge_inst (
      .apb_clk(apb_clk),
      .apb_rst(apb_rst),
      .mac_clk(mac_clk),
      .mac_rst(mac_rst),
      .request_apb(status_request),
      .snapshot_mac(status_snapshot_mac),
      .ack_apb(status_ack_apb),
      .snapshot_apb(status_snapshot)
  );
  cdc_2ff speed_sync0 (
      .clk_dst(apb_clk),
      .rst_dst(apb_rst),
      .signal_src(effective_mac_speed[0]),
      .signal_dst(cfg_effective_speed_apb[0])
  );
  cdc_2ff speed_sync1 (
      .clk_dst(apb_clk),
      .rst_dst(apb_rst),
      .signal_src(effective_mac_speed[1]),
      .signal_dst(cfg_effective_speed_apb[1])
  );
  cdc_2ff speed_sync2 (
      .clk_dst(apb_clk),
      .rst_dst(apb_rst),
      .signal_src(effective_mac_speed[2]),
      .signal_dst(cfg_effective_speed_apb[2])
  );
  cdc_2ff pause_active_sync (
      .clk_dst(apb_clk),
      .rst_dst(apb_rst),
      .signal_src(pause_active),
      .signal_dst(pause_active_apb)
  );
  always @* begin
    command_ready = 1'b1;
    if (paddr == `REG_INTERRUPT_ENABLE) command_ready = irq_enable_ready;
    if (paddr == `REG_INTERRUPT_STATUS) command_ready = irq_clear_ready;
    if ((paddr == `REG_RX_INVALID_COUNT) || (paddr == `REG_RX_OVERSIZE_COUNT) ||
        (paddr == `REG_RX_UNSUPPORTED_COUNT))
      command_ready = counter_clear_ready;
    // A status read toggles the snapshot request in APB setup.  Hold its
    // access phase until the MAC-domain snapshot has returned, so the read
    // itself returns current status rather than the prior snapshot.
    if (status_access) command_ready = (status_ack == status_request);
    pready = psel && penable && command_ready;
    pslverr = psel && penable && !access_valid;
    prdata = 32'd0;
    case (paddr)
      `REG_VERSION: prdata = 32'h41504231;
      `REG_GLOBAL_CONTROL: prdata = cfg_control_apb;
      `REG_MAC_ADDR_LOW: prdata = cfg_mac_addr_apb[31:0];
      `REG_MAC_ADDR_HIGH: prdata = {16'd0, cfg_mac_addr_apb[47:32]};
      `REG_MAX_CLIENT_DATA: prdata = {16'd0, cfg_max_client_data_apb};
      `REG_MAX_FRAME_SIZE: prdata = {16'd0, cfg_max_frame_size_apb};
      `REG_MIN_FRAME_SIZE: prdata = {16'd0, cfg_min_frame_size_apb};
      `REG_MAC_SPEED_CONFIG:
      prdata = {25'd0, cfg_effective_speed_apb, cfg_speed_override_apb, cfg_mac_speed_apb};
      `REG_PAUSE_TX_CONFIG: prdata = {16'd0, cfg_pause_quanta_apb};
      `REG_OVERSIZE_CONTROL: prdata = cfg_control_apb & 32'h40;
      `REG_PAUSE_CONTROL: prdata = cfg_control_apb & 32'h30;
      `REG_PAUSE_STATUS: prdata = status_snapshot[191:160];
      `REG_RX_STATUS: prdata = {31'd0, pause_active_apb};
      `REG_TX_STATUS: prdata = status_snapshot[223:192];
      `REG_INTERRUPT_ENABLE: prdata = irq_enable;
      `REG_INTERRUPT_STATUS: prdata = status_snapshot[127:96];
      `REG_RX_INVALID_COUNT: prdata = status_snapshot[31:0];
      `REG_RX_OVERSIZE_COUNT: prdata = status_snapshot[63:32];
      `REG_RX_UNSUPPORTED_COUNT: prdata = status_snapshot[95:64];
      default: begin
      end
    endcase
    for (group_index = 0; group_index < GROUP_COUNT; group_index = group_index + 1) begin
      if (group_low_select[group_index]) prdata = cfg_group_addr_apb[group_index*48+:32];
      if (group_high_select[group_index])
        prdata = {
          15'd0, cfg_group_valid_apb[group_index], cfg_group_addr_apb[group_index*48+32+:16]
        };
    end
  end
  always @(posedge apb_clk) begin
    if (apb_rst) begin
      status_request <= 1'b0;
      status_ack <= 1'b0;
    end else begin
      if (status_setup && (status_ack_apb == status_request)) status_request <= ~status_request;
      status_ack <= status_ack_apb;
    end
  end
endmodule
`default_nettype wire
