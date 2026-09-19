class mac_reset_monitor_c extends uvm_monitor;
  `uvm_component_utils(mac_reset_monitor_c)

  uvm_analysis_port #(mac_reset_item_c) analysis_port;
  mac_reset_agent_cfg_c                 cfg_h;
  virtual mac_reset_if                  vif;

  extern function new(string name = "mac_reset_monitor_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern task run_phase(uvm_phase phase);
  extern function void publish_event(bit is_asserted);
endclass

function mac_reset_monitor_c::new(string name = "mac_reset_monitor_c", uvm_component parent = null);
  super.new(name, parent);
  analysis_port = new("analysis_port", this);
endfunction

function void mac_reset_monitor_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_reset_agent_cfg_c)::get(this, "", "mac_reset_agent_cfg", cfg_h))
    `uvm_fatal("RESET_CFG", "mac_reset_agent_cfg_c was not supplied")
  vif = cfg_h.vif;
endfunction

task mac_reset_monitor_c::run_phase(uvm_phase phase);
  bit previous_value;
  bit current_value;

  // Treat the initial sampled state as a transition too. This preserves an
  // observable boot assertion when the harness initializes reset before UVM
  // run_phase begins, while also working for a passive observer.
  previous_value = ~cfg_h.active_level;
  forever begin
    @(vif.mon_cb);
    current_value = vif.mon_cb.rst;
    if (current_value != previous_value)
      publish_event(mac_reset_utils_c::is_asserted(current_value, cfg_h.active_level));
    previous_value = current_value;
  end
endtask

function void mac_reset_monitor_c::publish_event(bit is_asserted);
  mac_reset_item_c item_h;
  item_h = mac_reset_item_c::type_id::create("reset_event_item_h");
  item_h.operation = is_asserted ? MAC_RESET_ASSERT : MAC_RESET_DEASSERT;
  item_h.reset_id = cfg_h.reset_id;
  item_h.event_time = $time;
  mac_txn_logger_c::write(this, "OBSERVE_RESET", item_h);
  analysis_port.write(item_h);
  `uvm_info("RESET_EVENT", $sformatf("%s", item_h.convert2string()),
            cfg_h.enable_logger ? UVM_MEDIUM : UVM_HIGH)
endfunction
