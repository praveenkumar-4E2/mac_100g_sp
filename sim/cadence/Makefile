## =====================================================================
## Cadence Xcelium simulation Makefile for MAC design (xrun)
##
## New here? Just run:   make
## It prints this help — nothing gets built by accident.
##
## Run from: sim/cadence/
##   - filelist paths are resolved via mac_compile.f (../../src relative)
##   - NOTHING is written loose into sim/cadence/; artifacts are organized:
##       logs/*/       - simulator run logs, compile logs
##       transactions/*/ - UVM transaction traces (+MAC_TXN_LOG)
##       waves/*/      - waveform databases (waves.shm) and Indago dbs (ida.db)
##       runs/<test>_<ts>/ - per-run sandboxes (private XMLib, cov_work)
##       results/, coverage/ - JSON summaries and merged coverage reports
##   - compiled snapshot cache is managed by xrun: check/compile share
##     ./xcelium.d; every run (run/run_cov/gui) uses a private XMLib run
##     context (locks/snapshots) inside its own runs/*/ folder so parallel
##     runs never lock-fight
##
## Requires Cadence Xcelium on PATH (xrun, imc) and Python 3.
## =====================================================================

## --------------------------- Tools -----------------------------------
XRUN  = xrun
IMC   = imc
## Python interpreter. Resolved at parse time to the first one that
## actually runs (verified via --version), trying in order:
##   python3 -> python -> py -> common Windows install paths
## Override explicitly with, e.g.:  make run PYTHON=C:/Python310/python.exe
PYTHON ?= $(shell \
  for c in python3 python py \
      "C:/Python310/python.exe" "C:/Python311/python.exe" \
      "C:/Python312/python.exe" "C:/Python313/python.exe" \
      "/c/Python310/python.exe" "/c/Python311/python.exe" \
      "/c/Python312/python.exe" "/c/Python313/python.exe" \
      "/mnt/c/Python310/python.exe" "/mnt/c/Python311/python.exe"; do \
    if "$$c" --version >/dev/null 2>&1; then echo "$$c"; exit 0; fi; \
  done; echo python3)
SIMULATOR ?= xcelium

## --------------------------- Project config ---------------------------
## Override any of these from the command line, e.g.:
##   make run TOP=other_top FILELIST=other.f
# xrun manages its compiled database here (no vlib/vmap step needed).
WORK      = xcelium.d
TOP       = mac_tb_top
FILELIST  = mac_compile.f
SIMVISION_TCL = simvision.tcl
SOURCE_DIR ?= ../../src
LOG_DIR ?= logs
RESULT_DIR ?= results
COVERAGE_DIR ?= coverage
TXN_DIR ?= transactions
WAVES_DIR ?= waves
PLUSARGS ?=
DEFINES ?=

# UVM installation, pinned explicitly.  The automatic `-uvm` selection was
# resolving to CDNS-1.1d on this host, so the library is pinned via
# `-uvmhome`.  Override per-invocation if your install differs, e.g.:
#   make compile UVM_HOME=/some/other/UVM/CDNS-1.2
UVM_HOME ?= /home/install/XCELIUM2209/tools.lnx86/methodology/UVM/CDNS-1.2

# -uvmhome $(UVM_HOME) : link against the pinned UVM library (see UVM_HOME).
#   The automatic `-uvm` form is avoided: it selected CDNS-1.1d on this host.
# +incdir+$(UVM_HOME)/sv/src : UVM header includes (uvm_macros.svh, ral).
# -access +rwc : read/write/connect visibility for waveforms and txn logging.
# -timescale 1ns/1ps : global default; several test files declare `timescale
#   inside the package include chain (Cadence requires it outside design units).
# -nowarn NONPRT -nowarn NODNTW -nowarn TMSERX : drop benign noise (UTF-8
#   em-dashes in comments, implicit-net ports under default_nettype none,
#   nested timescales).  -nowarn must be repeated per message id.
# -disable_sem2009 : the TB uses post-2009 SV (clocking-block events such as
#   @(vif.cb) and clocking skews); turn off Xcelium's 1800-2009 fallback so
#   elaboration treats those constructs (not just opaque rvalues) correctly.
# -elaborate : stops after elaboration (compile-checks only, no simulation).
XRUN_BASE_OPTS = -uvmhome $(UVM_HOME) +incdir+$(UVM_HOME)/sv/src -f $(FILELIST) -top $(TOP) -access +rwc -timescale 1ns/1ps -nowarn NONPRT -nowarn NODNTW -nowarn TMSERX -disable_sem2009
DEFINE_OPTS = $(foreach define,$(DEFINES),+define+$(define))
# Extra xrun switches appended only by targets that opt in (run_existing based
# flow).  `indago_run` uses it to add the Indago database option.  Default: none.
XRUN_EXTRA_OPTS ?=
COV_RUN_OPTS = -coverage all -covtest $(COVTEST) -covoverwrite
COMPILE_LOG = $(LOG_DIR)/compile/mac_xrun_compile.log

## --------------------------- Test selection -----------------------------
## Override per run, e.g.:
##   make run TEST=mac_sanity_test_c VERBOSITY=UVM_HIGH SEED=12345
ifndef TEST
override TEST = mac_sanity_test_c
endif

ifndef VERBOSITY
override VERBOSITY = UVM_MEDIUM
endif

ifndef SEED
override SEED = random
endif

# No global UVM phase timeout is forced.  A caller may opt in explicitly,
# for example: make run UVM_TIMEOUT=50000000
UVM_TIMEOUT ?=
comma := ,
UVM_TIMEOUT_PLUSARG = $(if $(strip $(UVM_TIMEOUT)),+UVM_TIMEOUT=$(UVM_TIMEOUT)$(comma)YES)

## Every test run gets a timestamped test-named RUN_ID.  The run sandbox
## (private XMLib context, cov_work) lives in runs/<TEST>_<ts>/ so nothing is
## dropped loose into sim/cadence/; user-facing artifacts are categorized:
## run log -> logs/, transaction trace -> transactions/, waves & Indago -> waves/.
ifndef RUN_TIMESTAMP
RUN_TIMESTAMP := $(shell $(PYTHON) -c "from datetime import datetime; print(datetime.now().strftime('%d.%m.%Y-%H.%M.%S'))")
endif
RUN_ID ?= $(TEST)_$(RUN_TIMESTAMP)
ARTIFACT_ROOT ?= runs
RUN_DIR    ?= $(ARTIFACT_ROOT)/$(RUN_ID)
RUN_LOG    = $(LOG_DIR)/$(RUN_ID)/$(RUN_ID).log
RUN_TCL    = $(RUN_DIR)/run.tcl
TXN_LOG    = $(TXN_DIR)/$(RUN_ID)/transactions.log
WAVE_DIR   = $(WAVES_DIR)/$(RUN_ID)
WAVE_DB    = $(WAVE_DIR)/waves.shm
# Each run gets its OWN xrun run context (-xmlibdirname), living inside its
# run folder.  XMLib is where xrun keeps the per-invocation databases: the
# run.* dirs, .xmlib.lock, and snapshots.  A private XMLib is what makes
# concurrent invocations (e.g. a GUI and a batch run) fully independent —
# no contention on the lock that previously hung runs.  The compiled-unit
# WORK library (./xcelium.d) stays shared so runs reuse the checked cache.
# Do NOT use -work here: a custom -work breaks the -uvm add-on package bind
# (*F,WRKBAD) and does not relocate the XMLib lock directory anyway.
# Absolute path is required (xrun resolves sub-process paths against its
# internal run directory, so a relative path fails with PRENOP).
RUN_XMLIB ?= $(abspath $(RUN_DIR)/xmlib)
RESULT_FILE ?= $(RESULT_DIR)/tests/$(RUN_ID).json

## --------------------------- Coverage config -----------------------------
## Xcelium writes one cov_work/scope/<covtest> tree per run.  Pointing the
## database at the run folder keeps coverage local to its test artifacts.
COVTEST       = $(TEST)
COV_WORKDIR   = $(RUN_DIR)/cov_work
COV_DB        = $(COV_WORKDIR)/scope/$(COVTEST)
COV_HTML      = $(RUN_DIR)/html_cov_report
COV_CMD       = $(RUN_DIR)/imc_report.cmd
# Default merge inputs: every per-test database beneath the artifact root.
COV_MERGED    ?= $(COVERAGE_DIR)/scope/merged
COV_MERGED_HTML ?= $(COVERAGE_DIR)/html_merged_report
COV_INPUTS ?= $(shell find $(ARTIFACT_ROOT) -type d -path '*/cov_work/scope/*' \
                             -not -path '$(COVERAGE_DIR)/*' 2>/dev/null)

## --------------------------- Regression config ----------------------------
## A regression list is just a text file with one test name per line
## (blank lines and lines starting with # are ignored). Example:
##   mac_sanity_test_c
##   mac_register_access_test_c
##   # mac_stress_test   <- disabled, kept for reference
TESTLIST ?= ../../src/hvl_top/testlists/full_regression.list
REGRESSION_ID ?= regression_$(RUN_TIMESTAMP)
REGRESSION_RESULTS_DIR ?= $(RESULT_DIR)/regression/$(REGRESSION_ID)/tests
# Per-test UVM watchdog used by `make regression`.  The value is in simulator
# time ticks (5 ms at the project time precision); override or disable with
# `make regression REGRESSION_UVM_TIMEOUT=` when running intentional long tests.
REGRESSION_UVM_TIMEOUT ?= 5000000000
# Regression runs sequentially, so all tests in one regression share a single
# XMLib run context for fast incremental reuse.  It is kept inside the
# regression artifacts so it can never collide with an unrelated concurrent
# run.  Absolute for the same reason as RUN_XMLIB.
REGRESSION_XMLIB ?= $(abspath $(RESULT_DIR)/regression/$(REGRESSION_ID)/xmlib)

## Files/dirs removed by `make clean`
CLEAN_TARGETS = $(WORK) csrc waves.shm cov_work $(LOG_DIR) $(RESULT_DIR) \
                $(COVERAGE_DIR) $(ARTIFACT_ROOT) $(TXN_DIR) $(WAVES_DIR) \
                __pycache__ *.log *.key

.PHONY: help all check compile run smoke run_cov cov_report coverage \
        coverage_merge gui gui_waves audit regression clean \
        indago indago_db indago_help xrun_indago_check find_db indago_run \
        open_log open_txns open_waves

## --------------------------- Default / Help ------------------------------

## Plain `make` prints help instead of building anything
help:
	@echo "";
	@echo "======================================================================";
	@echo " MAC design simulation (Cadence Xcelium) - Makefile quick guide";
	@echo "======================================================================";
	@echo "";
	@echo "I just want to check my code compiles (fastest option):";
	@echo "  make check";
	@echo "";
	@echo "I want to compile + elaborate (no simulation, builds xcelium.d):";
	@echo "  make compile";
	@echo "";
	@echo "I want to run the default test:";
	@echo "  make run";
	@echo "";
	@echo "I want to run a SPECIFIC test:";
	@echo "  make run TEST=mac_tx_payload_50_test_c SEED=12345 PLUSARGS=\"+NUM_FRAMES=10\"";
	@echo "  (sandbox under runs/<test>_<DDMMYYYY-HHMMSS>/; log in logs/,"
	@echo "   transactions in transactions/, results in results/ - nothing loose"
	@echo "   in sim/cadence/)";
	@echo "";
	@echo "I want to look at the last run's artifacts:";
	@echo "  make open_log     # tail the newest run log";
	@echo "  make open_txns    # show the newest transaction trace";
	@echo "  make open_waves   # open the newest waveform in SimVision";
	@echo "";
	@echo "I want to run a test with coverage collection:";
	@echo "  make run_cov TEST=mac_sanity_test_c";
	@echo "  make cov_report TEST=mac_sanity_test_c   # HTML report afterwards";
	@echo "";
	@echo "I want to open the SimVision GUI to debug:";
	@echo "  make gui TEST=mac_sanity_test_c";
	@echo "";
	@echo "I want to debug with Indago (post-process, Xcelium's debugger):";
	@echo "  make xrun_indago_check              # what this xrun supports for Indago";
	@echo "  make indago_run TEST=mac_apb_config_cdc_test_c   # sim -> creates ida.db";
	@echo "  make find_db                        # list the ida.db databases found";
	@echo "  make indago DB=waves/mac_apb_config_cdc_test_c_<ts>/ida.db   # open it";
	@echo "  make indago_help                    # options supported by this indago";
	@echo "";
	@echo "I want to run a whole list of tests (regression):";
	@echo "  make regression TESTLIST=../../src/hvl_top/testlists/full_regression.list";
	@echo "  make regression TESTLIST=../../src/hvl_top/testlists/feature/pause_frame.list";
	@echo "  # Test ownership/status: ../../src/hvl_top/testplan/mac_testplan.csv";
	@echo "";
	@echo "I want to clean everything and start fresh:";
	@echo "  make clean";
	@echo "";
	@echo "----------------------------------------------------------------------";
	@echo "Full target reference";
	@echo "----------------------------------------------------------------------";
	@echo "  check          - fastest syntax/elaboration-only check (no sim)";
	@echo "  compile        - compile + elaborate (no sim)";
	@echo "  run            - batch-mode simulation (compile -> run in one xrun)";
	@echo "  smoke          - run the default smoke test";
	@echo "  run_cov        - batch-mode sim with coverage collection";
	@echo "  cov_report     - build HTML coverage report for TEST (imc)";
	@echo "  coverage       - run_cov + cov_report";
	@echo "  coverage_merge - merge collected cov_work dbs into one report";
	@echo "  gui            - launch SimVision to debug interactively";
	@echo "  gui_waves      - SimVision with the curated probe tcl (simvision.tcl)";
	@echo "  indago_run     - batch sim that ALSO creates the Indago ida.db";
	@echo "  indago         - open a database: indago -db DB=<path> (background)";
	@echo "  indago_db      - alias of indago (same DB= argument)";
	@echo "  indago_help    - help for the installed indago executable";
	@echo "  find_db        - list ida.db databases under the current tree";
	@echo "  xrun_indago_check - grep xrun -help for supported Indago options";
	@echo "  open_log       - tail the newest run log (logs/)";
	@echo "  open_txns      - show the newest transaction trace (transactions/)";
	@echo "  open_waves     - open the newest waveform (waves/) in SimVision";
	@echo "  regression     - run every test listed in TESTLIST";
	@echo "  clean          - remove all generated files";
	@echo "";
	@echo "Variables you can override (VAR=value after any target):";
	@echo "  SIMULATOR=$(SIMULATOR)  TEST=$(TEST)  VERBOSITY=$(VERBOSITY)  SEED=$(SEED)";
	@echo "  PLUSARGS=$(PLUSARGS)  DEFINES=$(DEFINES)  SOURCE_DIR=$(SOURCE_DIR)";
	@echo "  LOG_DIR=$(LOG_DIR)  RESULT_DIR=$(RESULT_DIR)  COVERAGE_DIR=$(COVERAGE_DIR)";
	@echo "  TXN_DIR=$(TXN_DIR)  WAVES_DIR=$(WAVES_DIR)  ARTIFACT_ROOT=$(ARTIFACT_ROOT)";
	@echo "  RUN_XMLIB=$(RUN_XMLIB)  # private xrun run-context per run (parallel-safe)";
	@echo "  UVM_HOME=$(UVM_HOME)  # pinned UVM install (-uvmhome)";
	@echo "  DB=            # Indago database to open with 'make indago DB=<path>'";
	@echo "======================================================================";
	@echo "";

## --------------------------- Standard flow --------------------------------

## Fast development loop: compile + elaborate only, to catch syntax/UVM and
## top-binding errors without starting simulation.
check:
	@echo ">> Quick compile check (no simulation, no coverage)";
	$(XRUN) -elaborate $(XRUN_BASE_OPTS) $(DEFINE_OPTS)
	@echo ">> Compile check PASSED - no errors.";

## Full compile + elaboration.  xrun caches unchanged units in ./xcelium.d
## so repeat invocations are incremental.
compile:
	mkdir -p $(LOG_DIR)/compile
	$(XRUN) -elaborate $(XRUN_BASE_OPTS) $(DEFINE_OPTS) -l $(COMPILE_LOG)
	@echo ">> Elaboration finished. Log: $(COMPILE_LOG)";

## Batch-mode simulation (no GUI).  xrun compiles, elaborates, and runs in a
## single invocation into the run's private XMLib context (see RUN_XMLIB).
run:
	$(MAKE) --no-print-directory run_existing

## Prepare the run folder, run the test, and capture a JSON result.
run_existing:
	mkdir -p $(RUN_DIR) $(RUN_XMLIB) $(dir $(RUN_LOG)) $(dir $(TXN_LOG))
	@start_epoch=$$(date +%s); \
	$(XRUN) $(XRUN_BASE_OPTS) $(DEFINE_OPTS) $(XRUN_EXTRA_OPTS) -xmlibdirname $(RUN_XMLIB) \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) $(UVM_TIMEOUT_PLUSARG) +MAC_TXN_LOG=$(TXN_LOG) $(PLUSARGS) -seed $(SEED) \
	  -l $(RUN_LOG); sim_status=$$?; \
	$(PYTHON) mac_result_summary.py capture --test $(TEST) --seed $(SEED) --log $(RUN_LOG) --result $(RESULT_FILE) --start-epoch $$start_epoch; result_status=$$?; \
	echo ">> Test '$(TEST)' result: $(RESULT_FILE)"; \
	echo ">> Log: $(RUN_LOG)"; \
	echo ">> Transactions: $(TXN_LOG)"; \
	if [ $$sim_status -ne 0 ]; then exit $$sim_status; else exit $$result_status; fi

smoke:
	$(MAKE) run TEST=mac_sanity_test_c

## --------------------------- Coverage flow --------------------------------

## Batch-mode simulation with coverage collection.
## Xcelium writes cov_work into the per-test run folder; afterwards make
## cov_report turns it into HTML (imc).
run_cov:
	mkdir -p $(RUN_DIR) $(RUN_XMLIB) $(dir $(RUN_LOG)) $(dir $(TXN_LOG))
	$(XRUN) $(XRUN_BASE_OPTS) $(DEFINE_OPTS) $(COV_RUN_OPTS) -xmlibdirname $(RUN_XMLIB) -covworkdir $(COV_WORKDIR) \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) $(UVM_TIMEOUT_PLUSARG) +MAC_TXN_LOG=$(TXN_LOG) +MAC_FUNCTIONAL_COVERAGE $(PLUSARGS) -seed $(SEED) \
	  -l $(RUN_LOG)
	$(PYTHON) mac_result_summary.py capture --test $(TEST) --seed $(SEED) --log $(RUN_LOG) --result $(RESULT_FILE)
	@echo ">> Coverage saved: $(COV_DB)"

## Generate an HTML coverage report for the current TEST (imc).
cov_report:
	@if [ ! -d $(COV_DB) ]; then \
	  echo "ERROR: coverage database '$(COV_DB)' not found; run make run_cov first."; exit 1; \
	fi
	mkdir -p $(RUN_DIR)
	@printf 'load %s\nreport -html -details -metrics all -out %s\n' "$(COV_DB)" "$(COV_HTML)" > $(COV_CMD)
	$(IMC) -exec $(COV_CMD)
	@echo ">> Report: $(COV_HTML)/index.html"

coverage: run_cov cov_report

## Merge all collected MAC coverage databases and generate one HTML report.
coverage_merge:
	@if [ -z "$(strip $(COV_INPUTS))" ]; then \
	  echo "ERROR: no coverage databases found; run make run_cov first or set COV_INPUTS."; exit 1; \
	fi
	mkdir -p $(COVERAGE_DIR)
	$(IMC) -execcmd "merge $(COV_INPUTS) -out $(COV_MERGED); \
	                 load $(COV_MERGED); \
	                 report -html -details -metrics all -out $(COV_MERGED_HTML)"
	@echo ">> Merged coverage report: $(COV_MERGED_HTML)/index.html"

## --------------------------- GUI / debug ----------------------------------

## Interactive SimVision, no automatic waveform layout.
gui:
	mkdir -p $(RUN_DIR) $(RUN_XMLIB) $(dir $(RUN_LOG)) $(dir $(TXN_LOG))
	$(XRUN) $(XRUN_BASE_OPTS) $(DEFINE_OPTS) -xmlibdirname $(RUN_XMLIB) \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) $(UVM_TIMEOUT_PLUSARG) +MAC_TXN_LOG=$(TXN_LOG) $(PLUSARGS) -seed $(SEED) \
	  -l $(RUN_LOG) -gui

## Interactive SimVision with the curated probe layout (simvision.tcl).
## The SHM waveform database is created as waves.shm in the working directory
## and is moved into waves/<RUN_ID>/ when the run closes (nothing stays in
## sim/cadence/).  Open it later with `make open_waves`.
gui_waves:
	mkdir -p $(RUN_DIR) $(RUN_XMLIB) $(dir $(RUN_LOG)) $(dir $(TXN_LOG)) $(WAVE_DIR)
	$(XRUN) $(XRUN_BASE_OPTS) $(DEFINE_OPTS) -xmlibdirname $(RUN_XMLIB) \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) $(UVM_TIMEOUT_PLUSARG) +MAC_TXN_LOG=$(TXN_LOG) $(PLUSARGS) -seed $(SEED) \
	  -l $(RUN_LOG) -gui -input $(abspath $(SIMVISION_TCL))
	@if [ -d waves.shm ]; then mv -f waves.shm $(WAVE_DIR)/waves.shm; echo ">> Waveform: $(WAVE_DIR)/waves.shm"; fi

## --------------------------- Indago debug ----------------------------------

## Indago is used in POST-PROCESS mode here: a simulation run creates the
## Indago database (ida.db), which is opened afterwards with `indago -db`.
## A plain `make run` / `make gui` does NOT produce an ida.db: the simulator
## must be invoked with the Indago database option, which `indago_run` does.
##
## The simulator-side option was VERIFIED against this installation's
## `xrun -helpall` (see `make xrun_indago_check`).  22.09-s003 documents:
##   -debug_opts <indago_pp|indago_interactive|indago_flow_recording>
##   -indago                    Enable interactive debug with Indago
## `indago_pp` runs the post-process Indago flow (produces ida.db), which is
## what `indago_run` needs.  The legacy `-debug_opts +indago` form does NOT
## exist in 22.09 (it fails with *E,OPT2ND); override INDAGO_DEBUG_OPTS
## per-invocation only if a different installation documents otherwise.
INDAGO ?= indago
INDAGO_DEBUG_OPTS ?= indago_pp
INDAGO_OPTS ?=

## Open a post-process Indago database in the GUI.
##   make indago DB=waves/mac_apb_config_cdc_test_c_19.09.2026-17.28.03/ida.db
## NOTE: `indago -db <db>` runs in the background, exactly as the command
## shown above; the GUI keeps running after make returns.
indago:
	@if [ -z "$(strip $(DB))" ]; then \
	  echo "ERROR: no Indago database given (DB= is empty)."; \
	  echo "  Usage : make indago DB=<path-to-ida.db>"; \
	  echo "  List  : make find_db   # to see the databases that exist"; \
	  exit 1; \
	fi
	@if [ ! -f "$(DB)" ]; then \
	  echo "ERROR: Indago database '$(DB)' not found (or is not a file)."; \
	  echo "  Create one first with: make indago_run TEST=<test>"; \
	  echo "  Then list candidates with: make find_db"; \
	  exit 1; \
	fi
	$(INDAGO) $(INDAGO_OPTS) -db $(DB) &

## Alias for `indago`: open a specified Indago database (indago -db <db>).
indago_db: indago

## Show the installed Indago executable's help (supported Indago-side options).
indago_help:
	$(INDAGO) -help

## Verify what THIS xrun installation supports for Indago (do not guess).
## The short `xrun -help` does not document per-option details, so this uses
## `-helpall` (confirmed supported by xrun 22.09-s003's usage text).
xrun_indago_check:
	@echo ">> xrun -helpall: '-debug_opts' documentation block:"
	@$(XRUN) -helpall 2>&1 | grep -i -A 16 'debug_opts' || echo "  (no '-debug_opts' entry in xrun -helpall)";
	@echo "";
	@echo ">> xrun -helpall: any lines mentioning indago:"
	@$(XRUN) -helpall 2>&1 | grep -i -B 2 -A 8 indago || echo "  (no 'indago' lines in xrun -helpall)";

## List every Indago database (ida.db) under the artifact folders.
find_db:
	@echo ">> Indago databases (ida.db) found:"
	@found=0; \
	for d in $$(find $(ARTIFACT_ROOT) $(WAVES_DIR) $(LOG_DIR) $(TXN_DIR) \
	               -name 'ida.db' -type f 2>/dev/null); do \
	  echo "  $$d"; \
	  found=1; \
	done; \
	if [ $$found -eq 0 ]; then \
	  echo "  (none found)"; \
	  echo "  Create one with: make indago_run TEST=<test>"; \
	fi

## Simulation run that ALSO generates the Indago post-process database.
## xrun creates ida.db in the current working directory; it is then moved
## into waves/<RUN_ID>/.  Afterwards open it with:
##   make indago DB=waves/<TEST>_<ts>/ida.db
indago_run:
	@-$(MAKE) --no-print-directory run_existing \
	  XRUN_EXTRA_OPTS="-debug_opts $(INDAGO_DEBUG_OPTS)"; \
	rc=$$?; \
	if [ -f ida.db ]; then \
	  mkdir -p $(WAVE_DIR); \
	  mv -f ida.db $(WAVE_DIR)/ida.db; \
	  echo ">> Indago database written: $(WAVE_DIR)/ida.db"; \
	fi; \
	exit $$rc

## --------------------------- Open artifacts (debug helpers) ----------------

## Newest-artifact pickers (by modification time).  Everything lives in the
## categorized folders, so these are safe to call at any time.  The log picker
## ignores compile/regression logs so it always lands on a run log.
LATEST_LOG  = $(shell ls -1dt $(LOG_DIR)/*/*.log 2>/dev/null | grep -v '/compile/' | grep -v '/regression/' | head -n1)
LATEST_TXN  = $(shell ls -1dt $(TXN_DIR)/*/*.log        2>/dev/null | head -n1)
LATEST_WAVE = $(shell ls -1dt $(WAVES_DIR)/*/waves.shm   2>/dev/null | head -n1)

## Tail the newest run log (logs/<RUN_ID>/<RUN_ID>.log).
open_log:
	@if [ -z "$(LATEST_LOG)" ]; then \
	  echo "ERROR: no run log found under $(LOG_DIR)/ (ran 'make run'?)."; exit 1; \
	fi; \
	echo ">> $(LATEST_LOG)"; \
	tail -n 200 "$(LATEST_LOG)"

## Show the newest UVM transaction trace (transactions/<RUN_ID>/transactions.log).
open_txns:
	@if [ -z "$(LATEST_TXN)" ]; then \
	  echo "ERROR: no transaction trace found under $(TXN_DIR)/ (ran 'make run'?)."; exit 1; \
	fi; \
	echo ">> $(LATEST_TXN)"; \
	tail -n 100 "$(LATEST_TXN)"

## Open the newest saved waveform (waves/<RUN_ID>/waves.shm) in SimVision.
open_waves:
	@if [ -z "$(LATEST_WAVE)" ]; then \
	  echo "ERROR: no waveform found under $(WAVES_DIR)/ (ran 'make gui_waves'?)."; exit 1; \
	fi; \
	echo ">> Opening $(LATEST_WAVE) in SimVision"; \
	simvision "$(LATEST_WAVE)" &

## --------------------------- Regression ------------------------------------

## Run every test listed in $(TESTLIST) (one test name per line,
## '#' comments and blank lines ignored). Tests run sequentially and share
## one XMLib run context (REGRESSION_XMLIB) for incremental reuse across the
## list.  The compiled WORK library itself is always the shared ./xcelium.d.
regression:
	@if [ ! -f $(TESTLIST) ]; then \
	  echo "ERROR: testlist file '$(TESTLIST)' not found."; exit 1; \
	fi
	@echo ">> Running regression from $(TESTLIST)";
	@mkdir -p $(LOG_DIR)/regression $(REGRESSION_RESULTS_DIR) $(REGRESSION_XMLIB); \
	fail=0; \
	for t in $$(awk '{ sub(/\r$$/, ""); if ($$0 !~ /^[[:space:]]*($$|#)/) print }' $(TESTLIST)); do \
	  echo ""; \
	  echo ">> ---- Running test: $$t ----"; \
	  if $(MAKE) --no-print-directory run_existing TEST=$$t SEED=$(SEED) UVM_TIMEOUT=$(REGRESSION_UVM_TIMEOUT) RUN_ID=$${t}_$(RUN_TIMESTAMP) RUN_XMLIB=$(REGRESSION_XMLIB) RESULT_FILE=$(REGRESSION_RESULTS_DIR)/$${t}.json; then \
	    echo ">> PASS: $$t"; \
	  else \
	    fail=1; \
	    echo ">> FAIL: $$t"; \
	  fi; \
	done; \
	$(PYTHON) mac_result_summary.py summary --results-dir $(REGRESSION_RESULTS_DIR) > $(LOG_DIR)/regression/$(REGRESSION_ID)_summary.log; summary_status=$$?; \
	cat $(LOG_DIR)/regression/$(REGRESSION_ID)_summary.log; \
	echo ""; \
	if [ $$fail -eq 1 ] || [ $$summary_status -ne 0 ]; then \
	  echo ">> Regression finished WITH FAILURES."; exit 1; \
	else \
	  echo ">> Regression finished, all tests PASSED."; \
	fi

## --------------------------- Housekeeping -----------------------------------

## Remove all generated simulation artifacts, including every run_* folder.
## (rm -rf works on Linux/macOS/WSL/Git-Bash; not native cmd.exe)
clean:
	rm -rf $(CLEAN_TARGETS)