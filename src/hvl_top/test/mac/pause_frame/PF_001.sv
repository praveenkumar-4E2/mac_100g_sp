`ifndef PF_001_PAUSE_TEST_SVH
`define PF_001_PAUSE_TEST_SVH

//------------------------------------------------------------------------------
// Class: PF_001_pause_test_c
// PF-001 all scenarios (S1-S5) in one test: basic valid PAUSE, validation/
// negative variants, non-control traffic, pause-quanta boundary values, and
// TX admission/inhibition behavior while paused.
//
// Agent topology covers both the validation checks (S1-S4: line-side RS
// active stimulus, AXI RX passive to confirm consumption/delivery) and the
// admission check (S5: AXI TX active to submit client data, RS TX passive
// to observe DUT-originated egress while paused).
//------------------------------------------------------------------------------
class PF_001_pause_test_c extends mac_base_test_c;

  // PAUSE timer constants: IEEE 802.3 quanta = 512 bit-times
  // Sim rate: ~165 ns per bit-time (per S5 comment: 0x0020 => 2.7 us)
  // Max pause: quanta=0xFFFF => 65535 * 512 * 165 ns ~488 ms
  localparam time PAUSE_BIT_TIME_NS = 165;
  localparam time MAX_QUANTA_NS = (16'hFFFF * 512 * PAUSE_BIT_TIME_NS);
  localparam time PAUSE_TIMEOUT_NS = MAX_QUANTA_NS + 10_000;
  `uvm_component_utils(PF_001_pause_test_c)

  extern function new(string name = "PF_001_pause_test_c",
                      uvm_component parent = null);
  extern virtual function void configure_test();
  extern virtual task run_stimulus(uvm_phase phase);
  extern task apb_write(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                        bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task apb_read(bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                       output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  extern task drive_and_check(string case_name, mac_pause_frame_variant_sequence_c seq_h,
                              bit expect_pause_active, bit expect_axi_delivery);
  extern task wait_for_pause_clear(string case_name, time timeout_ns = PAUSE_TIMEOUT_NS);
  extern task run_validation_scenarios();
  extern task run_admission_scenario();
endclass

function PF_001_pause_test_c::new(string name = "PF_001_pause_test_c",
                                  uvm_component parent = null);
  super.new(name, parent);
  // S1-S4 needs: RS active (drive PAUSE/variant frames), AXI passive (observe delivery)
  // S5 needs:    RS active (drive PAUSE), AXI active (submit client TX), RS passive (observe egress)
  num_rs_active_agents   = 1;
  num_axi_active_agents  = 1;
  num_rs_passive_agents  = 1;
  num_axi_passive_agents = 1;
  num_tx_frames          = 1;
endfunction

function void PF_001_pause_test_c::configure_test();
  super.configure_test();
  // S2D intentionally injects a runt control frame; this checker is for
  // legal-frame protocol conformance, so it must not turn directed negative
  // stimulus into a test error.
  env_cfg_h.has_protocol_checkers = 1'b0;
  // S5 verifies admission timing at the wire.  The generic TX reference
  // model does not model a request held by the admission gate, so it cannot
  // provide a meaningful frame-by-frame comparison for this one scenario.
  env_cfg_h.scoreboard_enable_tx_check = 1'b0;
endfunction

task PF_001_pause_test_c::apb_write(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                    input bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_write_sequence_c write_h;
  write_h         = apb_write_sequence_c::type_id::create($sformatf("apb_wr_%h", addr));
  write_h.m_addr  = addr;
  write_h.m_wdata = data;
  write_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
endtask

task PF_001_pause_test_c::apb_read(input bit [apb_transfer_t::ADDR_WIDTH-1:0] addr,
                                   output bit [apb_transfer_t::DATA_WIDTH-1:0] data);
  apb_read_sequence_c read_h;
  read_h        = apb_read_sequence_c::type_id::create($sformatf("apb_rd_%h", addr));
  read_h.m_addr = addr;
  read_h.start(env_h.virtual_sequencer_h.apb_seqr_h);
  data = read_h.m_rdata;
endtask

// Drives one variant frame, waits for the DUT to settle, then checks
// pause_active and AXI delivery against the scenario's expected outcome.
// axi_rx_cnt is read as a running total (never cleared), so callers must
// order calls such that at most one delivering frame occurs per check when
// expect_axi_delivery differentiation matters within a single test.
task PF_001_pause_test_c::drive_and_check(string case_name,
                                          mac_pause_frame_variant_sequence_c seq_h,
                                          bit expect_pause_active,
                                          bit expect_axi_delivery);
  bit [apb_transfer_t::DATA_WIDTH-1:0] status_data;
  int                                   axi_rx_cnt_before;
  int                                   axi_rx_cnt_after;
  bit                                   timed_out;

  axi_rx_cnt_before = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;

  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);

  // Bounded settle: DUT decode + CDC to the APB-visible status register.
  #1us;

  apb_read(reg_map_pkg::REG_RX_STATUS, status_data);
  if (status_data[0] == expect_pause_active)
    `uvm_info("PF_001", $sformatf("PASS [%0s]: pause_active=%0b as expected", case_name,
              status_data[0]), UVM_NONE)
  else
    `uvm_error("PF_001", $sformatf(
               "FAIL [%0s]: pause_active=%0b, expected %0b (REG_RX_STATUS=%h)", case_name,
               status_data[0], expect_pause_active, status_data))

  axi_rx_cnt_after = env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (expect_axi_delivery) begin
    mac_wait_utils_c::wait_for_axi_count_at_least(axi_rx_cnt_before + 1,
        env_h.axi4_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt, axi_rx_vif,
        MAC_COMPLETION_TIMEOUT_NS, timed_out);
    if (timed_out)
      `uvm_error("PF_001", $sformatf(
                 "FAIL [%0s]: expected AXI delivery, none observed (before=%0d)", case_name,
                 axi_rx_cnt_before))
    else
      `uvm_info("PF_001", $sformatf("PASS [%0s]: frame delivered to AXI client as expected",
                case_name), UVM_NONE)
  end else begin
    if (axi_rx_cnt_after == axi_rx_cnt_before)
      `uvm_info("PF_001", $sformatf("PASS [%0s]: frame consumed, no client delivery", case_name),
                UVM_NONE)
    else
      `uvm_error("PF_001", $sformatf(
                 "FAIL [%0s]: unexpected AXI delivery (before=%0d after=%0d)", case_name,
                 axi_rx_cnt_before, axi_rx_cnt_after))
  end
endtask

// Polls REG_RX_STATUS bit 0 until pause_active clears or timeout_ns elapses,
// so the next directed case never starts while a prior case's pause timer
// is still counting down. Bounded, non-blocking on a stuck DUT: reports via
// uvm_error rather than hanging the test.
task PF_001_pause_test_c::wait_for_pause_clear(string case_name,
                                               time timeout_ns = PAUSE_TIMEOUT_NS);
  bit [apb_transfer_t::DATA_WIDTH-1:0] status_data;
  time                                   start_ts;
  start_ts = $time;
  forever begin
    apb_read(reg_map_pkg::REG_RX_STATUS, status_data);
    if (!status_data[0]) return;
    if (($time - start_ts) >= timeout_ns) begin
      `uvm_error("PF_001", $sformatf(
                 "FAIL [%0s]: pause_active still set %0t after case, giving up wait", case_name,
                 timeout_ns))
      return;
    end
    #1us;
  end
endtask

// S1-S4: basic valid PAUSE, negative/validation variants, non-control
// traffic, and pause-quanta boundary sweep.
task PF_001_pause_test_c::run_validation_scenarios();
  mac_pause_frame_variant_sequence_c seq_h;

  //--------------------------------------------------------------------
  // Scenario 1: basic valid PAUSE, quanta=100.
  //--------------------------------------------------------------------
  seq_h = mac_pause_frame_variant_sequence_c::type_id::create("s1_basic_valid");
  drive_and_check("S1_BASIC_VALID", seq_h, 1'b1, 1'b0);
  wait_for_pause_clear("S1_BASIC_VALID");

  //--------------------------------------------------------------------
  // Scenario 2: negative/validation variants. Each must NOT change pause
  // state and must NOT reach the AXI client (all remain classified as
  // control-frame traffic at the RX MAC, per control_classifier.v keying
  // solely off EtherType==0x8808).
  //--------------------------------------------------------------------

  // 2a: corrupted FCS.
  seq_h = mac_pause_frame_variant_sequence_c::type_id::create("s2a_bad_fcs");
  seq_h.corrupt_fcs = 1'b1;
  drive_and_check("S2A_BAD_FCS", seq_h, 1'b0, 1'b0);
  wait_for_pause_clear("S2A_BAD_FCS");

  // 2b: invalid destination address (neither reserved multicast nor local
  // station address) -> pause_rx.v's event-accept condition never fires.
  seq_h = mac_pause_frame_variant_sequence_c::type_id::create("s2b_invalid_da");
  seq_h.dst_addr_ovr = 48'hAA_BB_CC_DD_EE_FF;
  drive_and_check("S2B_INVALID_DA", seq_h, 1'b0, 1'b0);
  wait_for_pause_clear("S2B_INVALID_DA");

  // 2c: unsupported opcode (still classified control via EtherType, but
  // opcode != 0x0001 so pause_rx.v never asserts timer_load_valid).
  seq_h = mac_pause_frame_variant_sequence_c::type_id::create("s2c_unsupported_opcode");
  seq_h.opcode_ovr = 16'h0002;
  drive_and_check("S2C_UNSUPPORTED_OPCODE", seq_h, 1'b0, 1'b0);
  wait_for_pause_clear("S2C_UNSUPPORTED_OPCODE");

  // 2d: below-minimum-length control frame (14B header + 4B payload + 4B
  // FCS = 22B, well under the 64B minFrameSize).
  seq_h = mac_pause_frame_variant_sequence_c::type_id::create("s2d_short_frame");
  seq_h.payload_octets = 4;
  drive_and_check("S2D_SHORT_FRAME", seq_h, 1'b0, 1'b0);
  wait_for_pause_clear("S2D_SHORT_FRAME");

  //--------------------------------------------------------------------
  // Scenario 3: non-control traffic. Same 4-byte "opcode+quanta" pattern
  // is harmless payload once EtherType is not 0x8808 (IPv4 EtherType),
  // proving classification is EtherType-driven and ordinary data still
  // reaches the client.
  //--------------------------------------------------------------------
  seq_h = mac_pause_frame_variant_sequence_c::type_id::create("s3_non_control_ipv4");
  seq_h.ether_type_ovr = 16'h0800;  // IPv4
  seq_h.dst_addr_ovr   = 48'hFF_FF_FF_FF_FF_FF;  // broadcast, always accepted
  drive_and_check("S3_NON_CONTROL_IPV4", seq_h, 1'b0, 1'b1);
  wait_for_pause_clear("S3_NON_CONTROL_IPV4");

  seq_h = mac_pause_frame_variant_sequence_c::type_id::create("s3_non_control_arp");
  seq_h.ether_type_ovr = 16'h0806;  // ARP
  seq_h.dst_addr_ovr   = 48'hFF_FF_FF_FF_FF_FF;
  drive_and_check("S3_NON_CONTROL_ARP", seq_h, 1'b0, 1'b1);
  wait_for_pause_clear("S3_NON_CONTROL_ARP");

  //--------------------------------------------------------------------
  // Scenario 4: pause-quanta boundary values (0, 1, 100, 65535). Each is
  // driven as an isolated valid PAUSE frame; only pause_active is checked
  // here (parameter-extraction proof), not timer duration.
  //--------------------------------------------------------------------
  begin
    bit [15:0] quanta_values[4] = '{16'h0000, 16'h0001, 16'h0064, 16'hFFFF};
    foreach (quanta_values[i]) begin
      seq_h            = mac_pause_frame_variant_sequence_c::type_id::create(
          $sformatf("s4_quanta_%0h", quanta_values[i]));
      seq_h.pause_quanta = quanta_values[i];
      // quanta=0 loads a zero-length pause: pause_active may already have
      // cleared by the time REG_RX_STATUS is sampled below, so this case is
      // checked for correct admission (frame consumed, no state error) but
      // not for a sustained pause_active=1.
      drive_and_check($sformatf("S4_QUANTA_%0h", quanta_values[i]), seq_h,
                       (quanta_values[i] != 16'h0000), 1'b0);
      // Each following PAUSE frame reloads the timer.  In particular, do not
      // wait for 0xFFFF (about 168 ms at the implementation's tick rate).
      // The admission scenario immediately reloads it with a short value.
    end
  end
endtask

// S5: admission gate behavior. A received PAUSE frame must inhibit
// DUT-originated data-frame transmission (F7/F10 inhibit path) while
// pause_active is set, and resume once the pause timer expires.
task PF_001_pause_test_c::run_admission_scenario();
  mac_pause_frame_variant_sequence_c seq_h;
  axi_sequence_c                     tx_seq_h;
  bit [apb_transfer_t::DATA_WIDTH-1:0] status_data;
  int                                   tx_egress_before, tx_egress_after;
  bit                                   timed_out;

  // Small quanta so this scenario does not wait for a large pause window;
  // large enough to reliably observe TX inhibition before it clears.
  seq_h              = mac_pause_frame_variant_sequence_c::type_id::create("admission_pause_seq");
  seq_h.pause_quanta = 16'h0020;  // ~2.7 us window at 512-bit-time quanta
  seq_h.start(env_h.mac_rs_stream_agent_top_h.active_agents[0].sequencer_h);
  #1us;

  apb_read(reg_map_pkg::REG_RX_STATUS, status_data);
  if (!status_data[0])
    `uvm_error("PF_001_ADM", $sformatf(
               "FAIL: pause_active not asserted before TX admission check (REG_RX_STATUS=%h)",
               status_data))
  else
    `uvm_info("PF_001_ADM", "pause_active asserted; issuing data TX request while paused",
              UVM_NONE)

  // Issue a client TX request while pause_active is expected to be set.
  tx_egress_before = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  tx_seq_h = axi_sequence_c::type_id::create("admission_tx_seq");
  // start() blocks until the request is admitted.  Launch it concurrently so
  // the following sample is genuinely inside the active PAUSE interval.
  fork
    tx_seq_h.start(env_h.axi4_stream_agent_top_h.active_agents[0].sequencer_h);
  join_none

  // While still within the pause window, no egress frame should appear.
  // This is a short, bounded negative-wait: absence within a fraction of
  // the pause window is the evidence of inhibition (F10 requires data TX
  // suppressed until pause_timerDone).
  #500ns;
  tx_egress_after = env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt;
  if (tx_egress_after == tx_egress_before)
    `uvm_info("PF_001_ADM", "PASS: data TX inhibited while pause_active", UVM_NONE)
  else
    `uvm_error("PF_001_ADM", $sformatf(
               "FAIL: %0d egress frame(s) observed while paused (before=%0d)",
               tx_egress_after - tx_egress_before, tx_egress_before))

  // Wait for the pause timer to expire and confirm resumption.
  mac_wait_utils_c::wait_for_count_at_least(tx_egress_before + 1,
      env_h.mac_rs_stream_agent_top_h.passive_agents[0].monitor_h.mon_rcvd_xtn_cnt, mac_tx_vif,
      MAC_COMPLETION_TIMEOUT_NS, timed_out);
  if (timed_out)
    `uvm_error("PF_001_ADM", "FAIL: data TX never resumed after pause expiry")
  else
    `uvm_info("PF_001_ADM", "PASS: data TX resumed after pause expiry", UVM_NONE)

  apb_read(reg_map_pkg::REG_RX_STATUS, status_data);
  if (!status_data[0])
    `uvm_info("PF_001_ADM", "PASS: pause_active cleared after timer expiry", UVM_NONE)
  else
    `uvm_error("PF_001_ADM", $sformatf(
               "FAIL: pause_active still set after expected expiry (REG_RX_STATUS=%h)",
               status_data))
endtask

task PF_001_pause_test_c::run_stimulus(uvm_phase phase);
  // Enable RX PAUSE handling (CTRL_PAUSE_BIT of REG_GLOBAL_CONTROL).
  // Keep promiscuous mode disabled: S2B's foreign unicast DA must be
  // rejected, rather than delivered as ordinary data.
  apb_write(reg_map_pkg::REG_GLOBAL_CONTROL, 32'h0000_0015);
  #200ns;  // CDC settle, same as mac_pause_rx_test_c

  run_validation_scenarios();  // S1-S4
  run_admission_scenario();    // S5
endtask

`endif  // PF_001_PAUSE_TEST_SVH
