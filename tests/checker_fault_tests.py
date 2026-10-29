"""Prove that real arithmetic, completion and clock-gating RTL faults fail.

All intentional changes live in a temporary directory. The supplied rtl/ is
never modified. Requires the same Icarus tool options as run_verification.py.
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--ivl-base")
    parser.add_argument("--vpi-dir")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    extra = ["--iverilog", args.iverilog, "--vvp", args.vvp]
    for flag, value in (("--ivl-base", args.ivl_base), ("--vpi-dir", args.vpi_dir)):
        if value:
            extra += [flag, value]
    faults = [
        ("incorrect_product_sign", "precision_decode_mag.v", "(signs[1] ^ signs[0])", "(signs[1] | signs[0])"),
        ("early_result_valid", "precision_accumulator.v", "(term_count == 5'd15)", "(term_count == 5'd14)"),
        ("unsafe_combinational_clock_gate", "precision_icg.v", "clk & enable_latched", "clk & (enable | test_enable)"),
    ]
    report = {}
    with tempfile.TemporaryDirectory(prefix="pe_checker_faults_") as scratch:
        scratch = Path(scratch)
        vectors = scratch / "vectors"
        subprocess.run([sys.executable, str(ROOT / "verification/generate_vectors.py"),
                        "--profile", "quick", "--random-frames", "0", "--int16-pairs", "0", "--out", str(vectors)], check=True)
        for name, filename, old, new in faults:
            directory = scratch / name
            rtl = directory / "rtl"
            results = directory / "results"
            shutil.copytree(ROOT / "rtl", rtl)
            source = rtl / filename
            text = source.read_text(encoding="utf-8")
            if text.count(old) != 1:
                raise RuntimeError(f"Fault target no longer unique: {name}")
            source.write_text(text.replace(old, new), encoding="utf-8")
            completed = subprocess.run([sys.executable, str(ROOT / "run_verification.py"),
                                       "--skip-generate", "--vectors", str(vectors), "--rtl-dir", str(rtl),
                                       "--out", str(results), *extra], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      text=True, check=False)
            summary_path = results / "comparison_summary.json"
            if completed.returncode == 0 or not summary_path.exists():
                print(completed.stdout)
                raise RuntimeError(f"Fault was not detected through comparison: {name}")
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            if summary["result"] != "FAIL" or summary["mismatched_samples"] == 0:
                raise RuntimeError(f"Checker did not report the expected mismatch: {name}")
            report[name] = dict(result="DETECTED", process_exit_code=completed.returncode,
                                mismatched_samples=summary["mismatched_samples"],
                                failed_frames=summary["failed_frames"], field_failures=summary["field_failures"])
            print(f"DETECTED: {name}; {summary['mismatched_samples']} mismatched pre/post samples")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Checker fault tests passed: all three intentional RTL faults were rejected.")


if __name__ == "__main__":
    main()
