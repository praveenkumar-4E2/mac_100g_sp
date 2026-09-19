class mac_reset_sequencer_c extends uvm_sequencer #(mac_reset_item_c);
  `uvm_component_utils(mac_reset_sequencer_c)

  mac_reset_agent_cfg_c cfg_h;

  extern function new(string name = "mac_reset_sequencer_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
endclass

function mac_reset_sequencer_c::new(string name = "mac_reset_sequencer_c",
                                    uvm_component parent = null);
  super.new(name, parent);
endfunction

function void mac_reset_sequencer_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_reset_agent_cfg_c)::get(this, "", "mac_reset_agent_cfg", cfg_h))
    `uvm_fatal("RESET_CFG", "mac_reset_agent_cfg_c was not supplied")
endfunction
