// UVM-only native MAC/RS stream interface.  It is intentionally owned by hvl_top.
`default_nettype none
interface mac_rs_stream_if #(
    parameter int unsigned DATA_WIDTH = 512,
    parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8
) (
    input logic clk,
    input logic rst
);
  logic valid, ready;
  logic [DATA_WIDTH-1:0] data;
  logic [KEEP_WIDTH-1:0] keep;
  logic sop, eop, error, fcs_present;
  logic [$clog2(KEEP_WIDTH+1)-1:0] frame_end_byte_index;
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    input ready;
  endclocking
  clocking mon_cb @(posedge clk);
    default input #1step output #0;
    input valid, ready, data, keep, sop, eop, frame_end_byte_index, error, fcs_present;
  endclocking
  modport client_mp(
      input clk, rst, ready,
      output valid, data, keep, sop, eop, frame_end_byte_index, error, fcs_present
  );
  modport mac_mp(
      input clk, rst, valid, data, keep, sop, eop, frame_end_byte_index, error, fcs_present,
      output ready
  );
endinterface
`default_nettype wire
