// UVM-only AXI4-Stream interface.  It is intentionally owned by hvl_top.
`default_nettype none
interface axi4_stream_if #(
    parameter int unsigned DATA_WIDTH = 512,
    parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8
) (
    input logic clk,
    input logic rst
);
  logic [DATA_WIDTH-1:0] tdata;
  logic [KEEP_WIDTH-1:0] tkeep;
  logic tvalid, tready, tlast;
  logic [7:0] tuser;
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    input tready;
  endclocking
  clocking mon_cb @(posedge clk);
    default input #1step output #0;
    input tdata, tkeep, tvalid, tready, tlast, tuser;
  endclocking
  modport master_mp(input clk, rst, tready, output tdata, tkeep, tvalid, tlast, tuser);
  modport slave_mp(input clk, rst, tdata, tkeep, tvalid, tlast, tuser, output tready);
endinterface
`default_nettype wire
