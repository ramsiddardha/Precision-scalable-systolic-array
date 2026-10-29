"""One-command Python -> SystemVerilog simulation -> Python comparison (Icarus)."""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def run_logged(command, logfile, cwd):
    with logfile.open("w", encoding="utf-8") as stream:
        result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, check=False)
    print(logfile.read_text(encoding="utf-8", errors="replace"), end="", flush=True)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("quick", "full"), default="full")
    parser.add_argument("--seed", type=int, default=20261029)
    parser.add_argument("--random-frames", type=int)
    parser.add_argument("--int16-pairs", type=int)
    parser.add_argument("--use-hsm", type=int, choices=(0, 1), default=0)
    parser.add_argument("--skip-generate", action="store_true")
    parser.add_argument("--vcd", action="store_true", help="optional waveform; full-profile files can be large")
    parser.add_argument("--out", type=Path, default=ROOT / "results")
    parser.add_argument("--vectors", type=Path, default=ROOT / "vectors")
    parser.add_argument("--rtl-dir", type=Path, default=ROOT / "rtl")
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--ivl-base", type=Path, help="optional Icarus backend directory for a relocated installation")
    parser.add_argument("--vpi-dir", type=Path, help="optional Icarus VPI module directory")
    args = parser.parse_args()
    out, vectors = args.out.resolve(), args.vectors.resolve()
    out.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    # Remove completion artifacts first. A failed new run cannot inherit PASS.
    for name in ("simulation_status.txt", "rtl_results.csv", "comparison_summary.json", "product_and_sum_comparison.csv",
                 "comparison_report.txt", "frame_comparison.csv", "run_metadata.json"):
        (out / name).unlink(missing_ok=True)
    if not args.skip_generate:
        generate = [sys.executable, str(ROOT / "verification/generate_vectors.py"),
                    "--profile", args.profile, "--seed", str(args.seed), "--out", str(vectors)]
        if args.random_frames is not None:
            generate += ["--random-frames", str(args.random_frames)]
        if args.int16_pairs is not None:
            generate += ["--int16-pairs", str(args.int16_pairs)]
        subprocess.run(generate, cwd=ROOT, check=True)

    missing = [program for program in (args.iverilog, args.vvp) if shutil.which(program) is None]
    if missing:
        parser.error("Simulator executable not found: " + ", ".join(missing) +
                     ". Install Icarus Verilog, or use verification/setup_pe_python_vivado.tcl in Vivado.")
    rtl_files = sorted(args.rtl_dir.resolve().glob("*.v"))
    if not rtl_files:
        parser.error("No Verilog files in --rtl-dir")
    compile_cmd = [args.iverilog]
    if args.ivl_base:
        compile_cmd += ["-B", str(args.ivl_base.resolve())]
    executable = out / "pe_python.vvp"
    compile_cmd += ["-g2012", "-s", "systolic_pe_python_tb",
                    f"-Psystolic_pe_python_tb.USE_HSM={args.use_hsm}",
                    "-o", str(executable)]
    compile_cmd += [str(p) for p in rtl_files] + [str(ROOT / "tb/systolic_pe_python_tb.sv")]
    print("Compiling single-PE RTL and Python-driven bench...", flush=True)
    if run_logged(compile_cmd, out / "compile.log", ROOT):
        raise SystemExit(1)
    simulate = [args.vvp]
    if args.vpi_dir:
        simulate += ["-M", str(args.vpi_dir.resolve())]
    simulate += [str(executable), f"+VECTORS={vectors / 'vectors.txt'}",
                 f"+RESULTS={out / 'rtl_results.csv'}", f"+STATUS={out / 'simulation_status.txt'}"]
    if args.vcd:
        simulate += [f"+VCD={out / 'single_pe.vcd'}"]
    print("Running simulation; output is recorded in simulation.log...", flush=True)
    simulation_code = run_logged(simulate, out / "simulation.log", ROOT)
    comparison_code = subprocess.run(
        [sys.executable, str(ROOT / "verification/compare_results.py"), "--vectors", str(vectors), "--results", str(out)],
        cwd=ROOT, check=False).returncode
    coverage = json.loads((vectors / "coverage.json").read_text(encoding="utf-8"))
    metadata = dict(simulator="Icarus Verilog / vvp", use_hsm=args.use_hsm,
                    simulation_exit_code=simulation_code, comparison_exit_code=comparison_code,
                    elapsed_seconds=round(time.monotonic() - start, 3),
                    profile=coverage["profile"], seed=coverage["seed"], vectors_sha256=coverage["vectors_sha256"],
                    python_version=sys.version.split()[0],
                    rtl_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in rtl_files})
    (out / "run_metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    if simulation_code or comparison_code:
        raise SystemExit(1)
    print(f"All checks passed. Results: {out / 'comparison_report.txt'}", flush=True)


if __name__ == "__main__":
    main()
