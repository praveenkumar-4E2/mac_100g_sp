transcript on

if {![file exists work]} {
  vlib work
}
vmap work work

vlog -sv +acc -suppress 2892 -f mac_compile.f

vsim -voptargs=+acc work.mac_tb_top +UVM_TESTNAME=mac_tx_payload_50_test_c +UVM_VERBOSITY=UVM_MEDIUM -sv_seed 1
do waves.do
