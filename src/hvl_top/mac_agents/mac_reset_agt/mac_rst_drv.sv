class mac_reset_driver_c extends uvm_driver #(mac_reset_item_c);
  `uvm_component_utils(mac_reset_driver_c)

  mac_reset_agent_cfg_c cfg_h;
  virtual mac_reset_if  vif;

  extern function new(string name = "mac_reset_driver_c", uvm_component parent = null);
  extern function void build_phase(uvm_phase phase);
  extern task run_phase(uvm_phase phase);
  extern task drive_item(mac_reset_item_c item_h);
  extern task synchronize();
endclass

function mac_reset_driver_c::new(string name = "mac_reset_driver_c", uvm_component parent = null);
  super.new(name, parent);
endfunction

function void mac_reset_driver_c::build_phase(uvm_phase phase);
  super.build_phase(phase);
  if (!uvm_config_db#(mac_reset_agent_cfg_c)::get(this, "", "mac_reset_agent_cfg", cfg_h))
    `uvm_fatal("RESET_CFG", "mac_reset_agent_cfg_c was not supplied")
  vif = cfg_h.vif;
endfunction

task mac_reset_driver_c::run_phase(uvm_phase phase);
  mac_reset_item_c item_h;
  forever begin
    seq_item_port.get_next_item(item_h);
    drive_item(item_h);
    seq_item_port.item_done();
  end
endtask

task mac_reset_driver_c::drive_item(mac_reset_item_c item_h);
  synchronize();
  case (item_h.operation)
    MAC_RESET_ASSERT: begin
      vif.rst <= cfg_h.active_level;
      repeat (item_h.duration_cycles) synchronize();
    end
    MAC_RESET_DEASSERT: vif.rst <= mac_reset_utils_c::inactive_level(cfg_h.active_level);
    default: `uvm_fatal("RESET_ITEM", "Unsupported reset operation")
  endcase
  mac_txn_logger_c::write(this, "DRIVE_RESET", item_h);
  `uvm_info("RESET_DRIVE", $sformatf("%s", item_h.convert2string()),
            cfg_h.enable_logger ? UVM_MEDIUM : UVM_HIGH)
endtask

task mac_reset_driver_c::synchronize();
  if (cfg_h.synchronize_to_clock) @(vif.drv_cb);
endtask
