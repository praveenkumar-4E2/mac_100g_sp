/**
 * @brief Top-level testbench module: instantiates the DUT, clocks,
 *        reset, ticks, APB configuration, and the AXI4-Stream
 *        virtual interfaces handed to the UVM environment.
 */
`timescale 1ns / 1ps
module mac_tb_top;
  `include "uvm_macros.svh"
  import uvm_pkg::*;
  import mac_test_pkg::*;

  // Typed top-level configuration published to the UVM config database
  // before run_test; the bootstrap initial block also drives its
  // config-intent fields and sets config_done once configuration completes.
  mac_tb_cfg_c tb_cfg;

  //============================================================================
  // Clocks & reset
  //============================================================================
  logic mac_clk;
  logic apb_clk;
  logic mac_rst;
  logic apb_rst;

  // These initial values hold the synchronous DUT domains in reset before
  // UVM run_phase starts. Subsequent assertion/release is owned exclusively
  // by the reset-agent drivers through these interfaces.
  mac_reset_if #(.INITIAL_RESET_VALUE(1'b1)) mac_reset_if_h (.clk(mac_clk));
  mac_reset_if #(.INITIAL_RESET_VALUE(1'b1)) apb_reset_if_h (.clk(apb_clk));
  assign mac_rst = mac_reset_if_h.rst;
  assign apb_rst = apb_reset_if_h.rst;

  // At 195.3125 MHz, each 512-bit MAC cycle transfers 100 Gb/s.  The TX and
  // RX timing consumers therefore advance once per mac_clk cycle.
  logic tx_tick;
  logic rx_tick;

  //============================================================================
  // AXI4-Stream testbench boundaries.  The names describe packet direction
  // relative to the DUT: stimulus enters on ingress; observed traffic exits
  // on egress.
  //============================================================================
  axi4_stream_if tb_ingress_axis_if (
      .clk(mac_clk),
      .rst(mac_rst)
  );

  axi4_stream_if tb_egress_axis_if (
      .clk(mac_clk),
      .rst(mac_rst)
  );

  // RS line-side ingress into the DUT RX path, driven by the active RS agent.
  mac_rs_stream_if tb_ingress_rs_if (
      .clk(mac_clk),
      .rst(mac_rst)
  );

  // Native MAC <-> RS interface (line side) observed on the DUT TX
  // output: driven by the TB from the native TX bridge nets so a passive
  // RS agent can verify the transmitted wire frames.
  mac_rs_stream_if tb_egress_rs_if (
      .clk(mac_clk),
      .rst(mac_rst)
  );

  // APB request signals are owned exclusively by the active APB UVM agent.
  apb_if apb_bus (
      .clk(apb_clk),
      .rst(apb_rst)
  );

  // An interface variable cannot be connected directly to a DUT input that
  // is forwarded internally by a continuous assignment in Questa.  These
  // nets form the legal pin-level boundary: the APB agent owns apb_bus and
  // the DUT consumes only resolved scalar nets.
  wire        apb_psel = apb_bus.psel;
  wire        apb_penable = apb_bus.penable;
  wire        apb_pwrite = apb_bus.pwrite;
  wire [15:0] apb_paddr = apb_bus.paddr;
  wire [31:0] apb_pwdata = apb_bus.pwdata;
  wire [31:0] apb_prdata;
  wire        apb_pready;
  wire        apb_pslverr;
  assign apb_bus.prdata  = apb_prdata;
  assign apb_bus.pready  = apb_pready;
  assign apb_bus.pslverr = apb_pslverr;

  //============================================================================
  // DUT scalar nets
  //============================================================================
  logic         tx_start;
  logic [ 47:0] tx_dest_addr;
  logic [ 47:0] tx_src_addr;
  logic [ 15:0] tx_length_type;
  logic         tx_client_valid;
  logic         tx_client_eop;
  logic [  6:0] tx_client_frame_end_byte_index;
  logic [511:0] tx_client_data;
  logic [ 63:0] tx_client_keep;
  logic         tb_egress_tx_mac_valid;
  logic         tb_egress_tx_mac_sop;
  logic         tb_egress_tx_mac_eop;
  logic         tb_egress_tx_mac_error;
  logic         tx_busy;
  logic         tx_frame_done;
  logic [511:0] tb_egress_tx_mac_data;
  logic [ 63:0] tb_egress_tx_mac_keep;
  logic [  6:0] tb_egress_tx_mac_frame_end_byte_index;
  logic         tb_ingress_rx_mac_valid;
  logic         tb_ingress_rx_mac_ready;
  logic         tb_ingress_rx_mac_sop;
  logic         tb_ingress_rx_mac_eop;
  logic         tb_ingress_rx_mac_error;
  logic         tb_ingress_rx_mac_fcs_present;
  logic [511:0] tb_ingress_rx_mac_data;
  logic [ 63:0] tb_ingress_rx_mac_keep;
  logic [  6:0] tb_ingress_rx_mac_frame_end_byte_index;
  logic         rx_client_valid;
  logic         rx_client_sop;
  logic         rx_client_eop;
  logic [511:0] rx_client_data;
  logic [ 63:0] rx_client_keep;
  logic [  6:0] rx_client_frame_end_byte_index;
  logic [ 47:0] rx_dest_addr;
  logic [ 47:0] rx_src_addr;
  logic [ 15:0] rx_length_type;
  logic [ 31:0] rx_received_fcs;
  logic         rx_frame_valid;
  logic         rx_frame_drop;
  logic         rx_crc_error;
  logic         rx_length_error;
  logic         rx_alignment_error;
  logic         rx_filter_hit;
  logic         rx_busy;
  logic         pause_active;
  logic         pause_timer_done;
  logic [ 31:0] rx_invalid_count;
  logic [ 31:0] rx_oversize_count;
  logic [ 31:0] rx_unsupported_control_count;
  logic [  6:0] interrupt_status;

  //============================================================================
  // DUT instantiation
  //============================================================================
  rtl_top dut_inst (
      .clk_core(mac_clk),
      .rst_n(~mac_rst),
      .pclk(apb_clk),
      .presetn(~apb_rst),
      .apb_psel(apb_psel),
      .apb_penable(apb_penable),
      .apb_pwrite(apb_pwrite),
      .apb_paddr(apb_paddr),
      .apb_pwdata(apb_pwdata),
      .apb_pstrb(4'hf),
      .apb_prdata(apb_prdata),
      .apb_pready(apb_pready),
      .apb_pslverr(apb_pslverr),
      .ingress_tx_axis_tdata(tb_ingress_axis_if.tdata),
      .ingress_tx_axis_tkeep(tb_ingress_axis_if.tkeep),
      .ingress_tx_axis_tvalid(tb_ingress_axis_if.tvalid),
      .ingress_tx_axis_tready(tb_ingress_axis_if.tready),
      .ingress_tx_axis_tlast(tb_ingress_axis_if.tlast),
      .ingress_tx_axis_tuser(tb_ingress_axis_if.tuser),
      .egress_tx_mac_data(tb_egress_tx_mac_data),
      .egress_tx_mac_keep(tb_egress_tx_mac_keep),
      .egress_tx_mac_valid(tb_egress_tx_mac_valid),
      .egress_tx_mac_ready(1'b1),
      .egress_tx_mac_sop(tb_egress_tx_mac_sop),
      .egress_tx_mac_eop(tb_egress_tx_mac_eop),
      .egress_tx_mac_frame_end_byte_index(tb_egress_tx_mac_frame_end_byte_index),
      .egress_tx_mac_error(tb_egress_tx_mac_error),
      .ingress_rx_mac_data(tb_ingress_rx_mac_data),
      .ingress_rx_mac_keep(tb_ingress_rx_mac_keep),
      .ingress_rx_mac_valid(tb_ingress_rx_mac_valid),
      .ingress_rx_mac_ready(tb_ingress_rx_mac_ready),
      .ingress_rx_mac_sop(tb_ingress_rx_mac_sop),
      .ingress_rx_mac_eop(tb_ingress_rx_mac_eop),
      .ingress_rx_mac_frame_end_byte_index(tb_ingress_rx_mac_frame_end_byte_index),
      .ingress_rx_mac_error(tb_ingress_rx_mac_error),
      .ingress_rx_mac_fcs_present(tb_ingress_rx_mac_fcs_present),
      .egress_rx_axis_tdata(tb_egress_axis_if.tdata),
      .egress_rx_axis_tkeep(tb_egress_axis_if.tkeep),
      .egress_rx_axis_tvalid(tb_egress_axis_if.tvalid),
      .egress_rx_axis_tready(tb_egress_axis_if.tready),
      .egress_rx_axis_tlast(tb_egress_axis_if.tlast),
      .egress_rx_axis_tuser(tb_egress_axis_if.tuser)
  );


  //============================================================================
  // Scalar tie-offs (AXI4-Stream mode: metadata comes from the stream)
  //============================================================================
  assign tx_dest_addr                   = '0;
  assign tx_src_addr                    = '0;
  assign tx_length_type                 = '0;
  assign tx_client_valid                = 1'b0;
  assign tx_client_data                 = '0;
  assign tx_client_keep                 = '0;
  assign tx_client_eop                  = 1'b0;
  assign tx_client_frame_end_byte_index = '0;

  // W3: the legacy scalar tx_start pin is inactive in AXI4-Stream mode.
  // Frame admission is owned entirely by the DUT's TX admission controller
  // (tx_axi_admission), which pulses the internal scheduler start from the
  // AXI first-beat presentation when TX enable, PAUSE, IPG, and pipeline
  // readiness permit. No testbench signal may generate an admission pulse.
  assign tx_start                       = 1'b0;

  //============================================================================
  // RX-ready controller (UTL-112/113): named baseline ready policy driven
  // from the typed top-level configuration. The TB is the downstream slave
  // of the DUT's m_axis_rx, so it owns tready. Before tb_cfg is built
  // (reset/bootstrap) the DUT is kept back-pressure-free; once the
  // configuration exists, ready follows tb_cfg.rx_ready_always. The config
  // is immutable after build, so the policy is sampled once rather than read
  // every cycle — an always_comb over tb_cfg.rx_ready_always would not react
  // because Questa ignores class-handle dynamic sensitivity (vlog-13365).
  // This named process replaces the permanent direct assign and can later be
  // swapped for a policy-driven controller.
  //============================================================================
  initial begin : tb_egress_axis_ready_controller
    tb_egress_axis_if.tready = 1'b1;
    wait (tb_cfg != null);
    tb_egress_axis_if.tready = tb_cfg.rx_ready_always;
  end

  // Native MAC <-> RS interface: the RS agent drives the line side
  // (tb_ingress_rs_if) and the DUT's scalar RX input ports are connected
  // to it, so frames flow through the DUT RX path and out the AXI
  // RX interface.
  assign tb_ingress_rx_mac_valid                = tb_ingress_rs_if.valid;
  assign tb_ingress_rx_mac_data                 = tb_ingress_rs_if.data;
  assign tb_ingress_rx_mac_keep                 = tb_ingress_rs_if.keep;
  assign tb_ingress_rx_mac_sop                  = tb_ingress_rs_if.sop;
  assign tb_ingress_rx_mac_eop                  = tb_ingress_rs_if.eop;
  assign tb_ingress_rx_mac_frame_end_byte_index = tb_ingress_rs_if.frame_end_byte_index;
  assign tb_ingress_rx_mac_error                = tb_ingress_rs_if.error;
  assign tb_ingress_rx_mac_fcs_present          = tb_ingress_rs_if.fcs_present;
  assign tb_ingress_rs_if.ready                 = tb_ingress_rx_mac_ready;

  // DUT TX wire: expose the native TX bridge on a MAC/RS stream so the passive RS agent
  // can verify transmitted frames. The TX path always appends FCS.
  always_comb begin
    tb_egress_rs_if.valid                = tb_egress_tx_mac_valid;
    tb_egress_rs_if.data                 = tb_egress_tx_mac_data;
    tb_egress_rs_if.keep                 = tb_egress_tx_mac_keep;
    tb_egress_rs_if.sop                  = tb_egress_tx_mac_sop;
    tb_egress_rs_if.eop                  = tb_egress_tx_mac_eop;
    tb_egress_rs_if.frame_end_byte_index = tb_egress_tx_mac_frame_end_byte_index;
    tb_egress_rs_if.error                = tb_egress_tx_mac_error;
    tb_egress_rs_if.fcs_present          = 1'b1;
    tb_egress_rs_if.ready                = 1'b1;
  end

  //============================================================================
  // RX status pulse log: one-cycle pulses from the DUT RX path.
  //============================================================================
  initial begin
    forever
    @(posedge mac_clk) begin
      if (!mac_rst) begin
        if (rx_frame_valid) $display("%0t RX_STATUS frame_valid", $time);
        if (rx_frame_drop) $display("%0t RX_STATUS frame_drop", $time);
        if (rx_crc_error) $display("%0t RX_STATUS crc_error", $time);
        if (rx_length_error) $display("%0t RX_STATUS length_error", $time);
        if (rx_alignment_error) $display("%0t RX_STATUS alignment_error", $time);
        if (rx_filter_hit) $display("%0t RX_STATUS filter_hit", $time);
      end
    end
  end

  //============================================================================
  // Clock generation: mac_clk 195.3125 MHz (5.12 ns);
  // apb_clk = mac_clk / 2 (10.24 ns), free-running from t=0. The RTL uses
  // synchronous resets, so apb_clk must run while apb_rst is asserted or the
  // APB-domain registers (reg_file, cdc_handshake) never see their reset.
  //============================================================================
  initial begin
    mac_clk = 1'b0;
    forever #2.56ns mac_clk = ~mac_clk;
  end

  initial begin
    apb_clk = 1'b0;
    forever #5.12ns apb_clk = ~apb_clk;
  end

  //============================================================================
  // 100 Gb/s tick generation: assert a timing advance every MAC cycle.
  // Keep the tick registered and reset-quiet so all sequential consumers see
  // a synchronous, single-domain enable.
  //============================================================================
  always @(posedge mac_clk or posedge mac_rst) begin
    if (mac_rst) begin
      tx_tick <= 1'b0;
      rx_tick <= 1'b0;
    end else begin
      tx_tick <= 1'b1;
      rx_tick <= 1'b1;
    end
  end

  //============================================================================
  // UVM: build and publish the typed top-level configuration (all virtual
  // interfaces + reset/configuration-completion state + config intent),
  // then run the test at time 0.
  //============================================================================
  initial begin
    tb_cfg               = mac_tb_cfg_c::type_id::create("tb_cfg");
    tb_cfg.axi_tx_vif    = tb_ingress_axis_if;
    tb_cfg.axi_rx_vif    = tb_egress_axis_if;
    tb_cfg.mac_rx_vif    = tb_ingress_rs_if;
    tb_cfg.mac_tx_vif    = tb_egress_rs_if;
    tb_cfg.apb_vif       = apb_bus;
    tb_cfg.mac_reset_vif = mac_reset_if_h;
    tb_cfg.apb_reset_vif = apb_reset_if_h;
    tb_cfg.validate();
    uvm_config_db#(mac_tb_cfg_c)::set(null, "*", "mac_tb_cfg", tb_cfg);
    run_test();
  end

endmodule
