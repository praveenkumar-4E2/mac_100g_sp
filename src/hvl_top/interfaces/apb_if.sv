// UVM-only APB3 interface.  It is intentionally owned by hvl_top.
`default_nettype none
interface apb_if (
    input logic clk,
    input logic rst
);
  logic psel, penable, pwrite;
  logic [15:0] paddr;
  logic [31:0] pwdata, prdata;
  logic pready, pslverr;
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    input rst, prdata, pready, pslverr;
  endclocking
  clocking mon_cb @(posedge clk);
    default input #1step output #0;
    input rst, psel, penable, pwrite, paddr, pwdata, prdata, pready, pslverr;
  endclocking
  modport master_mp(
      input clk, rst, prdata, pready, pslverr,
      output psel, penable, pwrite, paddr, pwdata
  );
  modport slave_mp(
      input clk, rst, psel, penable, pwrite, paddr, pwdata,
      output prdata, pready, pslverr
  );
endinterface
`default_nettype wire
