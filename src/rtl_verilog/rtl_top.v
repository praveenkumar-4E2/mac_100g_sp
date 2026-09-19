`default_nettype none
`include "mac_params.vh"

// Pure-Verilog DUT boundary.  It exposes only the client AXI streams, native
// MAC/RS streams, APB3, and clock/reset signals; implementation stays in
// mac_core_v.
module rtl_top (
    input  wire         clk_core,
    input  wire         rst_n,
    input  wire         pclk,
    input  wire         presetn,
    input  wire         apb_psel,
    input  wire         apb_penable,
    input  wire         apb_pwrite,
    input  wire [ 15:0] apb_paddr,
    input  wire [ 31:0] apb_pwdata,
    input  wire [  3:0] apb_pstrb,
    output wire [ 31:0] apb_prdata,
    output wire         apb_pready,
    output wire         apb_pslverr,
    input  wire [`AXIS_DATA_WIDTH-1:0] ingress_tx_axis_tdata,
    input  wire [`AXIS_KEEP_WIDTH-1:0] ingress_tx_axis_tkeep,
    input  wire         ingress_tx_axis_tvalid,
    output wire         ingress_tx_axis_tready,
    input  wire         ingress_tx_axis_tlast,
    input  wire [  7:0] ingress_tx_axis_tuser,
    output wire [`AXIS_DATA_WIDTH-1:0] egress_tx_mac_data,
    output wire [`AXIS_KEEP_WIDTH-1:0] egress_tx_mac_keep,
    output wire         egress_tx_mac_valid,
    input  wire         egress_tx_mac_ready,
    output wire         egress_tx_mac_sop,
    output wire         egress_tx_mac_eop,
    output wire [  6:0] egress_tx_mac_frame_end_byte_index,
    output wire         egress_tx_mac_error,
    input  wire [`AXIS_DATA_WIDTH-1:0] ingress_rx_mac_data,
    input  wire [`AXIS_KEEP_WIDTH-1:0] ingress_rx_mac_keep,
    input  wire         ingress_rx_mac_valid,
    output wire         ingress_rx_mac_ready,
    input  wire         ingress_rx_mac_sop,
    input  wire         ingress_rx_mac_eop,
    input  wire [  6:0] ingress_rx_mac_frame_end_byte_index,
    input  wire         ingress_rx_mac_error,
    input  wire         ingress_rx_mac_fcs_present,
    output wire [`AXIS_DATA_WIDTH-1:0] egress_rx_axis_tdata,
    output wire [`AXIS_KEEP_WIDTH-1:0] egress_rx_axis_tkeep,
    output wire         egress_rx_axis_tvalid,
    input  wire         egress_rx_axis_tready,
    output wire         egress_rx_axis_tlast,
    output wire [  7:0] egress_rx_axis_tuser
);

  // APB write strobes are retained at the wrapper boundary for APB3
  // compatibility. The current 32-bit register implementation writes full
  // words, so no internal byte-strobe port is required.
  wire unused_apb_pstrb = &apb_pstrb;

  mac_core_v mac_core_inst (
      .clk_core(clk_core),
      .rst_n(rst_n),
      .pclk(pclk),
      .presetn(presetn),
      .apb_psel(apb_psel),
      .apb_penable(apb_penable),
      .apb_pwrite(apb_pwrite),
      .apb_paddr(apb_paddr),
      .apb_pwdata(apb_pwdata),
      .apb_prdata(apb_prdata),
      .apb_pready(apb_pready),
      .apb_pslverr(apb_pslverr),
      .ingress_tx_axis_tdata(ingress_tx_axis_tdata),
      .ingress_tx_axis_tkeep(ingress_tx_axis_tkeep),
      .ingress_tx_axis_tvalid(ingress_tx_axis_tvalid),
      .ingress_tx_axis_tready(ingress_tx_axis_tready),
      .ingress_tx_axis_tlast(ingress_tx_axis_tlast),
      .ingress_tx_axis_tuser(ingress_tx_axis_tuser),
      .egress_tx_mac_data(egress_tx_mac_data),
      .egress_tx_mac_keep(egress_tx_mac_keep),
      .egress_tx_mac_valid(egress_tx_mac_valid),
      .egress_tx_mac_ready(egress_tx_mac_ready),
      .egress_tx_mac_sop(egress_tx_mac_sop),
      .egress_tx_mac_eop(egress_tx_mac_eop),
      .egress_tx_mac_frame_end_byte_index(egress_tx_mac_frame_end_byte_index),
      .egress_tx_mac_error(egress_tx_mac_error),
      .ingress_rx_mac_data(ingress_rx_mac_data),
      .ingress_rx_mac_keep(ingress_rx_mac_keep),
      .ingress_rx_mac_valid(ingress_rx_mac_valid),
      .ingress_rx_mac_ready(ingress_rx_mac_ready),
      .ingress_rx_mac_sop(ingress_rx_mac_sop),
      .ingress_rx_mac_eop(ingress_rx_mac_eop),
      .ingress_rx_mac_frame_end_byte_index(ingress_rx_mac_frame_end_byte_index),
      .ingress_rx_mac_error(ingress_rx_mac_error),
      .ingress_rx_mac_fcs_present(ingress_rx_mac_fcs_present),
      .egress_rx_axis_tdata(egress_rx_axis_tdata),
      .egress_rx_axis_tkeep(egress_rx_axis_tkeep),
      .egress_rx_axis_tvalid(egress_rx_axis_tvalid),
      .egress_rx_axis_tready(egress_rx_axis_tready),
      .egress_rx_axis_tlast(egress_rx_axis_tlast),
      .egress_rx_axis_tuser(egress_rx_axis_tuser)
  );
endmodule

`default_nettype wire
