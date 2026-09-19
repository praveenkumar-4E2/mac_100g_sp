## =====================================================================
## Cadence Xcelium simulation Makefile for MAC design (xrun)
##
## New here? Just run:   make
## It prints this help — nothing gets built by accident.
##
## Run from: sim/cadence/
##   - filelist paths are resolved via mac_compile.f (../../src relative)
##   - logs go under logs/, results under results/, coverage under coverage/
##     (all inside this cadence folder, per request)
##   - compiled snapshot cache is managed by xrun in ./xcelium.d
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
PLUSARGS ?=
DEFINES ?=

# -uvm  : compile/link against Xcelium's built-in UVM (macros + RAL).
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
XRUN_BASE_OPTS = -uvm -f $(FILELIST) -top $(TOP) -access +rwc -timescale 1ns/1ps -nowarn NONPRT -nowarn NODNTW -nowarn TMSERX -disable_sem2009
DEFINE_OPTS = $(foreach define,$(DEFINES),+define+$(define))
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

## Every test run gets a timestamped test-named folder inside cadence/.
## Logs, waveforms, and coverage databases for one run stay together there.
ifndef RUN_TIMESTAMP
RUN_TIMESTAMP := $(shell $(PYTHON) -c "from datetime import datetime; print(datetime.now().strftime('%d.%m.%Y-%H.%M.%S'))")
endif
RUN_ID ?= $(TEST)_$(RUN_TIMESTAMP)
ARTIFACT_ROOT ?= .
RUN_DIR    ?= $(ARTIFACT_ROOT)/$(RUN_ID)
RUN_LOG    = $(RUN_DIR)/$(RUN_ID).log
RUN_TCL    = $(RUN_DIR)/run.tcl
# Transaction trace records are appended to the normal UVM test log.
TXN_LOG    = $(RUN_LOG)
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

## Files/dirs removed by `make clean`
CLEAN_TARGETS = $(WORK) csrc waves.shm cov_work $(LOG_DIR) $(RESULT_DIR) \
                $(COVERAGE_DIR) *.log *.key *_??.??.????-??.??.??

.PHONY: help all check compile run smoke run_cov cov_report coverage \
        coverage_merge gui gui_waves audit regression clean

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
	@echo "  (run artifacts are saved under ./<test>_<DDMMYYYY-HHMMSS>/;";
	@echo "   logs in logs/, results in results/, all inside sim/cadence/)";
	@echo "";
	@echo "I want to run a test with coverage collection:";
	@echo "  make run_cov TEST=mac_sanity_test_c";
	@echo "  make cov_report TEST=mac_sanity_test_c   # HTML report afterwards";
	@echo "";
	@echo "I want to open the SimVision GUI to debug:";
	@echo "  make gui TEST=mac_sanity_test_c";
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
	@echo "  regression     - run every test listed in TESTLIST";
	@echo "  clean          - remove all generated files";
	@echo "";
	@echo "Variables you can override (VAR=value after any target):";
	@echo "  SIMULATOR=$(SIMULATOR)  TEST=$(TEST)  VERBOSITY=$(VERBOSITY)  SEED=$(SEED)";
	@echo "  PLUSARGS=$(PLUSARGS)  DEFINES=$(DEFINES)  SOURCE_DIR=$(SOURCE_DIR)";
	@echo "  LOG_DIR=$(LOG_DIR)  RESULT_DIR=$(RESULT_DIR)  COVERAGE_DIR=$(COVERAGE_DIR)";
	@echo "  ARTIFACT_ROOT=$(ARTIFACT_ROOT)  RUN_TIMESTAMP=$(RUN_TIMESTAMP)";
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
## single invocation; unchanged units are reused from xcelium.d.
run: compile
	$(MAKE) --no-print-directory run_existing

## Prepare the run folder, run the test, and capture a JSON result.
run_existing:
	mkdir -p $(RUN_DIR)
	@start_epoch=$$(date +%s); \
	$(XRUN) $(XRUN_BASE_OPTS) $(DEFINE_OPTS) \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) $(UVM_TIMEOUT_PLUSARG) +MAC_TXN_LOG=$(TXN_LOG) $(PLUSARGS) -seed $(SEED) \
	  -l $(RUN_LOG); sim_status=$$?; \
	$(PYTHON) mac_result_summary.py capture --test $(TEST) --seed $(SEED) --log $(RUN_LOG) --result $(RESULT_FILE) --start-epoch $$start_epoch; result_status=$$?; \
	echo ">> Test '$(TEST)' result: $(RESULT_FILE)"; \
	if [ $$sim_status -ne 0 ]; then exit $$sim_status; else exit $$result_status; fi

smoke:
	$(MAKE) run TEST=mac_sanity_test_c

## --------------------------- Coverage flow --------------------------------

## Batch-mode simulation with coverage collection.
## Xcelium writes cov_work into the per-test run folder; afterwards make
## cov_report turns it into HTML (imc).
run_cov: compile
	mkdir -p $(RUN_DIR)
	$(XRUN) $(XRUN_BASE_OPTS) $(DEFINE_OPTS) $(COV_RUN_OPTS) -covworkdir $(COV_WORKDIR) \
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
	mkdir -p $(RUN_DIR)
	$(XRUN) $(XRUN_BASE_OPTS) $(DEFINE_OPTS) \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) $(UVM_TIMEOUT_PLUSARG) +MAC_TXN_LOG=$(TXN_LOG) $(PLUSARGS) -seed $(SEED) \
	  -l $(RUN_LOG) -gui

## Interactive SimVision with the curated probe layout (simvision.tcl)
## and an SHM waveform database saved in the run folder.
gui_waves:
	mkdir -p $(RUN_DIR)
	$(XRUN) $(XRUN_BASE_OPTS) $(DEFINE_OPTS) \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) $(UVM_TIMEOUT_PLUSARG) +MAC_TXN_LOG=$(TXN_LOG) $(PLUSARGS) -seed $(SEED) \
	  -l $(RUN_LOG) -gui -input $(RUN_DIR)/../$(SIMVISION_TCL)

## --------------------------- Regression ------------------------------------

## Run every test listed in $(TESTLIST) (one test name per line,
## '#' comments and blank lines ignored). Compiles once conceptually;
## xrun re-elaborates incrementally per test via run_existing.
regression: compile
	@if [ ! -f $(TESTLIST) ]; then \
	  echo "ERROR: testlist file '$(TESTLIST)' not found."; exit 1; \
	fi
	@echo ">> Running regression from $(TESTLIST)";
	@mkdir -p $(LOG_DIR)/regression $(REGRESSION_RESULTS_DIR); \
	fail=0; \
	for t in $$(awk '{ sub(/\r$$/, ""); if ($$0 !~ /^[[:space:]]*($$|#)/) print }' $(TESTLIST)); do \
	  echo ""; \
	  echo ">> ---- Running test: $$t ----"; \
	  if $(MAKE) --no-print-directory run_existing TEST=$$t SEED=$(SEED) UVM_TIMEOUT=$(REGRESSION_UVM_TIMEOUT) RUN_ID=$${t}_$(RUN_TIMESTAMP) RESULT_FILE=$(REGRESSION_RESULTS_DIR)/$${t}.json; then \
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