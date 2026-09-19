// Central transaction trace service. Drivers record intent and monitors record
// observations in one time-ordered end-to-end trace per test.
class mac_txn_logger_c;
  static int    fd = 0;
  static string path = "";

  protected
  function new();
  endfunction

  static function void open_if_needed();
    string test_name;
    string requested_path;
    uvm_cmdline_processor clp;
    if (fd != 0) return;
    clp = uvm_cmdline_processor::get_inst();
    if (!clp.get_arg_value("+UVM_TESTNAME=", test_name)) test_name = "mac_default";
    if (clp.get_arg_value("+MAC_TXN_LOG=", requested_path)) path = requested_path;
    else path = {test_name, ".transactions.log"};
    // Append to the simulator/UVM test log when +MAC_TXN_LOG points there.
    // This keeps one chronological artifact per test instead of creating a
    // separate transaction file.
    fd = $fopen(path, "a");
    if (fd == 0) $display("MAC_TXN_LOG: unable to open '%s'", path);
    else $fdisplay(fd, "# MAC transaction trace | test=%s", test_name);
  endfunction

  static function void write(uvm_component source, string action, uvm_object transaction);
    string source_name;
    open_if_needed();
    if (fd == 0) return;
    source_name = (source == null) ? "<none>" : source.get_full_name();
    $fdisplay(fd, "%0t | %s | %s | %s", $time, action, source_name,
              (transaction == null) ? "<null>" : transaction.sprint());
  endfunction

  static function void close();
    if (fd != 0) begin
      $fdisplay(fd, "# end of trace");
      $fclose(fd);
      fd = 0;
    end
  endfunction
endclass
