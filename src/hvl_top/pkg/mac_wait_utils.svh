/**
 * @brief HVL façade-owned bounded wait API (mac_test_pkg member).
 *
 * `mac_wait_utils_c` is a stateless collection of static wait tasks that
 * replace open-ended polling (`forever ... #1ns`), fixed time-step settle
 * delays (`#1us`), and fragile iteration-counted timeouts (`repeat (5000)
 * #100ns`). Every wait is bounded by an absolute simulation-time timeout and
 * reports its outcome through an output flag, so a stalled DUT fails the
 * calling test instead of hanging the run.
 *
 * Contract (per skills/utilities/proposal.md, W4):
 *  - pure utility: no hierarchy access, no global counters, no
 *    uvm_config_db access;
 *  - the tasks never issue uvm_error/uvm_fatal themselves — the caller
 *    chooses the report context and severity from the `timed_out` flag;
 *  - clock/event-based sampling when a clock source (`virtual mac_rs_stream_if`) is
 *    supplied, #1ns steps otherwise; all waits are bounded by timeout_ns.
 *
 * This file is a member of mac_test_pkg (text-included), so it must NOT
 * declare `package`/`endpackage`.
 */
`ifndef MAC_WAIT_UTILS_SVH
`define MAC_WAIT_UTILS_SVH

class mac_wait_utils_c;
  protected
  function new();
  endfunction

  // Returns the time elapsed since `start_ts`, in a form that never
  // underflows for a wait started inside the current run.
  protected static function time elapsed_since(time start_ts);
    return ($time >= start_ts) ? ($time - start_ts) : $time;
  endfunction

  //------------------------------------------------------------------------
  // Bounded reset / configuration-completion wait (UTL-101/102).
  //
  // Waits until cfg_h.config_done (published by mac_tb_top once the APB
  // bootstrap completes) is asserted, or until timeout_ns elapses. On
  // timeout, timed_out is set and the task returns; otherwise timed_out is
  // cleared. cfg_h must not be null.
  //------------------------------------------------------------------------
  static task wait_for_config_done(mac_tb_cfg_c cfg_h, input time timeout_ns, output bit timed_out);
    time start_ts;
    start_ts  = $time;
    timed_out = 1'b0;
    forever begin
      if (cfg_h.config_done) break;
      if (elapsed_since(start_ts) >= timeout_ns) begin
        timed_out = 1'b1;
        break;
      end
      #1ns;
    end
  endtask

  //------------------------------------------------------------------------
  // Bounded count-arrival wait (UTL-103/104/105).
  //
  // Waits until the instance-local counter `count` (e.g. a driver or
  // monitor frame count) reaches `target`, or until timeout_ns elapses.
  // Sampling is clock/event-based on the supplied MAC/RS stream clock edge when
  // `vif` is non-null (UTL-105) and falls back to #1ns steps otherwise.
  // `count` is passed by reference so the live monitor/driver field is
  // observed; its type matches the counters in the agents (int).
  //------------------------------------------------------------------------
  static task wait_for_count_at_least(input int unsigned target, ref int count,
                                      input virtual mac_rs_stream_if vif, input time timeout_ns,
                                      output bit timed_out);
    time start_ts;
    start_ts  = $time;
    timed_out = 1'b0;
    forever begin
      if (count >= int'(target)) break;
      if (elapsed_since(start_ts) >= timeout_ns) begin
        timed_out = 1'b1;
        break;
      end
      if (vif == null) #1ns;
      else @(posedge vif.clk);
    end
  endtask

  // AXI4-Stream counterpart of wait_for_count_at_least.  Keep interface
  // types explicit so tests can use clock-based waits on either MAC path.
  static task wait_for_axi_count_at_least(input int unsigned target, ref int count,
                                          input virtual axi4_stream_if vif, input time timeout_ns,
                                          output bit timed_out);
    time start_ts;
    start_ts  = $time;
    timed_out = 1'b0;
    forever begin
      if (count >= int'(target)) break;
      if (elapsed_since(start_ts) >= timeout_ns) begin
        timed_out = 1'b1;
        break;
      end
      if (vif == null) #1ns;
      else @(posedge vif.clk);
    end
  endtask

  //------------------------------------------------------------------------
  // Bounded queue-drain wait (UTL-103).
  //
  // Waits until the byte queue `q` (e.g. a pending expected-frame queue)
  // is empty, or until timeout_ns elapses. Sampling matches
  // wait_for_count_at_least.
  //------------------------------------------------------------------------
  static task wait_for_queue_empty(ref byte unsigned q[$], input virtual mac_rs_stream_if vif,
                                   input time timeout_ns, output bit timed_out);
    time start_ts;
    start_ts  = $time;
    timed_out = 1'b0;
    forever begin
      if (q.size() == 0) break;
      if (elapsed_since(start_ts) >= timeout_ns) begin
        timed_out = 1'b1;
        break;
      end
      if (vif == null) #1ns;
      else @(posedge vif.clk);
    end
  endtask
endclass

`endif  // MAC_WAIT_UTILS_SVH
