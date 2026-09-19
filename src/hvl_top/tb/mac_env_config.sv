class mac_env_cfg_c extends uvm_object;
  `uvm_object_utils(mac_env_cfg_c)

  bit                   has_function_coverage              = 0;

  bit                   has_scoreboard                     = 1;

  // Scoreboard policy.  The default preserves the existing end-to-end
  // packet checks and strict FIFO ordering; tests can narrow checking for a
  // feature-focused scenario without changing checker source.
  bit                   scoreboard_enable_tx_check         = 1;
  bit                   scoreboard_enable_rx_check         = 1;
  bit                   scoreboard_check_addresses         = 1;
  bit                   scoreboard_check_ether_type        = 1;
  bit                   scoreboard_check_payload           = 1;
  bit                   scoreboard_check_fcs               = 1;
  bit                   scoreboard_check_error_flags       = 1;
  // Zero disables elapsed-time checking.  This is the compatibility default
  // until every test has an agreed end-of-traffic timeout budget.
  time                  scoreboard_unmatched_timeout_ns    = 0;
  // An asserted reset starts a new comparison epoch.  Queued traffic from
  // the prior epoch is deliberately flushed and counted, never compared
  // across reset.
  bit                   scoreboard_flush_on_reset          = 1;

  bit                   has_protocol_checkers              = 1;

  // Shared predictor/checker limits.  Tests may override these for a
  // different MAC profile without changing component code.
  int unsigned          min_payload_bytes                  = 46;
  int unsigned          max_payload_bytes                  = MAC_SUPER_JUMBO_PAYLOAD_BYTES;
  // Frame limits are environment policy, never agent literals.  The default
  // follows the RTL storage limit; profiles may narrow it.
  int unsigned          max_frame_octets                   = MAC_SUPER_JUMBO_FRAME_OCTETS;

  bit                   has_axi_agents                     = 1;

  bit                   has_rs_agents                      = 1;

  bit                   has_apb_agents                     = 1;

  bit                   has_reset_agents                   = 1;

  bit                   has_virtual_sequencer              = 1;

  axi_agent_cfg_c       axi_active_agent_cfgs          [];
  axi_agent_cfg_c       axi_passive_agent_cfgs         [];

  rs_agent_cfg_c        rs_active_agent_cfgs           [];
  rs_agent_cfg_c        rs_passive_agent_cfgs          [];
  mac_reset_agent_cfg_c reset_agent_cfgs               [];

  apb_agent_cfg_c       apb_active_agent_cfgs          [];
  apb_agent_cfg_c       apb_passive_agent_cfgs         [];


  int                   num_axi_active_agents              = 1;
  int                   num_axi_passive_agents             = 1;

  int                   num_rs_active_agents               = 1;
  int                   num_rs_passive_agents              = 1;

  int                   num_apb_active_agents              = 1;
  int                   num_apb_passive_agents             = 0;

  int                   num_duts                           = 1;
  uvm_reg_block         ral_h;
  uvm_reg_adapter       ral_adapter_h;
  int                   num_reset_agents                   = 0;





  extern function new(string name = "mac_env_cfg_c");
  extern function void validate();

endclass


function mac_env_cfg_c::new(string name = "mac_env_cfg_c");
  super.new(name);
endfunction

/**
 * @brief Validates the environment configuration before child components
 *        are created (UTL-084).
 *
 * Checks that every agent-count field has a matching non-empty config
 * array of exactly the declared size, that no array entry is null, and
 * that each entry's declared identity (is_active) matches the array it
 * lives in. All problems are collected and reported in a single
 * actionable fatal message.
 */
function void mac_env_cfg_c::validate();
  string problems;

  if (min_payload_bytes > max_payload_bytes)
    problems = {
      problems,
      $sformatf(
          " min_payload_bytes=%0d > max_payload_bytes=%0d", min_payload_bytes, max_payload_bytes
      )
    };
  if (max_frame_octets == 0 || max_frame_octets > MAC_SUPER_JUMBO_FRAME_OCTETS)
    problems = {
      problems, $sformatf(" max_frame_octets=%0d outside RTL range 1..%0d", max_frame_octets,
                          MAC_SUPER_JUMBO_FRAME_OCTETS)
    };
  if (scoreboard_unmatched_timeout_ns < 0)
    problems = {
      problems, $sformatf(" scoreboard_unmatched_timeout_ns=%0t<0", scoreboard_unmatched_timeout_ns)
    };

  if (num_axi_active_agents < 0)
    problems = {problems, $sformatf(" num_axi_active_agents=%0d<0", num_axi_active_agents)};
  if (num_axi_passive_agents < 0)
    problems = {problems, $sformatf(" num_axi_passive_agents=%0d<0", num_axi_passive_agents)};
  if (num_rs_active_agents < 0)
    problems = {problems, $sformatf(" num_rs_active_agents=%0d<0", num_rs_active_agents)};
  if (num_rs_passive_agents < 0)
    problems = {problems, $sformatf(" num_rs_passive_agents=%0d<0", num_rs_passive_agents)};
  if (num_apb_active_agents < 0)
    problems = {problems, $sformatf(" num_apb_active_agents=%0d<0", num_apb_active_agents)};
  if (num_apb_passive_agents < 0)
    problems = {problems, $sformatf(" num_apb_passive_agents=%0d<0", num_apb_passive_agents)};
  if (num_reset_agents < 0)
    problems = {problems, $sformatf(" num_reset_agents=%0d<0", num_reset_agents)};

  // A dynamic array cannot be compared with null; a never-allocated
  // array reports size() == 0 in Questa, so a size/count mismatch below
  // also catches the null case.
  if (axi_active_agent_cfgs.size() != num_axi_active_agents)
    problems = {
      problems,
      $sformatf(
          " axi_active size=%0d != num=%0d", axi_active_agent_cfgs.size(), num_axi_active_agents
      )
    };

  if (axi_passive_agent_cfgs.size() != num_axi_passive_agents)
    problems = {
      problems,
      $sformatf(
          " axi_passive size=%0d != num=%0d", axi_passive_agent_cfgs.size(), num_axi_passive_agents
      )
    };

  if (rs_active_agent_cfgs.size() != num_rs_active_agents)
    problems = {
      problems,
      $sformatf(" rs_active size=%0d != num=%0d", rs_active_agent_cfgs.size(), num_rs_active_agents)
    };

  if (rs_passive_agent_cfgs.size() != num_rs_passive_agents)
    problems = {
      problems,
      $sformatf(
          " rs_passive size=%0d != num=%0d", rs_passive_agent_cfgs.size(), num_rs_passive_agents
      )
    };
  if (apb_active_agent_cfgs.size() != num_apb_active_agents)
    problems = {
      problems,
      $sformatf(
          " apb_active size=%0d != num=%0d", apb_active_agent_cfgs.size(), num_apb_active_agents
      )
    };
  if (apb_passive_agent_cfgs.size() != num_apb_passive_agents)
    problems = {
      problems,
      $sformatf(
          " apb_passive size=%0d != num=%0d", apb_passive_agent_cfgs.size(), num_apb_passive_agents
      )
    };
  if (reset_agent_cfgs.size() != num_reset_agents)
    problems = {
      problems, $sformatf(" reset size=%0d != num=%0d", reset_agent_cfgs.size(), num_reset_agents)
    };

  foreach (axi_active_agent_cfgs[i]) begin
    if (axi_active_agent_cfgs[i] == null)
      problems = {problems, $sformatf(" axi_active_cfgs[%0d]=null", i)};
    else if (axi_active_agent_cfgs[i].is_active != UVM_ACTIVE)
      problems = {
        problems,
        $sformatf(" axi_active_cfgs[%0d] is %0s", i, axi_active_agent_cfgs[i].is_active.name())
      };
  end
  foreach (axi_passive_agent_cfgs[i]) begin
    if (axi_passive_agent_cfgs[i] == null)
      problems = {problems, $sformatf(" axi_passive_cfgs[%0d]=null", i)};
    else if (axi_passive_agent_cfgs[i].is_active != UVM_PASSIVE)
      problems = {
        problems,
        $sformatf(" axi_passive_cfgs[%0d] is %0s", i, axi_passive_agent_cfgs[i].is_active.name())
      };
  end
  foreach (rs_active_agent_cfgs[i]) begin
    if (rs_active_agent_cfgs[i] == null)
      problems = {problems, $sformatf(" rs_active_cfgs[%0d]=null", i)};
    else if (rs_active_agent_cfgs[i].is_active != UVM_ACTIVE)
      problems = {
        problems,
        $sformatf(" rs_active_cfgs[%0d] is %0s", i, rs_active_agent_cfgs[i].is_active.name())
      };
  end
  foreach (rs_passive_agent_cfgs[i]) begin
    if (rs_passive_agent_cfgs[i] == null)
      problems = {problems, $sformatf(" rs_passive_cfgs[%0d]=null", i)};
    else if (rs_passive_agent_cfgs[i].is_active != UVM_PASSIVE)
      problems = {
        problems,
        $sformatf(" rs_passive_cfgs[%0d] is %0s", i, rs_passive_agent_cfgs[i].is_active.name())
      };
  end
  foreach (reset_agent_cfgs[i]) begin
    if (reset_agent_cfgs[i] == null) problems = {problems, $sformatf(" reset_cfgs[%0d]=null", i)};
  end
  foreach (apb_active_agent_cfgs[i]) begin
    if (apb_active_agent_cfgs[i] == null)
      problems = {problems, $sformatf(" apb_active_cfgs[%0d]=null", i)};
    else if (apb_active_agent_cfgs[i].m_is_active != UVM_ACTIVE)
      problems = {
        problems,
        $sformatf(" apb_active_cfgs[%0d] is %0s", i, apb_active_agent_cfgs[i].m_is_active.name())
      };
  end
  foreach (apb_passive_agent_cfgs[i]) begin
    if (apb_passive_agent_cfgs[i] == null)
      problems = {problems, $sformatf(" apb_passive_cfgs[%0d]=null", i)};
    else if (apb_passive_agent_cfgs[i].m_is_active != UVM_PASSIVE)
      problems = {
        problems,
        $sformatf(" apb_passive_cfgs[%0d] is %0s", i, apb_passive_agent_cfgs[i].m_is_active.name())
      };
  end

  if (problems != "")
    `uvm_fatal(get_type_name(), $sformatf("%s: invalid configuration:%0s", get_type_name(), problems
               ))
endfunction
