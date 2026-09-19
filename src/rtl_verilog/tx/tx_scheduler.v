`default_nettype none
module tx_scheduler (
    input  wire start,
    input  wire request_ready,
    input  wire ipg_done,
    output wire accept_start,
    output wire request_ready_out
);
  assign accept_start = start && request_ready && ipg_done;
  assign request_ready_out = request_ready && ipg_done;
endmodule
`default_nettype wire
