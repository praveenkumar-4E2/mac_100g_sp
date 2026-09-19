# Curated debug view for the pure-Verilog MAC regression.
onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -divider {Clocks and reset}
add wave sim:/mac_tb_top/mac_clk sim:/mac_tb_top/mac_rst
add wave sim:/mac_tb_top/apb_clk sim:/mac_tb_top/apb_rst

add wave -divider {APB3}
add wave sim:/mac_tb_top/apb_psel sim:/mac_tb_top/apb_penable sim:/mac_tb_top/apb_pwrite
add wave -hex sim:/mac_tb_top/apb_paddr sim:/mac_tb_top/apb_pwdata sim:/mac_tb_top/apb_prdata
add wave sim:/mac_tb_top/apb_pready sim:/mac_tb_top/apb_pslverr

add wave -divider {TX client AXI ingress}
add wave sim:/mac_tb_top/axi_tx_if/tvalid sim:/mac_tb_top/axi_tx_if/tready sim:/mac_tb_top/axi_tx_if/tlast
add wave -hex sim:/mac_tb_top/axi_tx_if/tkeep sim:/mac_tb_top/axi_tx_if/tuser
add wave -hex sim:/mac_tb_top/axi_tx_if/tdata

add wave -divider {TX native MAC RS egress}
add wave sim:/mac_tb_top/tb_egress_tx_mac_valid
add wave sim:/mac_tb_top/tb_egress_tx_mac_sop sim:/mac_tb_top/tb_egress_tx_mac_eop sim:/mac_tb_top/tb_egress_tx_mac_error
add wave -unsigned sim:/mac_tb_top/tb_egress_tx_mac_frame_end_byte_index
add wave -hex sim:/mac_tb_top/tb_egress_tx_mac_keep sim:/mac_tb_top/tb_egress_tx_mac_data

add wave -divider {RX native MAC RS ingress}
add wave sim:/mac_tb_top/tb_ingress_rx_mac_valid sim:/mac_tb_top/tb_ingress_rx_mac_ready
add wave sim:/mac_tb_top/tb_ingress_rx_mac_sop sim:/mac_tb_top/tb_ingress_rx_mac_eop sim:/mac_tb_top/tb_ingress_rx_mac_error sim:/mac_tb_top/tb_ingress_rx_mac_fcs_present
add wave -unsigned sim:/mac_tb_top/tb_ingress_rx_mac_frame_end_byte_index
add wave -hex sim:/mac_tb_top/tb_ingress_rx_mac_keep sim:/mac_tb_top/tb_ingress_rx_mac_data

add wave -divider {RX client AXI egress}
add wave sim:/mac_tb_top/axi_rx_if/tvalid sim:/mac_tb_top/axi_rx_if/tready sim:/mac_tb_top/axi_rx_if/tlast
add wave -hex sim:/mac_tb_top/axi_rx_if/tkeep sim:/mac_tb_top/axi_rx_if/tuser
add wave -hex sim:/mac_tb_top/axi_rx_if/tdata
WaveRestoreZoom {0 ns} {1000 ns}
