class mac_apb_functional_config_virtual_seq_c extends mac_base_virtual_sequence_c;
  `uvm_object_utils(mac_apb_functional_config_virtual_seq_c)

  extern function new(string name = "mac_apb_functional_config_virtual_seq_c");
  extern task body();

  extern task apb_write_reg(bit [15:0] addr, bit [31:0] data);
  extern task apb_read_reg(bit [15:0] addr, output bit [31:0] data);
  extern task cdc_settle();
  extern task send_axi_tx(int count, int pmin = 46, int pmax = 1500);
  extern task send_rs_rx(int count, int pmin = 46, int pmax = 1500, bit broadcast = 1'b1);
  extern task phase1_apb_register_sweep();
  extern task phase2_configure_mac();
  extern task phase3_mixed_frame_sizes();
  extern task phase4_pause_and_filtering();
  extern task phase5_cdc_transition_stress();
  extern task phase6_sustained_bidirectional();
endclass

function mac_apb_functional_config_virtual_seq_c::new(string name = "mac_apb_functional_config_virtual_seq_c");
  super.new(name);
endfunction

task mac_apb_functional_config_virtual_seq_c::body();
  phase1_apb_register_sweep();
  phase2_configure_mac();
  phase3_mixed_frame_sizes();
  phase4_pause_and_filtering();
  phase5_cdc_transition_stress();
  phase6_sustained_bidirectional();
  `uvm_info("APB_FUNC_CFG", "All 6 phases completed successfully", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

task mac_apb_functional_config_virtual_seq_c::apb_write_reg(bit [15:0] addr, bit [31:0] data);
  apb_write_sequence_c seq_h;
  seq_h = apb_write_sequence_c::type_id::create($sformatf("func_cfg_wr_%h", addr));
  seq_h.m_addr  = addr;
  seq_h.m_wdata = data;
  seq_h.start(p_sequencer.apb_seqr_h);
endtask

task mac_apb_functional_config_virtual_seq_c::apb_read_reg(bit [15:0] addr, output bit [31:0] data);
  apb_read_sequence_c seq_h;
  seq_h = apb_read_sequence_c::type_id::create($sformatf("func_cfg_rd_%h", addr));
  seq_h.m_addr = addr;
  seq_h.start(p_sequencer.apb_seqr_h);
  data = seq_h.m_rdata;
endtask

task mac_apb_functional_config_virtual_seq_c::cdc_settle();
  #250ns;
endtask

task mac_apb_functional_config_virtual_seq_c::send_axi_tx(int count, int pmin, int pmax);
  axi_clean_sequence_c seq_h;
  seq_h = axi_clean_sequence_c::type_id::create("func_cfg_axi_tx");
  seq_h.num_tx          = count;
  seq_h.payload_min     = pmin;
  seq_h.payload_max     = pmax;
  seq_h.error_injection = 1'b0;
  seq_h.broadcast_da    = 1'b0;
  seq_h.inter_frame_delay = 0;
  seq_h.start(p_sequencer.client_ingress_seqr_h);
endtask

task mac_apb_functional_config_virtual_seq_c::send_rs_rx(int count, int pmin, int pmax, bit broadcast);
  rs_sequence_c seq_h;
  seq_h = rs_sequence_c::type_id::create("func_cfg_rs_rx");
  seq_h.num_frames      = count;
  seq_h.payload_min     = pmin;
  seq_h.payload_max     = pmax;
  seq_h.error_injection = 1'b0;
  seq_h.broadcast_da    = broadcast;
  seq_h.inter_frame_delay = 0;
  seq_h.start(p_sequencer.line_ingress_seqr_h);
endtask

// ---------------------------------------------------------------------------
// Phase 1: APB Register Sweep
// ---------------------------------------------------------------------------

task mac_apb_functional_config_virtual_seq_c::phase1_apb_register_sweep();
  bit [31:0] rdata;
  bit [31:0] wdata;
  bit [15:0] legal_addrs [9];
  bit [15:0] bad_addrs [4];

  `uvm_info("APB_FUNC_CFG", "=== Phase 1: APB Register Sweep ===", UVM_NONE)

  legal_addrs = '{
    reg_map_pkg::REG_GLOBAL_CONTROL,
    reg_map_pkg::REG_MAC_ADDR_LOW,
    reg_map_pkg::REG_MAC_ADDR_HIGH,
    reg_map_pkg::REG_MAX_CLIENT_DATA,
    reg_map_pkg::REG_MAX_FRAME_SIZE,
    reg_map_pkg::REG_MIN_FRAME_SIZE,
    reg_map_pkg::REG_INTERRUPT_ENABLE,
    reg_map_pkg::REG_MAC_SPEED_CONFIG,
    reg_map_pkg::REG_PAUSE_TX_CONFIG
  };
  bad_addrs = '{16'h0001, 16'h0002, 16'h004e, 16'h00a0};

  foreach (legal_addrs[i]) begin
    wdata = $urandom;
    apb_write_reg(legal_addrs[i], wdata);
    apb_read_reg(legal_addrs[i], rdata);
    `uvm_info("APB_FUNC_CFG", $sformatf("  RW reg %h: wrote %h read %h",
              legal_addrs[i], wdata, rdata), UVM_HIGH)
  end

  for (int unsigned g = 0; g < 4; g++) begin
    wdata = $urandom;
    apb_write_reg(reg_map_pkg::group_low_addr(g), wdata);
    apb_read_reg(reg_map_pkg::group_low_addr(g), rdata);
    wdata = {15'd0, 1'b1, $urandom & 16'hFFFF};
    apb_write_reg(reg_map_pkg::group_high_addr(g), wdata);
    apb_read_reg(reg_map_pkg::group_high_addr(g), rdata);
  end

  apb_read_reg(reg_map_pkg::REG_VERSION, rdata);
  if (rdata !== 32'h4150_4231)
    `uvm_error("APB_FUNC_CFG", $sformatf("VERSION mismatch: got %h expected 4150_4231", rdata))

  apb_read_reg(reg_map_pkg::REG_OVERSIZE_CONTROL, rdata);
  apb_read_reg(reg_map_pkg::REG_PAUSE_CONTROL, rdata);
  apb_read_reg(reg_map_pkg::REG_PAUSE_STATUS, rdata);
  apb_read_reg(reg_map_pkg::REG_RX_STATUS, rdata);
  apb_read_reg(reg_map_pkg::REG_TX_STATUS, rdata);

  apb_read_reg(reg_map_pkg::REG_INTERRUPT_STATUS, rdata);
  if (rdata != '0) begin
    apb_write_reg(reg_map_pkg::REG_INTERRUPT_STATUS, rdata);
    #200ns;
    apb_read_reg(reg_map_pkg::REG_INTERRUPT_STATUS, rdata);
  end

  begin
    bit [31:0] patterns [5];
    patterns[0] = 32'h0000_0000;
    patterns[1] = 32'hffff_ffff;
    patterns[2] = 32'haaaa_aaaa;
    patterns[3] = 32'h5555_5555;
    patterns[4] = $urandom;
    foreach (patterns[i]) begin
      apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, patterns[i]);
      apb_read_reg(reg_map_pkg::REG_GLOBAL_CONTROL, rdata);
    end
  end

  foreach (bad_addrs[i]) begin
    apb_write_sequence_c wr_h;
    apb_read_sequence_c  rd_h;
    wr_h = apb_write_sequence_c::type_id::create($sformatf("bad_wr_%h", bad_addrs[i]));
    wr_h.m_addr  = bad_addrs[i];
    wr_h.m_wdata = $urandom;
    wr_h.m_expect_slverr = 1'b1;
    wr_h.m_expected_status = APB_SLVERR;
    wr_h.start(p_sequencer.apb_seqr_h);

    rd_h = apb_read_sequence_c::type_id::create($sformatf("bad_rd_%h", bad_addrs[i]));
    rd_h.m_addr = bad_addrs[i];
    rd_h.m_expect_slverr = 1'b1;
    rd_h.m_expected_status = APB_SLVERR;
    rd_h.start(p_sequencer.apb_seqr_h);
  end

  repeat (20) begin
    bit [15:0] rand_addr;
    bit [31:0] rand_data;
    bit        legal;
    legal = ($urandom_range(0, 3) != 0);
    if (legal) begin
      rand_addr = legal_addrs[$urandom_range(0, 8)];
      rand_data = $urandom;
      if ($urandom_range(0, 1))
        apb_write_reg(rand_addr, rand_data);
      else
        apb_read_reg(rand_addr, rand_data);
    end else begin
      rand_addr = bad_addrs[$urandom_range(0, 3)];
      rand_data = $urandom;
      if ($urandom_range(0, 1)) begin
        apb_write_sequence_c wr_h;
        wr_h = apb_write_sequence_c::type_id::create($sformatf("rand_bad_wr_%h", rand_addr));
        wr_h.m_addr  = rand_addr;
        wr_h.m_wdata = rand_data;
        wr_h.m_expect_slverr = 1'b1;
        wr_h.m_expected_status = APB_SLVERR;
        wr_h.start(p_sequencer.apb_seqr_h);
      end else begin
        apb_read_sequence_c rd_h;
        rd_h = apb_read_sequence_c::type_id::create($sformatf("rand_bad_rd_%h", rand_addr));
        rd_h.m_addr = rand_addr;
        rd_h.m_expect_slverr = 1'b1;
        rd_h.m_expected_status = APB_SLVERR;
        rd_h.start(p_sequencer.apb_seqr_h);
      end
    end
  end

  `uvm_info("APB_FUNC_CFG", "Phase 1 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 2: Configure MAC for bidirectional traffic
// ---------------------------------------------------------------------------

task mac_apb_functional_config_virtual_seq_c::phase2_configure_mac();
  bit [31:0] rdata;
  bit [31:0] ctrl;

  `uvm_info("APB_FUNC_CFG", "=== Phase 2: Configure MAC ===", UVM_NONE)

  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PROMISCUOUS_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, 32'h0200_0001);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h0000_0000);
  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  apb_write_reg(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_read_reg(reg_map_pkg::REG_GLOBAL_CONTROL, rdata);
  cdc_settle();

  // Drive concurrent traffic: 10 AXI TX + 10 RS RX
  fork
    send_axi_tx(10, 46, 46);
    send_rs_rx(10, 46, 46, 1'b1);
  join

  // Reconfigure frame limits
  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
  cdc_settle();

  fork
    send_axi_tx(5, 100, 900);
    // 1000-byte MAX_FRAME_SIZE includes the Ethernet header and FCS.  Keep
    // the payload at 982 bytes so this phase drives a legal boundary frame.
    send_rs_rx(5, 982, 982, 1'b1);
  join

  #2us;

  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  cdc_settle();

  `uvm_info("APB_FUNC_CFG", "Phase 2 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 3: Mixed Frame Sizes
// ---------------------------------------------------------------------------

task mac_apb_functional_config_virtual_seq_c::phase3_mixed_frame_sizes();
  bit [31:0] ctrl;

  `uvm_info("APB_FUNC_CFG", "=== Phase 3: Mixed Frame Sizes ===", UVM_NONE)

  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PROMISCUOUS_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  apb_write_reg(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  cdc_settle();

  fork
    begin
      send_axi_tx(2, 46, 46);
      #($urandom_range(0, 30) * 1ns);
      send_axi_tx(2, 500, 500);
      #($urandom_range(0, 30) * 1ns);
      send_axi_tx(2, 1500, 1500);
    end
    begin
      send_rs_rx(2, 46, 46, 1'b1);
      #($urandom_range(0, 30) * 1ns);
      send_rs_rx(2, 128, 128, 1'b1);
      #($urandom_range(0, 30) * 1ns);
      send_rs_rx(2, 1500, 1500, 1'b1);
    end
  join

  #2us;

  `uvm_info("APB_FUNC_CFG", "Phase 3 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 4: PAUSE + Address Filtering
// ---------------------------------------------------------------------------

task mac_apb_functional_config_virtual_seq_c::phase4_pause_and_filtering();
  bit [31:0] rdata;
  bit [31:0] ctrl;
  bit [47:0] station_addr = 48'h02_00_00_00_40_04;
  bit [47:0] group0_addr  = 48'h01_00_5e_00_40_04;

  `uvm_info("APB_FUNC_CFG", "=== Phase 4: PAUSE + Address Filtering ===", UVM_NONE)

  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PAUSE_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, station_addr[31:0]);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, station_addr[47:32]);
  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  apb_write_reg(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);

  apb_write_reg(reg_map_pkg::group_low_addr(0), group0_addr[31:0]);
  apb_write_reg(reg_map_pkg::group_high_addr(0), {15'd0, 1'b1, group0_addr[47:32]});
  cdc_settle();

  begin
    mac_control_frame_sequence_c pause_seq;
    pause_seq = mac_control_frame_sequence_c::type_id::create("func_cfg_pause");
    pause_seq.pause_quanta = 16'h0100;
    pause_seq.start(p_sequencer.line_ingress_seqr_h);
  end
  #1us;
  apb_read_reg(reg_map_pkg::REG_PAUSE_STATUS, rdata);

  apb_write_reg(reg_map_pkg::REG_PAUSE_TX_CONFIG,
                (32'h1 << reg_map_pkg::PAUSE_TX_ENABLE_BIT) |
                (32'h1 << reg_map_pkg::PAUSE_TX_SOFT_REQ_BIT));
  #500ns;

  fork
    send_rs_rx(3, 46, 100, 1'b0);
    begin
      repeat (2) begin
        apb_002_rx_frame_sequence_c grp_seq;
        grp_seq = apb_002_rx_frame_sequence_c::type_id::create("func_cfg_grp0");
        grp_seq.frame_octets = 100;
        grp_seq.destination = group0_addr;
        grp_seq.payload_pattern = mac_hvl_utils_c::PAYLOAD_RANDOM;
        grp_seq.payload_seed = $urandom;
        grp_seq.start(p_sequencer.line_ingress_seqr_h);
      end
    end
    begin
      apb_002_rx_frame_sequence_c nomatch_seq;
      nomatch_seq = apb_002_rx_frame_sequence_c::type_id::create("func_cfg_nomatch");
      nomatch_seq.frame_octets = 100;
      nomatch_seq.destination = 48'hDE_AD_BE_EF_00_01;
      nomatch_seq.payload_pattern = mac_hvl_utils_c::PAYLOAD_RANDOM;
      nomatch_seq.payload_seed = $urandom;
      nomatch_seq.start(p_sequencer.line_ingress_seqr_h);
    end
  join

  #2us;

  `uvm_info("APB_FUNC_CFG", "Phase 4 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 5: CDC Transition Stress
// ---------------------------------------------------------------------------

task mac_apb_functional_config_virtual_seq_c::phase5_cdc_transition_stress();
  bit [31:0] ctrl;
  bit [47:0] old_addr = 48'h02_00_00_00_50_05;
  bit [47:0] new_addr = 48'h02_00_00_00_50_06;

  `uvm_info("APB_FUNC_CFG", "=== Phase 5: CDC Transition Stress ===", UVM_NONE)

  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PROMISCUOUS_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, old_addr[31:0]);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, old_addr[47:32]);
  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
  cdc_settle();

  fork
    begin
      repeat (12) begin
        apb_002_rx_frame_sequence_c frame_h;
        frame_h = apb_002_rx_frame_sequence_c::type_id::create("cdc_stress_frame");
        frame_h.frame_octets = $urandom_range(900, 1000);
        frame_h.destination = ($urandom_range(0, 1)) ? old_addr : new_addr;
        frame_h.payload_pattern = mac_hvl_utils_c::PAYLOAD_RANDOM;
        frame_h.payload_seed = $urandom;
        frame_h.start(p_sequencer.line_ingress_seqr_h);
        #($urandom_range(0, 20) * 1ns);
      end
    end
    begin
      repeat (6) begin
        apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, new_addr[31:0]);
        apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, new_addr[47:32]);
        apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1200);
        apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, old_addr[31:0]);
        apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, old_addr[47:32]);
        apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1000);
      end
    end
  join

  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, new_addr[31:0]);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, new_addr[47:32]);
  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1200);
  cdc_settle();

  begin
    apb_002_rx_frame_sequence_c verify_h;
    verify_h = apb_002_rx_frame_sequence_c::type_id::create("cdc_verify_final");
    verify_h.frame_octets = 1100;
    verify_h.destination = new_addr;
    verify_h.payload_pattern = mac_hvl_utils_c::PAYLOAD_INCREMENTING;
    verify_h.payload_seed = $urandom;
    verify_h.start(p_sequencer.line_ingress_seqr_h);
  end
  #1us;

  `uvm_info("APB_FUNC_CFG", "Phase 5 complete", UVM_NONE)
endtask

// ---------------------------------------------------------------------------
// Phase 6: Sustained Bidirectional + Periodic APB Modification
// ---------------------------------------------------------------------------

task mac_apb_functional_config_virtual_seq_c::phase6_sustained_bidirectional();
  bit [31:0] ctrl;
  bit [31:0] rdata;

  `uvm_info("APB_FUNC_CFG", "=== Phase 6: Sustained Bidirectional ===", UVM_NONE)

  ctrl = (32'h1 << reg_map_pkg::CTRL_RX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_TX_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PROMISCUOUS_BIT) |
         (32'h1 << reg_map_pkg::CTRL_PAUSE_BIT);
  apb_write_reg(reg_map_pkg::REG_GLOBAL_CONTROL, ctrl);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_LOW, 32'h0200_0006);
  apb_write_reg(reg_map_pkg::REG_MAC_ADDR_HIGH, 32'h0000_0000);
  apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
  apb_write_reg(reg_map_pkg::REG_MIN_FRAME_SIZE, 32'd64);
  apb_write_reg(reg_map_pkg::REG_INTERRUPT_ENABLE, 32'h0000_007F);
  cdc_settle();

  fork
    begin
      int sizes [6];
      sizes = '{46, 46, 200, 200, 800, 1500};
      foreach (sizes[s]) begin
        send_axi_tx(2, sizes[s], sizes[s]);
        #($urandom_range(0, 50) * 1ns);
      end
    end
    begin
      int sizes [6];
      sizes = '{46, 46, 128, 128, 1000, 1500};
      foreach (sizes[s]) begin
        send_rs_rx(2, sizes[s], sizes[s], 1'b1);
        #($urandom_range(0, 50) * 1ns);
      end
    end
    begin
      repeat (7) begin
        #1us;
        apb_write_reg(reg_map_pkg::REG_MAC_SPEED_CONFIG, $urandom & 32'h0000_000F);
        apb_write_reg(reg_map_pkg::REG_MAX_FRAME_SIZE, 32'd1518);
        apb_write_reg(reg_map_pkg::REG_INTERRUPT_ENABLE, $urandom);
        apb_read_reg(reg_map_pkg::REG_RX_INVALID_COUNT, rdata);
        apb_read_reg(reg_map_pkg::REG_RX_OVERSIZE_COUNT, rdata);
      end
    end
  join

  #3us;

  apb_read_reg(reg_map_pkg::REG_RX_INVALID_COUNT, rdata);
  `uvm_info("APB_FUNC_CFG", $sformatf("  Final RX_INVALID_COUNT: %0d", rdata), UVM_HIGH)
  apb_read_reg(reg_map_pkg::REG_RX_OVERSIZE_COUNT, rdata);
  `uvm_info("APB_FUNC_CFG", $sformatf("  Final RX_OVERSIZE_COUNT: %0d", rdata), UVM_HIGH)
  apb_read_reg(reg_map_pkg::REG_INTERRUPT_STATUS, rdata);
  `uvm_info("APB_FUNC_CFG", $sformatf("  Final INTERRUPT_STATUS: %h", rdata), UVM_HIGH)

  `uvm_info("APB_FUNC_CFG", "Phase 6 complete", UVM_NONE)
endtask
