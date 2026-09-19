"""MAC-local simulator log result extraction and regression summarization.

Cross-simulator: understands both Questa (log lines prefixed with '#',
'** Error', ...) and Cadence Xcelium (no '#', 'xmvlog: *E,..' / 'xmelab:
*E,..' / 'xrun: *F,..' compile-elab-run messages) log conventions.
"""

import argparse
import json
import re
import time
from pathlib import Path


def uvm_count(text: str, severity: str) -> int:
    # UVM report summary counts, e.g.:
    #   questo:  # UVM_ERROR :   12
    #   xrun:    UVM_ERROR : 12
    # Anchored to the full line so per-message report lines (which continue
    # with @time/severity text) are not mistaken for the summary count.
    match = re.search(rf"^\s*\#?\s*UVM_{severity}\s*:\s*(\d+)\s*$",
                      text, re.MULTILINE)
    return int(match.group(1)) if match else 0


def simulator_errors(text: str) -> int:
    count = 0
    # Questa compile/load/run errors.
    count += len(re.findall(r"^\#?\s*\*\* Error(?:\s*\([^)]*\))?:",
                            text, re.MULTILINE))
    count += len(re.findall(r"^\#?\s*Error loading design\s*$",
                            text, re.MULTILINE))
    # Cadence Xcelium compile/elaborate (xmvlog/xmelab/ncvlog/ncelab/xrun)
    # and runtime fatal/error messages, e.g. "xmelab: *E,<ID>: ...".
    count += len(re.findall(
        r"^\s*#?\s*(?:xmvlog|xmelab|ncvlog|ncelab|irun|xrun|sncunix)"
        r"\s*:\s*\*[EF],", text, re.MULTILINE))
    count += len(re.findall(r"^\s*#?\s*\*[EF],", text, re.MULTILINE))
    return count


def capture(args: argparse.Namespace) -> int:
    log_path = Path(args.log)
    text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
    errors = uvm_count(text, "ERROR")
    warnings = uvm_count(text, "WARNING")
    fatals = uvm_count(text, "FATAL")
    # Compiler/elaboration/run errors are not necessarily UVM reports and
    # can still leave a zero process exit status. Count them so a batch
    # regression cannot advertise a simulator error as PASS.
    total_errors = errors + fatals + simulator_errors(text)
    status = "PASS" if log_path.exists() and total_errors == 0 else "FAIL"
    duration = (max(0.0, time.time() - args.start_epoch)
                if args.start_epoch is not None else
                (max(0.0, log_path.stat().st_mtime - log_path.stat().st_ctime)
                 if log_path.exists() else 0.0))
    result = {
        "test": args.test,
        "seed": str(args.seed),
        "status": status,
        "error_count": total_errors,
        "warning_count": warnings,
        "log_file": str(log_path),
        "duration_seconds": round(duration, 3),
    }
    result_path = Path(args.result)
    result_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("MAC_RESULT " + json.dumps(result, sort_keys=True))
    return 0 if status == "PASS" else 1


def summary(args: argparse.Namespace) -> int:
    results = []
    for path in sorted(Path(args.results_dir).glob("*.json")):
        try:
            results.append(json.loads(path.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError):
            continue
    print("=" * 88)
    print("MAC REGRESSION SUMMARY")
    print("=" * 88)
    print(f"{'TEST':30} {'SEED':12} {'STATUS':8} {'ERRORS':7} {'WARNINGS':9} DURATION  LOG")
    print("-" * 88)
    for r in results:
        print(f"{r['test']:30} {r['seed']:12} {r['status']:8} {r['error_count']:<7} "
              f"{r['warning_count']:<9} {r['duration_seconds']:>7.3f}s  {r['log_file']}")
    passed = sum(r["status"] == "PASS" for r in results)
    print("-" * 88)
    print(f"Total: {len(results)}  Passed: {passed}  Failed: {len(results) - passed}")
    print("=" * 88)
    return 0 if passed == len(results) else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    cap = sub.add_parser("capture")
    cap.add_argument("--test", required=True)
    cap.add_argument("--seed", required=True)
    cap.add_argument("--log", required=True)
    cap.add_argument("--result", required=True)
    cap.add_argument("--start-epoch", type=float,
                     help="Unix timestamp captured immediately before simulator launch")
    cap.set_defaults(func=capture)
    summ = sub.add_parser("summary")
    summ.add_argument("--results-dir", required=True)
    summ.set_defaults(func=summary)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())