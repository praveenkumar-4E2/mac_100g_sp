`default_nettype none
module stats_cdc_bridge #(
    parameter WIDTH = 384
) (
    input wire apb_clk,
    input wire apb_rst,
    input wire mac_clk,
    input wire mac_rst,
    input wire request_apb,
    input wire [WIDTH-1:0] snapshot_mac,
    output reg ack_apb,
    output reg [WIDTH-1:0] snapshot_apb
);
  wire req_mac, ready, valid;
  reg req_seen, pending, send;
  wire [WIDTH:0] source_bundle = {req_seen, snapshot_mac};
  wire [WIDTH:0] dest_bundle;
  cdc_2ff req_sync_inst (
      .clk_dst(mac_clk),
      .rst_dst(mac_rst),
      .signal_src(request_apb),
      .signal_dst(req_mac)
  );
  always @(posedge mac_clk) begin
    if (mac_rst) begin
      req_seen <= 1'b0;
      pending <= 1'b0;
      send <= 1'b0;
    end else begin
      send <= 1'b0;
      if (req_mac != req_seen) begin
        req_seen <= req_mac;
        pending  <= 1'b1;
      end
      if (pending && ready) begin
        send <= 1'b1;
        pending <= 1'b0;
      end
    end
  end
  cdc_handshake #(
      .WIDTH(WIDTH + 1)
  ) snapshot_cdc_inst (
      .clk_src  (mac_clk),
      .rst_src  (mac_rst),
      .req_src  (send),
      .data_src (source_bundle),
      .ready_src(ready),
      .clk_dst  (apb_clk),
      .rst_dst  (apb_rst),
      .valid_dst(valid),
      .data_dst (dest_bundle),
      .ack_dst  (valid)
  );
  always @(posedge apb_clk) begin
    if (apb_rst) begin
      ack_apb <= 1'b0;
      snapshot_apb <= {WIDTH{1'b0}};
    end else if (valid) {ack_apb, snapshot_apb} <= dest_bundle;
  end
endmodule
`default_nettype wire
