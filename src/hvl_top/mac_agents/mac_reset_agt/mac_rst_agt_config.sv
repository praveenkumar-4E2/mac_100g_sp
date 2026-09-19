class mac_reset_agent_cfg_c extends uvm_object;
  `uvm_object_utils(mac_reset_agent_cfg_c)

  uvm_active_passive_enum is_active               = UVM_ACTIVE;
  virtual mac_reset_if    vif;
  int unsigned            reset_id                = 0;
  bit                     active_level            = 1'b1;
  int unsigned            default_duration_cycles = 1;
  bit                     synchronize_to_clock    = 1'b1;
  bit                     has_monitor             = 1'b1;
  bit                     enable_logger           = 1'b0;

  extern function new(string name = "mac_reset_agent_cfg_c");
  extern function void validate();
  extern function string convert2string();
endclass

function mac_reset_agent_cfg_c::new(string name = "mac_reset_agent_cfg_c");
  super.new(name);
endfunction

function void mac_reset_agent_cfg_c::validate();
  string problems;

  if (vif == null) problems = {problems, " vif=null"};
  if (is_active == UVM_PASSIVE && !has_monitor)
    problems = {problems, " passive agent with has_monitor=0 observes nothing"};
  if (default_duration_cycles == 0) problems = {problems, " default_duration_cycles=0"};
  if (problems != "")
    `uvm_fatal("RESET_CFG", $sformatf("%s: invalid configuration:%0s", get_type_name(), problems))
endfunction

function string mac_reset_agent_cfg_c::convert2string();
  return $sformatf(
      "is_active=%0s reset_id=%0d vif=%0d active_level=%0b duration=%0d sync=%0b has_monitor=%0b",
      is_active.name(),
      reset_id,
      (vif != null),
      active_level,
      default_duration_cycles,
      synchronize_to_clock,
      has_monitor
  );
endfunction
