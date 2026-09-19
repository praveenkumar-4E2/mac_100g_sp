# MAC Feature Test Layout

Each testcase belongs to one IEEE MAC feature, not to an individual owner.
The owner, testcase ID, status, and requirement reference are tracked in
`../../testplan/mac_testplan.csv`.

| Feature directory | Testcases | Owner |
| --- | ---: | --- |
| `pause_frame/` | 5 | Adithya |
| `ipg/` | 2 | Adithya |
| `preamble_sfd/` | 3 | Haritha |
| `counters/` | 2 | Adithya |
| `address_filtering/` | 6 | Haritha |
| `padding/` | 1 | Haritha |
| `cdc/` | 3 | Akhil |
| `integration/` | 6 | Akhil |
| `statistics/` | 4 | Akhil |
| `ppm/` | 6 | Sudha |
| `reset/` | 5 | Sudha |
| `frame_format/` | 9 | Sudha |
| `crc/` | 3 | Praveen |
| `apb/` | 6 | Praveen |

Total: 61 testcases.

Test files use `mac_<feature>_<nnn>_test.svh` and classes use the matching
`mac_<feature>_<nnn>_test_c` name. Add the file to its feature aggregator,
then add that aggregator to `mac_test_manifest.svh` when it is first used.
