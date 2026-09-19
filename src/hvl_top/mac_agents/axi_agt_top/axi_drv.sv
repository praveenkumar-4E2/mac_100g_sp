/**
 * @brief MAC Master TX Driver.
 *
 * Receives transaction objects from the sequencer and drives
 * them onto the DUT transmit interface. The driver is primarily
 * active during the run_phase.
 *
 * AXI4-Stream drive contract (see doc/interface/axi4-stream_examples.md):
 *  - 64-byte beats, lane-0 aligned; stream carries DA + SA + ET + payload.
 *  - tkeep is a contiguous-ones prefix mask, all-ones on interior beats.
 *  - tlast is asserted only on the final beat.
 *  - tuser[1] (fcs_present): client supplies the FCS in the last 4 bytes.
 *  - tuser[0] (error): frame is flagged as bad.
 *  - A stalled beat (tready low) must stay unchanged.
 */
class axi_driver_c extends uvm_driver #(axi_item_c);
  `uvm_component_utils(axi_driver_c)

  virtual axi4_stream_if vif;
  axi_agent_cfg_c        cfg_h;

  // Instance-local frame counter (UTL-088), read by tests via the driver
  // handle; replaces the former class-static counter on the config.
  int                    drv_data_sent_cnt = 0;

  extern function new(string name = "axi_driver_c", uvm_component parent = null);

  extern function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern task reset_signals();
  extern task drive_frame(axi_item_c item);
  extern task send_beat(logic [511:0] tdata, logic [63:0] tkeep, bit tlast, bit [7:0] tuser);
endclass

/**
 * @brief Constructor for the MAC Master TX driver.
 *
 * Initializes the driver by calling the parent class
 * constructor.
 *
 * @param name Name of the driver component.
 * @param parent Parent component in the UVM hierarchy.
 */
function axi_driver_c::new(string name = "axi_driver_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Retrieves the agent configuration and the virtual AXI4-Stream
 * interface from the UVM configuration database.
 *
 * @param phase Current UVM build phase.
 */
function void axi_driver_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(axi_agent_cfg_c)::get(this, "", "axi_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR",
               "uvm_config_db#(axi_agent_cfg_c)::get cannot find resource axi agt config")
  end
  if (cfg_h.vif == null) begin
    `uvm_fatal("CONFIG_ERROR", "axi_agent_cfg_c::vif is null")
  end
  // UTL-106: in DUT-facing TX mode the DUT owns tready on axi_tx_vif; the
  // TB must never drive it. Self-generated backpressure is only valid in
  // agent-only harnesses, so reject the setting here instead of ever
  // asserting tready from the source driver.
  if (cfg_h.generate_backpressure)
    `uvm_fatal("CONFIG_ERROR", $sformatf(
               "axi_agent_cfg_c::generate_backpressure=1 is not allowed for the DUT-facing AXI TX source driver: it would drive the DUT-owned tready; disable generate_backpressure in DUT-facing mode"
               ))
  vif = cfg_h.vif;
endfunction

/**
 * @brief Implements the UVM run phase.
 *
 * Waits for reset to deassert, then continuously pulls
 * transactions from the sequencer and drives them as
 * AXI4-Stream frames.
 *
 * @param phase Current UVM run phase.
 */
task axi_driver_c::run_phase(uvm_phase phase);
  reset_signals();
  forever begin
    seq_item_port.get_next_item(req);
    drive_frame(req);
    seq_item_port.item_done();
  end
endtask

/**
 * @brief Drives all interface signals to their idle state.
 *
 * Called once before the drive loop starts; all signals are
 * deasserted so the DUT sees an idle bus.
 */
task axi_driver_c::reset_signals();
  vif.tvalid <= 1'b0;
  vif.tdata  <= '0;
  vif.tkeep  <= '0;
  vif.tlast  <= 1'b0;
  vif.tuser  <= '0;
endtask

/**
 * @brief Drives one MAC frame as a sequence of AXI4-Stream beats.
 *
 * UTL-072: the wire frame is built with the shared utilities (big-endian
 * header via encode_be48/encode_be16, LSB-first FCS via
 * fcs_to_wire_bytes), and the beat geometry is utility-derived: the beat
 * count via ceil_div, the contiguous-low tkeep via keep_from_valid_bytes,
 * and the beat's lane bytes via extract_beat_bytes. Handshake timing is
 * unchanged (send_beat).
 *
 * Packs the frame bytes (DA, SA, ether_type, payload and, when insert_fcs
 * is set, the FCS) into 64-byte beats, starting at lane 0. tuser[1]
 * (fcs_present) mirrors insert_fcs, tuser[0] (error) mirrors crc_error.
 * length_error and alignment_error have no AXI4-Stream transport and are
 * currently ignored.
 *
 * @param item Transaction to drive.
 */
task axi_driver_c::drive_frame(axi_item_c item);
  byte unsigned         frame_q     [$];
  bit           [511:0] tdata;
  bit           [ 63:0] tkeep;
  bit           [  7:0] tuser;
  int                   frame_size;
  int                   beats;
  int                   valid_bytes;

  mac_txn_logger_c::write(this, "DRIVE_AXI", item);

  // Ethernet header (DA, SA, ether_type) big-endian, then payload, then the
  // client-supplied FCS LSB-first (fcs[7:0] first, the byte order the DUT
  // TX path expects from tx_client_capture's fcs_tail window).
  void'(mac_hvl_utils_c::encode_be48(frame_q, item.dst_addr));
  void'(mac_hvl_utils_c::encode_be48(frame_q, item.src_addr));
  void'(mac_hvl_utils_c::encode_be16(frame_q, item.ether_type));
  foreach (item.payload[i]) frame_q.push_back(item.payload[i]);
  if (item.insert_fcs) void'(mac_hvl_utils_c::fcs_to_wire_bytes(frame_q, item.fcs));

  frame_size = frame_q.size();
  tuser = {6'b0, item.insert_fcs, item.crc_error};

  beats = mac_hvl_utils_c::ceil_div(frame_size, 64);
  for (int b = 0; b < beats; b++) begin
    valid_bytes = (frame_size - b * 64 >= 64) ? 64 : frame_size - b * 64;
    tkeep = mac_hvl_utils_c::keep_from_valid_bytes(valid_bytes, 64);
    void'(mac_hvl_utils_c::extract_beat_bytes(frame_q, tdata, valid_bytes, 64));
    send_beat(tdata, tkeep, (b == beats - 1), tuser);
  end

  drv_data_sent_cnt++;
  if (cfg_h.enable_logger) begin
    `uvm_info(get_type_name(), $sformatf("drv sent frame: %s beats=%0d bytes=%0d",
                                         item.convert2string(), beats, frame_size), UVM_MEDIUM)
  end else begin
    `uvm_info(get_type_name(), $sformatf(
              "drv sent frame: %s beats=%0d bytes=%0d", item.convert2string(), beats, frame_size),
              UVM_HIGH)
  end
endtask

/**
 * @brief Drives a single AXI4-Stream beat with full handshaking.
 *
 * Writes the beat with raw nonblocking assignments (visible to the
 * DUT at the next posedge), then holds until tready is sampled high.
 * drv_cb.tready is sampled with the #1step input skew — the pre-edge
 * value, the exact view the DUT's always_ff capture uses — so the
 * driver and the DUT always agree on the handshake edge.
 *
 * @param tdata 512-bit beat payload.
 * @param tkeep 64-bit byte-enable prefix mask.
 * @param tlast End-of-frame marker.
 * @param tuser Side-note flags (error, fcs_present).
 */
task axi_driver_c::send_beat(logic [511:0] tdata, logic [63:0] tkeep, bit tlast, bit [7:0] tuser);
  vif.tvalid <= 1'b1;
  vif.tdata  <= tdata;
  vif.tkeep  <= tkeep;
  vif.tlast  <= tlast;
  vif.tuser  <= tuser;
  // UTL-106: no self-generated backpressure here — tready is DUT-owned on
  // the DUT-facing AXI TX interface and the TB must not drive it. The
  // generate_backpressure setting is rejected in build_phase.
  // Sample the raw interface signal on the transfer edge.  drv_cb has a
  // #1step input skew, so using drv_cb.tready here observes the prior-cycle
  // value and can advance the driver without a real DUT handshake.
  do begin
    // Wait on the raw clock edge, not the clocking-block posedge event:
    // drv_cb applies a #1step input skew whose event fires one step before
    // the real edge, so a beat driven from an item that arrives inside that
    // pre-edge window can have its first wait return in the same timestep,
    // collapsing the handshake to zero cycles and dropping the beat.
    @(posedge vif.clk);
  end while (!vif.tready);
  vif.tvalid <= 1'b0;
endtask
