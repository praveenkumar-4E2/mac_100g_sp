class mac_reset_agent_c extends uvm_agent;
  `uvm_component_utils(mac_reset_agent_c)

  mac_reset_sequencer_c sequencer_h;
  mac_reset_driver_c    driver_h;
  mac_reset_monitor_c   monitor_h;
  mac_reset_agent_cfg_c cfg_h;

  extern function new(string name = "mac_reset_agent_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern function void connect_phase(uvm_phase phase);
endclass

function mac_reset_agent_c::new(string name = "mac_reset_agent_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

function void mac_reset_agent_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_reset_agent_cfg_c)::get(this, "", "mac_reset_agent_cfg", cfg_h))
    `uvm_fatal("RESET_CFG", "mac_reset_agent_cfg_c was not supplied")
  cfg_h.validate();
  if (cfg_h.is_active == UVM_ACTIVE) begin
    sequencer_h = mac_reset_sequencer_c::type_id::create("sequencer_h", this);
    driver_h    = mac_reset_driver_c::type_id::create("driver_h", this);
  end
  if (cfg_h.has_monitor) monitor_h = mac_reset_monitor_c::type_id::create("monitor_h", this);
endfunction

function void mac_reset_agent_c::connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  if (cfg_h.is_active == UVM_ACTIVE) driver_h.seq_item_port.connect(sequencer_h.seq_item_export);
endfunction
