`default_nettype none
module cdc_dpram #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 16
) (
    input wire wr_clk,
    input wire wr_rst,
    input wire wr_valid,
    input wire [DATA_WIDTH-1:0] wr_data,
    output wire wr_ready,
    input wire rd_clk,
    input wire rd_rst,
    output wire rd_valid,
    output reg [DATA_WIDTH-1:0] rd_data,
    input wire rd_ready
);
  localparam ADDR_WIDTH = $clog2(DEPTH);
  localparam PTR_WIDTH = ADDR_WIDTH + 1;
  reg [DATA_WIDTH-1:0] memory[0:DEPTH-1];
  reg [PTR_WIDTH-1:0]
      wr_ptr_bin,
      wr_ptr_gray,
      rd_ptr_bin,
      rd_ptr_gray,
      rd_gray_wr1,
      rd_gray_wr2,
      wr_gray_rd1,
      wr_gray_rd2;
  reg full, empty;
  wire [PTR_WIDTH-1:0] wr_ptr_bin_next = wr_ptr_bin + (wr_valid && wr_ready);
  wire [PTR_WIDTH-1:0] rd_ptr_bin_next = rd_ptr_bin + (rd_valid && rd_ready);
  wire [PTR_WIDTH-1:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
  wire [PTR_WIDTH-1:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;
  assign wr_ready = !full;
  assign rd_valid = !empty;
  always @(posedge wr_clk) begin
    if (wr_rst) begin
      wr_ptr_bin <= {PTR_WIDTH{1'b0}};
      wr_ptr_gray <= {PTR_WIDTH{1'b0}};
      rd_gray_wr1 <= {PTR_WIDTH{1'b0}};
      rd_gray_wr2 <= {PTR_WIDTH{1'b0}};
      full <= 1'b0;
    end else begin
      rd_gray_wr1 <= rd_ptr_gray;
      rd_gray_wr2 <= rd_gray_wr1;
      if (wr_valid && wr_ready) memory[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
      wr_ptr_bin <= wr_ptr_bin_next;
      wr_ptr_gray <= wr_ptr_gray_next;
      full <=
          (wr_ptr_gray_next == {~rd_gray_wr2[PTR_WIDTH-1:PTR_WIDTH-2], rd_gray_wr2[PTR_WIDTH-3:0]});
    end
  end
  always @(posedge rd_clk) begin
    if (rd_rst) begin
      rd_ptr_bin <= {PTR_WIDTH{1'b0}};
      rd_ptr_gray <= {PTR_WIDTH{1'b0}};
      wr_gray_rd1 <= {PTR_WIDTH{1'b0}};
      wr_gray_rd2 <= {PTR_WIDTH{1'b0}};
      empty <= 1'b1;
      rd_data <= {DATA_WIDTH{1'b0}};
    end else begin
      wr_gray_rd1 <= wr_ptr_gray;
      wr_gray_rd2 <= wr_gray_rd1;
      if (rd_valid) rd_data <= memory[rd_ptr_bin[ADDR_WIDTH-1:0]];
      rd_ptr_bin <= rd_ptr_bin_next;
      rd_ptr_gray <= rd_ptr_gray_next;
      empty <= (rd_ptr_gray_next == wr_gray_rd2);
    end
  end
endmodule
`default_nettype wire
