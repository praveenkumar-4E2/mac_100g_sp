# MAC UVM Test Layout

Tests are organized by feature.  A test owns its scenario, while reusable
stimulus lives in the matching `../sequences/` feature directory.

```text
test/
  base/          shared setup, reset, APB bootstrap
  mac/           feature-organized testcase source and manifest
../sequences/
  axi/ rs/       agent-level ingress stimulus
  smoke/         reusable smoke-test stimulus
  virtual/       cross-agent virtual sequences
../coverage/     functional coverage and coverage plan
../testlists/    smoke, feature, nightly, and full regressions
```

All feature tests belong in `test/mac/<feature>/`. `mac_virtual_seqr.sv` remains in `tb/` because it is environment
infrastructure.  New tests extend `mac_base_test_c`, stay focused on one
feature, and are added to the smallest relevant testlist.
