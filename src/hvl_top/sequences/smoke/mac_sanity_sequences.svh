`ifndef MAC_SANITY_SEQUENCES_SVH
`define MAC_SANITY_SEQUENCES_SVH

//------------------------------------------------------------------------------
// Sanity-test stimulus: configurable randomized, valid frames for each MAC
// direction, built on the reusable AXI/RS sequence bases.
// TX frames omit a client FCS because the MAC TX path generates it; RX
// frames carry a valid FCS and use a broadcast destination to pass address
// filtering.
//------------------------------------------------------------------------------
class mac_sanity_tx_sequence_c extends axi_sequence_base_c;
  `uvm_object_utils(mac_sanity_tx_sequence_c)

  int unsigned num_transactions;

  extern function new(string name = "mac_sanity_tx_sequence_c");
  extern task body();
endclass

function mac_sanity_tx_sequence_c::new(string name = "mac_sanity_tx_sequence_c");
  super.new(name);
  num_transactions  = 10;
  error_injection   = 1'b0;
  payload_min       = 46;
  payload_max       = 46;
  inter_frame_delay = 1us;
endfunction

task mac_sanity_tx_sequence_c::body();
  num_tx = int'(num_transactions);
  if (num_tx == 0) `uvm_fatal("MAC_SANITY", "TX transaction count must be non-zero")
  resolve_config();
  repeat (num_tx) begin
    send_clean_item(46);  // clean, 46-byte payload, client FCS omitted
    #inter_frame_delay;
  end
endtask

class mac_sanity_rx_sequence_c extends rs_sequence_base_c;
  `uvm_object_utils(mac_sanity_rx_sequence_c)

  int unsigned num_transactions;

  extern function new(string name = "mac_sanity_rx_sequence_c");
  extern task body();
endclass

function mac_sanity_rx_sequence_c::new(string name = "mac_sanity_rx_sequence_c");
  super.new(name);
  num_transactions  = 10;
  error_injection   = 1'b0;
  broadcast_da      = 1'b1;
  payload_min       = 46;
  payload_max       = 46;
  inter_frame_delay = 1us;
endfunction

task mac_sanity_rx_sequence_c::body();
  num_frames = int'(num_transactions);
  if (num_frames == 0) `uvm_fatal("MAC_SANITY", "RX transaction count must be non-zero")
  resolve_config();
  repeat (num_frames) begin
    send_clean_frame(46);  // clean, broadcast, 46-byte payload, valid FCS
    #inter_frame_delay;
  end
endtask

`endif  // MAC_SANITY_SEQUENCES_SVH