/**
 * @brief Reusable AXI4-Stream (client-side) sequence base.
 *
 * Owns the shared mechanics of every AXI master TX sequence:
 *  - agent-config lookup from the starting sequencer (resolve_config);
 *  - configurable traffic knobs (transaction count, payload bounds, error
 *    injection, optional broadcast DA, optional inter-frame delay);
 *  - deterministic helper tasks (send_clean_item) that take explicit
 *    arguments so any test, virtual sequence, or subclass can reuse them.
 *
 * The knobs are `rand` with -1 sentinels: resolve_config() replaces the
 * sentinels with the agent-config defaults, while values set by the caller
 * are preserved — the body() never re-randomizes the knobs, so caller
 * assignments survive start(). Deterministic helpers that do not need the
 * config (send_clean_item with an explicit length) are safe to call without
 * resolve_config(); helpers that randomize payload size resolve sentinel
 * bounds to the IEEE 802.3 legal range on their own.
 */
class axi_sequence_base_c extends uvm_sequence #(axi_item_c);
  `uvm_object_utils(axi_sequence_base_c)

  // Traffic knobs. -1 sentinels resolve to the agent config; caller-set
  // values are never overwritten by the default body().
  rand int         num_tx          = -1;  // <0 => cfg.num_tx_default
  rand int         payload_min     = -1;  // <0 => cfg.min_payload_len
  rand int         payload_max     = -1;  // <0 => cfg.max_payload_len
  rand bit         error_injection = 1'b0;
  rand bit         broadcast_da    = 1'b0;  // TX client frames are not address-filtered

  // Optional inter-frame delay inserted by the default body() (0 = none;
  // the AXI driver owns handshaking on the stream).
  time             inter_frame_delay = 0;

  // Resolved agent config (see resolve_config()).
  axi_agent_cfg_c  cfg_h;
  bit              cfg_resolved = 1'b0;
  // Sequence-local progress, available to a calling virtual sequence after
  // start() returns without reaching into the AXI driver.
  int unsigned     items_sent = 0;

  constraint c_knob_bounds {
    num_tx inside {[-1 : 100]};
    payload_min inside {[-1 : MAC_SUPER_JUMBO_PAYLOAD_BYTES]};
    payload_max inside {[-1 : MAC_SUPER_JUMBO_PAYLOAD_BYTES]};
    (payload_min >= 0) -> (payload_max >= payload_min);
  }

  extern function new(string name = "axi_sequence_base_c");
  extern task pre_body();
  extern task resolve_config();
  extern task body();
  extern function void validate_knobs();
  extern function axi_item_c new_random_item();
  extern task do_axi_item(axi_item_c item);
  extern task send_random_items(int count = -1);
  extern task send_clean_item(int pkt_len = -1,
                              bit [47:0] da = 48'hFF_FF_FF_FF_FF_FF,
                              bit fcs_on = 1'b0);
endclass

/**
 * @brief Constructor for the AXI sequence base.
 *
 * @param name Name of the sequence object.
 */
function axi_sequence_base_c::new(string name = "axi_sequence_base_c");
  super.new(name);
endfunction

// Runs for both the base sequence and subclasses that override body().
task axi_sequence_base_c::pre_body();
  items_sent = 0;
endtask

/**
 * @brief Resolves the agent config and fills knob sentinels.
 *
 * Looks up the axi_agent_cfg published for the agent owning the starting
 * sequencer (never a null-context wildcard), then replaces negative knobs
 * with the config defaults. Runs once; safe to call repeatedly.
 */
task axi_sequence_base_c::resolve_config();
  if (cfg_resolved) return;
  if (!uvm_config_db#(axi_agent_cfg_c)::get(m_sequencer, "", "axi_agent_cfg", cfg_h)) begin
    `uvm_fatal(get_type_name(),
               "uvm_config_db#(axi_agent_cfg_c)::get cannot find resource axi agt config")
  end
  if (num_tx < 0) num_tx = cfg_h.num_tx_default;
  if (payload_min < 0) payload_min = cfg_h.min_payload_len;
  if (payload_max < 0) payload_max = cfg_h.max_payload_len;
  validate_knobs();
  cfg_resolved = 1'b1;
endtask

// Report invalid caller configuration before transaction randomization.
function void axi_sequence_base_c::validate_knobs();
  if (num_tx < 0 || num_tx > 100 || payload_min < 0 || payload_max < payload_min ||
      payload_max > MAC_SUPER_JUMBO_PAYLOAD_BYTES)
    `uvm_fatal(get_type_name(), $sformatf(
               "Invalid AXI sequence knobs: num_tx=%0d payload_min=%0d payload_max=%0d",
               num_tx, payload_min, payload_max))
endfunction

/**
 * @brief Default behavior: drive num_tx randomized items.
 *
 * Honors the knobs: payload bounds, error-injection enable, and broadcast
 * DA are applied per item; an optional inter-frame delay is inserted.
 * Subclasses override body() to compose the deterministic helpers instead.
 */
task axi_sequence_base_c::body();
  resolve_config();
  send_random_items();
endtask

// Drives a caller-selected randomized burst, or num_tx when omitted.
task axi_sequence_base_c::send_random_items(int count = -1);
  int actual_count;
  actual_count = (count < 0) ? num_tx : count;
  if (actual_count < 0 || actual_count > 100)
    `uvm_fatal(get_type_name(), $sformatf("Invalid AXI item count: %0d", actual_count))
  repeat (actual_count) begin
    axi_item_c item;
    item = new_random_item();
    do_axi_item(item);
    if (inter_frame_delay > 0) #inter_frame_delay;
  end
endtask

/**
 * @brief Creates and randomizes a single item honoring the knobs.
 *
 * When error_injection is disabled, the item is clean (no CRC/length/
 * alignment errors). Payload size is softly bounded by payload_min/max, and
 * broadcast_da fixes the destination to the broadcast address when set.
 * The client-side FCS policy is left to the item's own distribution.
 *
 * @return Fully randomized axi_item_c (not yet sent).
 */
function axi_item_c axi_sequence_base_c::new_random_item();
  axi_item_c item;
  if (payload_min < 0) payload_min = 46;
  if (payload_max < 0) payload_max = 1500;
  item = axi_item_c::type_id::create("item");
  if (!item.randomize() with {
        if (error_injection == 1'b0) {
          crc_error == 0;
          length_error == 0;
          alignment_error == 0;
        }
        payload.size() inside {[payload_min : payload_max]};
        soft ether_type > 16'h0600;
        if (broadcast_da) dst_addr == 48'hFF_FF_FF_FF_FF_FF;
      }) begin
    `uvm_fatal(get_type_name(), "Randomization of axi_item_c failed")
  end
  return item;
endfunction

/**
 * @brief Drives one item through the sequencer to the AXI driver.
 *
 * @param item Item to send.
 */
task axi_sequence_base_c::do_axi_item(axi_item_c item);
  if (item == null) `uvm_fatal(get_type_name(), "Cannot drive a null AXI item")
  start_item(item);
  finish_item(item);
  items_sent++;
endtask

/**
 * @brief Builds and drives one deterministic clean item.
 *
 * The item is guaranteed valid (no errors) with an explicit destination and
 * optional payload length. When pkt_len < 0 the payload is randomized within
 * the knob bounds. By default the client omits an FCS (insert_fcs off) so
 * the MAC TX path generates it.
 *
 * @param pkt_len Fixed payload length, or -1 to randomize within bounds.
 * @param da      Destination MAC address.
 * @param fcs_on  Whether the client item carries an FCS.
 */
task axi_sequence_base_c::send_clean_item(int pkt_len = -1,
                                          bit [47:0] da = 48'hFF_FF_FF_FF_FF_FF,
                                          bit fcs_on = 1'b0);
  axi_item_c item;
  if (payload_min < 0) payload_min = 46;
  if (payload_max < 0) payload_max = 1500;
  item = axi_item_c::type_id::create("item");
  if (!item.randomize() with {
        dst_addr == da;
        crc_error == 0;
        length_error == 0;
        alignment_error == 0;
        insert_fcs == fcs_on;
        soft ether_type > 16'h0600;
        if (pkt_len >= 0) payload.size() == pkt_len;
        else payload.size() inside {[payload_min : payload_max]};
      }) begin
    `uvm_fatal(get_type_name(), "Randomization of clean AXI item failed")
  end
  do_axi_item(item);
endtask
