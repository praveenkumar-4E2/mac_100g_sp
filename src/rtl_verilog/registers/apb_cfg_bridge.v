`default_nettype none
module apb_cfg_bridge #(
    parameter GROUP_COUNT = 4,
    parameter WIDTH = 150 + 49 * GROUP_COUNT
) (
    input wire apb_clk,
    input wire apb_rst,
    input wire write_valid,
    input wire [15:0] write_addr,
    input wire [31:0] write_data,
    input wire mac_clk,
    input wire mac_rst,
    output reg cfg_update,
    output reg [31:0] cfg_control,
    output reg [47:0] cfg_mac_addr,
    output reg [15:0] cfg_max_client_data,
    output reg [15:0] cfg_max_frame_size,
    output reg [15:0] cfg_min_frame_size,
    output reg [GROUP_COUNT*48-1:0] cfg_group_addr,
    output reg [GROUP_COUNT-1:0] cfg_group_valid,
    output wire [15:0] cfg_max_frame_size_apb,
    output wire [15:0] cfg_min_frame_size_apb,
    output wire [31:0] cfg_control_apb,
    output wire [47:0] cfg_mac_addr_apb,
    output wire [15:0] cfg_max_client_data_apb,
    output wire [GROUP_COUNT*48-1:0] cfg_group_addr_apb,
    output wire [GROUP_COUNT-1:0] cfg_group_valid_apb,
    output wire cfg_pause_tx_enable_apb,
    output wire cfg_pause_tx_soft_req_apb,
    output wire [15:0] cfg_pause_quanta_apb,
    output reg cfg_pause_tx_enable,
    output reg cfg_pause_tx_soft_req,
    output reg [15:0] cfg_pause_quanta,
    output reg [2:0] cfg_mac_speed,
    output reg cfg_speed_override,
    output wire [2:0] cfg_mac_speed_apb,
    output wire cfg_speed_override_apb
);
  wire write_pulse, ready, valid;
  reg pending, send;
  wire [WIDTH-1:0] bundle, bundle_dst;
  wire cfg_promiscuous_unused;
  reg_file #(
      .GROUP_COUNT(GROUP_COUNT)
  ) reg_file_inst (
      .apb_clk(apb_clk),
      .apb_rst(apb_rst),
      .write_valid(write_valid),
      .write_addr(write_addr),
      .write_data(write_data),
      .cfg_write(write_pulse),
      .cfg_control(cfg_control_apb),
      .cfg_mac_addr(cfg_mac_addr_apb),
      .cfg_max_client_data(cfg_max_client_data_apb),
      .cfg_pause_tx_enable(cfg_pause_tx_enable_apb),
      .cfg_pause_tx_soft_req(cfg_pause_tx_soft_req_apb),
      .cfg_pause_quanta(cfg_pause_quanta_apb),
      .cfg_promiscuous_mode(cfg_promiscuous_unused),
      .cfg_mac_speed(cfg_mac_speed_apb),
      .cfg_speed_override(cfg_speed_override_apb),
      .cfg_max_frame_size(cfg_max_frame_size_apb),
      .cfg_min_frame_size(cfg_min_frame_size_apb),
      .cfg_group_addr(cfg_group_addr_apb),
      .cfg_group_valid(cfg_group_valid_apb)
  );
  assign bundle = {
    cfg_mac_speed_apb,
    cfg_speed_override_apb,
    cfg_pause_quanta_apb,
    cfg_pause_tx_soft_req_apb,
    cfg_pause_tx_enable_apb,
    cfg_group_valid_apb,
    cfg_group_addr_apb,
    cfg_min_frame_size_apb,
    cfg_max_frame_size_apb,
    cfg_max_client_data_apb,
    cfg_mac_addr_apb,
    cfg_control_apb
  };
  always @(posedge apb_clk) begin
    if (apb_rst) begin
      pending <= 1'b0;
      send <= 1'b0;
    end else begin
      send <= 1'b0;
      if (write_pulse) pending <= 1'b1;
      if (pending && ready) begin
        send <= 1'b1;
        pending <= 1'b0;
      end
    end
  end
  cdc_handshake #(
      .WIDTH(WIDTH)
  ) config_cdc_inst (
      .clk_src  (apb_clk),
      .rst_src  (apb_rst),
      .req_src  (send),
      .data_src (bundle),
      .ready_src(ready),
      .clk_dst  (mac_clk),
      .rst_dst  (mac_rst),
      .valid_dst(valid),
      .data_dst (bundle_dst),
      .ack_dst  (valid)
  );
  always @(posedge mac_clk) begin
    if (mac_rst) begin
      cfg_update <= 1'b0;
      cfg_control <= 32'h40;
      cfg_mac_addr <= 48'd0;
      cfg_max_client_data <= 16'd1500;
      cfg_max_frame_size <= 16'd1518;
      cfg_min_frame_size <= 16'd64;
      cfg_pause_tx_enable <= 1'b0;
      cfg_pause_tx_soft_req <= 1'b0;
      cfg_pause_quanta <= 16'd0;
      cfg_mac_speed <= 3'b100;
      cfg_speed_override <= 1'b0;
      cfg_group_addr <= {GROUP_COUNT * 48{1'b0}};
      cfg_group_valid <= {GROUP_COUNT{1'b0}};
    end else if (valid) begin
      cfg_update <= ~cfg_update;
      {cfg_mac_speed, cfg_speed_override, cfg_pause_quanta, cfg_pause_tx_soft_req,
       cfg_pause_tx_enable, cfg_group_valid, cfg_group_addr, cfg_min_frame_size, cfg_max_frame_size,
       cfg_max_client_data, cfg_mac_addr, cfg_control} <= bundle_dst;
    end
  end
endmodule
`default_nettype wire
