/** Shared polarity helpers for reset sequences, drivers, and monitors. */
class mac_reset_utils_c;
  static function bit is_asserted(bit reset_value, bit active_level);
    return (reset_value == active_level);
  endfunction

  static function bit inactive_level(bit active_level);
    return ~active_level;
  endfunction
endclass
