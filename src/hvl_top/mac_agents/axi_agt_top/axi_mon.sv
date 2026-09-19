/**
 * @brief MAC Master TX Monitor.
 *
 * Observes the DUT transmit interface, samples signal activity,
 * and converts it into transaction objects. The collected
 * transactions are forwarded to components such as the
 * scoreboard and coverage collector for verification.
 *
 * AXI4-Stream observe contract (see doc/interface/axi4-stream_examples.md):
 *  - Beats are captured on tvalid && tready at the clock edge.
 *  - Bytes are read lane 0..63 according to the tkeep mask.
 *  - First 14 bytes of a frame are DA + SA + ether_type.
 *  - tuser[1] (fcs_present): the last 4 bytes are the FCS.
 *  - tuser[0] (error) is mapped onto crc_error.
 *  - length_error/alignment_error have no AXI4-Stream transport.
 */
class axi_monitor_c extends uvm_monitor;
  `uvm_component_utils(axi_monitor_c)

  uvm_analysis_port #(axi_item_c) analysis_port;
  axi_item_c                      axi_item_h;

  virtual axi4_stream_if          vif;
  axi_agent_cfg_c                 cfg_h;

  // Instance-local frame counter (UTL-089), read by tests via the monitor
  // handle; replaces the former class-static counter on the config.
  int                             mon_rcvd_xtn_cnt = 0;


  extern function new(string name = "axi_monitor_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern task run_phase(uvm_phase phase);
  extern function void collect_item(byte unsigned frame_q[$], bit [7:0] tuser,
                                    int unsigned eop_byte_count);
endclass

/**
 * @brief Constructor for the MAC Master TX monitor.
 *
 * Initializes the monitor by calling the parent class
 * constructor.
 *
 * @param name Name of the monitor component.
 * @param parent Parent component in the UVM hierarchy.
 */
function axi_monitor_c::new(string name = "axi_monitor_c", uvm_component parent = null);
  super.new(name, parent);
  analysis_port = new("analysis_port", this);
endfunction

/**
 * @brief Implements the UVM build phase.
 *
 * Retrieves the agent configuration and the virtual AXI4-Stream
 * interface from the UVM configuration database.
 *
 * @param phase Current UVM build phase.
 */
function void axi_monitor_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(axi_agent_cfg_c)::get(this, "", "axi_agent_cfg", cfg_h)) begin
    `uvm_fatal("CONFIG_ERROR",
               "uvm_config_db#(axi_agent_cfg_c)::get cannot find resource axi agt config")
  end
  if (cfg_h.vif == null) begin
    `uvm_fatal("CONFIG_ERROR", "axi_agent_cfg_c::vif is null")
  end
  vif = cfg_h.vif;
endfunction

/**
 * @brief Implements the UVM run phase.
 *
 * Samples the AXI4-Stream bus beat by beat, reassembles frames,
 * and writes one transaction per completed frame. Beats seen
 * while reset is asserted are ignored.
 *
 * @param phase Current UVM run phase.
 */
task axi_monitor_c::run_phase(uvm_phase phase);
  byte unsigned frame_q[$];
  forever begin
    // mon_cb input skew #1step samples the pre-edge value — the exact
    // view the DUT's always_ff capture uses.
    @(posedge vif.mon_cb);
    if (vif.rst) begin
      frame_q.delete();
      continue;
    end
    if (vif.mon_cb.tvalid && vif.mon_cb.tready) begin
      // UTL-076: beat capture is utility-derived — the contiguous-low
      // tkeep maps to a valid-byte count (valid_bytes_from_keep), and
      // append_beat_bytes moves the low lanes onto the frame queue.
      void'(mac_hvl_utils_c::append_beat_bytes(
          frame_q,
          vif.mon_cb.tdata,
          mac_hvl_utils_c::valid_bytes_from_keep(
              vif.mon_cb.tkeep, $bits(vif.mon_cb.tkeep)
          ),
          $bits(
              vif.mon_cb.tkeep)
      ));
      if (vif.mon_cb.tlast) begin
        // UTL-124: the codec EOP byte count is the valid-lane count of the
        // final beat (tkeep), not the whole-frame byte count — the two differ
        // on every multi-beat frame.
        collect_item(frame_q, vif.mon_cb.tuser, mac_hvl_utils_c::valid_bytes_from_keep(
                     vif.mon_cb.tkeep, $bits(vif.mon_cb.tkeep)));
        frame_q.delete();
      end
    end
  end
endtask

/**
 * @brief Converts a completed frame byte stream into a transaction.
 *
 * UTL-068: all parsing is delegated to `mac_frame_codec_c::axi_to_frame`
 * (the single source of truth for AXI byte layout — big-endian header,
 * tuser[1] FCS-present, tuser[0] error). This monitor retains only its
 * handshake sampling (run_phase), the malformed-frame error report, and the
 * analysis-port publication; it then maps the canonical frame onto the item.
 *
 * @param frame_q Frame bytes in wire order.
 * @param tuser   Sideband flags of the final beat.
 * @param eop_byte_count Valid-lane count of the final beat (tkeep).
 */
function void axi_monitor_c::collect_item(byte unsigned frame_q[$], bit [7:0] tuser,
                                          int unsigned eop_byte_count);
  mac_frame_c canon;
  int nbytes = frame_q.size();

  if (mac_frame_codec_c::axi_to_frame(
          frame_q, tuser, eop_byte_count, MAC_FRAME_DIR_AXI_TX, RS_ETH_LEN_BOUND, canon
      ) != 0) begin
    `uvm_error(get_type_name(), $sformatf("axi_to_frame rejected %0d-byte frame (tuser=%02x)",
                                          nbytes, tuser))
    return;
  end

  axi_item_h            = axi_item_c::type_id::create("axi_item_h");
  axi_item_h.packet_id  = axi_item_c::next_packet_id++;
  axi_item_h.dst_addr   = canon.da;
  axi_item_h.src_addr   = canon.sa;
  axi_item_h.ether_type = canon.ether_type;
  axi_item_h.payload    = new[canon.payload.size()];
  foreach (canon.payload[i]) axi_item_h.payload[i] = canon.payload[i];
  axi_item_h.insert_fcs      = canon.fcs_present;
  axi_item_h.fcs             = canon.fcs;
  // AXI status comes from the tuser error bit (mapped by the codec onto the
  // canonical result); length/alignment are not transported on AXI.
  axi_item_h.crc_error       = (canon.result == MAC_FRAME_RESULT_CRC_ERROR);
  axi_item_h.length_error    = 1'b0;
  axi_item_h.alignment_error = 1'b0;

  mon_rcvd_xtn_cnt++;
  mac_txn_logger_c::write(this, "OBSERVE_AXI", axi_item_h);
  if (cfg_h.enable_logger) begin
    `uvm_info(get_type_name(), $sformatf("mon observed frame: %s nbytes=%0d",
                                         axi_item_h.convert2string(), nbytes), UVM_MEDIUM)
  end else begin
    `uvm_info(get_type_name(), $sformatf(
              "mon observed frame: %s nbytes=%0d", axi_item_h.convert2string(), nbytes), UVM_HIGH)
  end

  analysis_port.write(axi_item_h);
endfunction
