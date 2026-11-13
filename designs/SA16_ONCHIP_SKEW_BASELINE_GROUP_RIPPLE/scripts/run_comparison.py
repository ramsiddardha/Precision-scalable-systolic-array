#!/usr/bin/env python3
"""Check XSim captures and run one synthesis plus three power jobs per on-chip skew array."""

import argparse
import csv
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = ("baseline", "group_ripple")
MODES = ("int4", "int8", "int16")
TOP = "systolic_array_skew_top"
GENUS_TCL = ROOT / "scripts/run_genus.tcl"
BENCH = ROOT / "tb/block_tb.sv"
LIBRARY = (
    "/afs/iitd.ac.in/service/tools/public/asiclib/tsmc/L65/libraries/LP/"
    "TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a/tcbn65lptc.lib"
)
INPUTS = {
    "clk": 1, "rst_n": 1, "start": 1, "step_enable": 1, "mode": 2,
    "a_vector": 256, "b_vector": 256,
}
PERIODS = {"3.333": ("3p333", 3333000), "3.000": ("3ns", 3000000)}
INPUT_CYCLES = 16
FRAME_CYCLES = 51
CAPTURE_START = 4
MACS_PER_FRAME = 4096
NUM = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
FIELDS = (
    "variant", "mode", "status", "clock_period_ns", "power_method", "cells", "area", "critical_data_path_ns",
    "setup_slack_ps", "setup_margin_target_ps", "setup_margin_met",
    "leakage_mw", "internal_mw", "switching_mw", "dynamic_mw", "total_mw",
    "switching_delta_pct_vs_baseline", "dynamic_delta_pct_vs_baseline",
    "dynamic_ratio_vs_int4", "switching_ratio_vs_int4", "frames", "checked_macs",
    "capture_ns", "captured_clock_cycles", "dynamic_energy_pj_per_mac", "total_energy_pj_per_mac",
    "genus_version", "operating_conditions",
)


def required(pattern, text, label):
    match = re.search(pattern, text, re.M)
    if match is None:
        raise ValueError(f"Cannot read {label}")
    return match


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1048576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def text_write(path, text):
    temp = path.with_suffix(".tmp")
    temp.write_text(text)
    temp.replace(path)


def check_capture(variant, mode, rtl, period):
    tag, period_fs = PERIODS[period]
    mode_index = MODES.index(mode)
    directory = ROOT / "variants" / variant / "activity" / tag
    path = directory / f"array_{mode}.vcd"
    info = directory / f"array_{mode}_runinfo.txt"
    metadata = info.read_text()
    for key, value in (
        ("Design top", TOP), ("Variant", variant), ("Test result", "PASS"),
        ("VCD DUT scope", "block_tb/dut"), ("Mode", f"{mode_index} ({mode})"),
        ("Clock period", f"{period} ns"),
    ):
        required(rf"^{re.escape(key + ': ' + value)}\s*$", metadata, f"{key} in {info}")
    frame_match = required(r"^Frames: (\d+); checked MACs: (\d+)\s*$", metadata, "frame count")
    frames, products = map(int, frame_match.groups())
    if frames < 1 or products != MACS_PER_FRAME * frames:
        raise ValueError(f"Invalid frame or MAC count in {info}")
    seed = int(required(r"^Random seed: 0x([0-9a-fA-F]+)\s*$", metadata, "seed")[1], 16)
    if seed == 0:
        raise ValueError(f"Zero seed in {info}")
    sources = dict(re.findall(r"^Source CRC32: (\S+) ([a-fA-F0-9]{8})\s*$", metadata, re.M))
    expected = {source.name: f"{zlib.crc32(source.read_bytes()):08x}" for source in (*rtl, BENCH)}
    if sources != expected:
        raise ValueError(f"VCD RTL/bench mismatch for {variant}/{mode}. Regenerate the capture.")
    crc = 0
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1048576), b""):
            crc = zlib.crc32(chunk, crc)
            digest.update(chunk)
    expected_crc = required(r"^VCD CRC32: ([0-9a-fA-F]{8})\s*$", metadata, "VCD checksum")[1]
    if expected_crc.lower() != f"{crc:08x}":
        raise ValueError(f"VCD checksum mismatch: {path}. Transfer in binary mode.")
    begin = CAPTURE_START * period_fs
    end = begin + FRAME_CYCLES * frames * period_fs
    for label, stamp in (("begins", begin), ("ends", end)):
        value = required(rf"^Capture {label}: ({NUM}) ns\s*$", metadata, f"capture {label}")[1]
        if round(float(value) * 1e6) != stamp:
            raise ValueError(f"Capture timestamp mismatch in {info}")
    with path.open("rb") as f:
        stimulus = check_vcd(f, path, mode_index, begin, end, period_fs)
    return path, digest.hexdigest(), (seed, frames, products, begin, end), stimulus


def check_vcd(stream, path, mode_index, begin, end, period_fs):
    scopes, ports, timescale = [], {}, None
    for line in stream:
        tokens = line.split()
        if tokens[:1] == [b"$scope"]:
            scopes.append(tokens[2])
        elif tokens[:1] == [b"$upscope"]:
            scopes.pop()
        elif tokens[:1] == [b"$var"] and scopes == [b"block_tb", b"dut"]:
            ports[tokens[4].decode("ascii")] = (tokens[3], int(tokens[2]))
        elif tokens[:1] == [b"$timescale"]:
            while b"$end" not in tokens:
                continuation = stream.readline()
                if not continuation:
                    raise ValueError(f"Incomplete VCD timescale in {path}")
                tokens.extend(continuation.split())
            timescale = b"".join(tokens[1:tokens.index(b"$end")])
        elif tokens[:1] == [b"$enddefinitions"]:
            if b"$end" not in tokens and stream.readline().strip() != b"$end":
                raise ValueError(f"Incomplete VCD header in {path}")
            break
    if timescale != b"1fs":
        raise ValueError(f"Expected 1 fs timescale in {path}")

    watched = {**INPUTS, "input_ready": 1, "done": 1, "error": 1}
    if any(name not in ports or ports[name][1] != width for name, width in watched.items()):
        raise ValueError(f"Missing or wrong-width DUT VCD ports in {path}")
    identifiers = {name: ports[name][0] for name in watched}
    monitored = set(identifiers.values())
    aliases = {}
    for name in INPUTS:
        aliases.setdefault(identifiers[name], []).append(name)
    values, rises, done_rises, pending = {}, [], [], {}
    sampled_feed, sampled_start = [], []
    ready_before_edge = False
    stimulus = hashlib.sha256()
    first, now = None, 0

    def hash_boundary():
        # Canonicalize names and value widths so XSim identifier assignments do
        # not affect the comparison. Hash one final value per timestamp.
        if pending:
            for name, bits in sorted(pending.items()):
                stimulus.update(f"{now}:{name}:{bits}\n".encode("ascii"))
            pending.clear()

    for raw in stream:
        line = raw.strip()
        tag = line[:1]
        if tag == b"#":
            hash_boundary()
            ready_before_edge = values.get(identifiers["input_ready"]) == 1
            now = int(line[1:])
            if first is None:
                first = now
        elif tag in (b"b", b"B", b"0", b"1", b"x", b"X", b"z", b"Z"):
            if tag in (b"b", b"B"):
                bits, identifier = line[1:].split()
            else:
                bits, identifier = tag, line[1:]
            if identifier not in monitored:
                continue
            if bits.strip(b"01"):
                raise ValueError(f"Unknown DUT activity in {path} at {now} fs")
            value = int(bits, 2)
            if identifier == identifiers["mode"] and value != mode_index:
                raise ValueError(f"Mode changed or is incorrect in {path}")
            if identifier in (identifiers["rst_n"], identifiers["step_enable"]) and value != 1:
                raise ValueError(f"Reset or pause in measured VCD {path} at {now} fs")
            if identifier == identifiers["error"] and value:
                raise ValueError(f"Controller or mesh error in {path} at {now} fs")
            old = values.get(identifier)
            if old != value:
                if old == 0 and value == 1:
                    if identifier == identifiers["clk"]:
                        rises.append(now)
                        if ready_before_edge:
                            sampled_feed.append(now)
                        if values.get(identifiers["start"]) == 1:
                            sampled_start.append(now)
                    if identifier == identifiers["done"]:
                        done_rises.append(now)
                for name in aliases.get(identifier, ()):
                    pending[name] = value
                values[identifier] = value
    hash_boundary()
    expected_rises = list(range(begin + period_fs // 2, end, period_fs))
    expected_done = expected_rises[FRAME_CYCLES-1::FRAME_CYCLES]
    expected_start = expected_rises[::FRAME_CYCLES]
    expected_feed = [stamp for index, stamp in enumerate(expected_rises)
                     if 2 <= index % FRAME_CYCLES < 2 + INPUT_CYCLES]
    if (first not in (begin, begin - 1) or now != end or not monitored.issubset(values)
            or rises != expected_rises or done_rises != expected_done
            or sampled_start != expected_start or sampled_feed != expected_feed):
        raise ValueError(f"Capture duration, clock, vector intake, or completion check failed for {path}")
    return stimulus.hexdigest()


def metrics_synth(directory, margin):
    area = (directory / "area.rpt").read_text(errors="replace")
    timing = (directory / "timing.rpt").read_text(errors="replace")
    row = required(rf"^\s*{TOP}\s+\S+\s+(\d+)\s+({NUM})", area, "top area")
    path = required(rf"^Path\s+1:\s+(?:MET|VIOLATED)\s+\(\s*({NUM})\s+(ps|ns)\)", timing, "setup path")
    factor = {"ps": 1, "ns": 1000}[path[2]]
    slack = float(path[1]) * factor
    delay = float(required(rf"^\s*Data Path:\s*-\s*({NUM})", timing, "data path delay")[1])
    return {
        "cells": int(row[1]), "area": float(row[2]), "critical_data_path_ns": round(delay * factor / 1000, 9),
        "setup_slack_ps": slack, "setup_margin_target_ps": margin,
        "setup_margin_met": "YES" if slack >= margin else "NO",
        "genus_version": required(r"^\s*Generated by:\s*(.+)$", area, "Genus version")[1].strip(),
        "operating_conditions": required(r"^\s*Operating conditions:\s*(.+)$", area, "PVT conditions")[1].strip(),
    }


def metrics_power(directory, method, mode, cycles):
    if method == "time_based":
        log = directory / "console.log"
        trace = log.read_text(errors="replace")
        if (f"TIME-BASED COVERAGE: {cycles} physical frames" not in trace
                or f"TIME-BASED COMPLETE: {mode}" not in trace
                or not re.search(r"(?i)Started\s+['\"]?time[_ -]based['\"]?\s+power computation|-mode\s*:\s*time_based\b", trace)
                or re.search(r"(?i)using average analysis|fall(?:ing)? back to average|does not exist in PDB", trace)):
            raise ValueError(f"Time-based analysis was not verified. See {log}")
    text = (directory / "power.rpt").read_text(errors="replace")
    unit = required(r"^Power Unit:\s*(\S+)", text, "power unit")[1].lower()
    factors = {"w": 1000, "mw": 1, "uw": .001, "μw": .001, "µw": .001}
    if unit not in factors:
        raise ValueError(f"Unsupported power unit {unit}")
    row = required(rf"^\s*(?:Subtotal|Total)\s+({NUM})\s+({NUM})\s+({NUM})\s+({NUM})", text, "power subtotal")
    leakage, internal, switching, total = [float(x) * factors[unit] for x in row.groups()]
    return dict(zip(("leakage_mw", "internal_mw", "switching_mw", "dynamic_mw", "total_mw"),
                    (round(x, 9) for x in (leakage, internal, switching, internal + switching, total))))


def native_state_counts(path):
    states = {"DFF": set(), "DLAT": set()}
    with path.open(errors="replace") as source:
        for line in source:
            match = re.fullmatch(r"add mapped point \S+ (\S+)/\S+ -type (DFF|DLAT) \2\s*", line)
            if match:
                states[match[2]].add(match[1])
    if not all(states.values()):
        raise ValueError(f"Missing FF/latch state points in native map {path}")
    return tuple(len(states[kind]) for kind in ("DFF", "DLAT"))


def run_job(genus, directory, fingerprint, environment, read_metrics, fresh):
    directory.mkdir(parents=True, exist_ok=True)
    record = directory / "result.json"
    completed = directory / "COMPLETED.txt"
    if not fresh and record.is_file() and completed.is_file():
        try:
            previous = json.loads(record.read_text())
            if previous["signature"] == fingerprint:
                result = read_metrics(directory)
                if result == previous["metrics"]:
                    print(f"  REUSE {directory.relative_to(ROOT)}", flush=True)
                    return result
        except (OSError, ValueError, KeyError):
            pass
    for file in (record, completed):
        if file.exists():
            file.unlink()
    if environment["PE_STAGE"] == "synth":
        old_fv = directory / "fv"
        if old_fv.is_dir():
            shutil.rmtree(old_fv)
        for name in ("final.db", "state.map.do", "mapped.v", "mapped.sdc", "area.rpt", "timing.rpt"):
            try:
                (directory / name).unlink()
            except FileNotFoundError:
                pass
    else:
        for name in ("power.rpt", "activity.rpt", "activity_after_power.rpt"):
            try:
                (directory / name).unlink()
            except FileNotFoundError:
                pass
    log = directory / "console.log"
    print(f"  RUN   {directory.relative_to(ROOT)}", flush=True)
    command = [str(genus), "-no_gui"]
    if environment["PE_STAGE"] == "power" and environment["PE_POWER_METHOD"] == "time_based":
        command += ["-batch", "-abort_on_error", "-lic_startup_options", "Joules_Implementation_Opt"]
    with log.open("w") as out:
        process = subprocess.run(command + ["-files", str(GENUS_TCL)],
                                 cwd=directory, stdout=out, stderr=subprocess.STDOUT,
                                 env=dict(os.environ, **environment), check=False)
    if process.returncode or not completed.is_file():
        raise ValueError(f"Genus exit {process.returncode} or incomplete run. See {log}")
    result = read_metrics(directory)
    text_write(record, json.dumps({"signature": fingerprint, "metrics": result}, indent=2) + "\n")
    return result


def synth_result(directory, margin):
    result = metrics_synth(directory, margin)
    result["db_sha256"] = sha256(directory / "final.db")
    result["map_sha256"] = sha256(directory / "state.map.do")
    result["ff"], result["latch"] = native_state_counts(directory / "state.map.do")
    return result


def write_summary(rows, output):
    baseline = {row["mode"]: row for row in rows if row["variant"] == "baseline" and row["status"] == "OK"}
    int4 = {row["variant"]: row for row in rows if row["mode"] == "int4" and row["status"] == "OK"}
    for row in rows:
        reference = baseline.get(row["mode"])
        if reference and row["status"] == "OK":
            for metric in ("switching", "dynamic"):
                key = f"{metric}_mw"
                if reference[key]:
                    row[f"{metric}_delta_pct_vs_baseline"] = round((row[key] / reference[key] - 1) * 100, 4)
        own_int4 = int4.get(row["variant"])
        if own_int4 and row["status"] == "OK":
            for metric in ("dynamic", "switching"):
                key = f"{metric}_mw"
                if own_int4[key]:
                    row[f"{metric}_ratio_vs_int4"] = round(row[key] / own_int4[key], 6)
    temp = output.with_suffix(".tmp")
    with temp.open("w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    temp.replace(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--period", choices=PERIODS, default="3.333", help="Clock period in ns")
    parser.add_argument("--time-based", action="store_true", help="Run Joules per-cycle power instead of average-activity power")
    parser.add_argument("--check-captures", action="store_true", help="Check only the XSim VCDs and matching RTL")
    parser.add_argument("--fresh", action="store_true", help="Rerun completed jobs")
    parser.add_argument("variants", nargs="*", metavar="VARIANT", help="Default: baseline and group_ripple")
    args = parser.parse_args()
    unknown = set(args.variants).difference(VARIANTS)
    if unknown:
        parser.error("Unknown PE variant: " + ", ".join(sorted(unknown)))
    selected = tuple(dict.fromkeys(args.variants or VARIANTS))
    tag, _ = PERIODS[args.period]
    method = "time_based" if args.time_based else "average_activity"
    sdc = ROOT / "constraints" / f"array_{tag}.sdc"
    variant_suffix = "" if set(selected) == set(VARIANTS) else "_" + selected[0]
    output = ROOT / f"onchip_skew_array_{tag}_{method}{variant_suffix}_summary.csv"
    all_rtl = {v: sorted((ROOT / "variants" / v / "rtl").glob("*.v")) for v in selected}
    captures, workloads, stimulus_by_mode = {}, set(), {}
    for variant, rtl in all_rtl.items():
        if len(rtl) != 23:
            raise ValueError(f"Expected 23 RTL files in {variant}")
        for mode in MODES:
            path, digest, workload, stimulus = check_capture(variant, mode, rtl, args.period)
            if stimulus_by_mode.setdefault(mode, stimulus) != stimulus:
                raise ValueError(f"Boundary stimulus differs across builds in {variant}/{mode}")
            captures[variant, mode] = path, digest
            workloads.add(workload)
            print(f"PASS capture {variant}/{mode}", flush=True)
    if len(workloads) != 1:
        raise ValueError("Captures differ in seed, workload size, or measurement window")
    if args.check_captures:
        return 0
    _, frames, macs, begin, end = next(iter(workloads))
    capture_ns = (end - begin) / 1e6
    cycles = FRAME_CYCLES * frames
    workload_fields = {"frames": frames, "checked_macs": macs, "capture_ns": capture_ns,
                       "captured_clock_cycles": cycles, "clock_period_ns": args.period, "power_method": method}

    margin = int(os.environ.get("PE_SETUP_MARGIN_PS", "250"))
    if not 0 <= margin <= 3000:
        raise ValueError("PE_SETUP_MARGIN_PS must be between 0 and 3000")
    executable = shutil.which(os.environ.get("GENUS_BIN", ""))
    if not executable:
        raise ValueError("Use the dirac1 tmux pane with the working Genus 23 launcher exported as GENUS_BIN.")
    genus = Path(executable).absolute()
    library = Path(os.environ.get("PE_LIB_FILE", LIBRARY)).expanduser().resolve()
    if library.name != "tcbn65lptc.lib" or not library.is_file():
        raise ValueError(f"Cannot read TSMC65 LP typical Liberty: {library}")
    common = [str(genus.resolve()), str(genus.stat().st_mtime_ns), str(library), str(margin),
              *(sha256(path) for path in (library, sdc, GENUS_TCL, Path(__file__)))]
    rows, failed = [], False
    for variant, rtl in all_rtl.items():
        print(f"===== {variant} =====", flush=True)
        run_dir = ROOT / "runs" / tag / variant
        mapped = run_dir / "synth"
        synthesis_key = hashlib.sha256("|".join(common + [sha256(path) for path in rtl]).encode()).hexdigest()
        env = {"PE_LIB_FILE": str(library), "PE_VARIANT": variant, "PE_SETUP_MARGIN_PS": str(margin),
               "PE_PERIOD": args.period, "PE_SDC": str(sdc)}
        try:
            synthesis = run_job(genus, mapped, synthesis_key, dict(env, PE_STAGE="synth"),
                                lambda directory: synth_result(directory, margin), args.fresh)
        except (OSError, ValueError) as error:
            print(f"  FAILED synthesis: {error}", file=sys.stderr, flush=True)
            rows.extend(dict(workload_fields, variant=variant, mode=mode, status="SYNTH_FAILED") for mode in MODES)
            failed = True
            write_summary(rows, output)
            continue
        reported = {key: value for key, value in synthesis.items() if key in FIELDS}
        for mode in MODES:
            vcd, vcd_hash = captures[variant, mode]
            key = hashlib.sha256("|".join((synthesis_key, synthesis["db_sha256"],
                                          synthesis["map_sha256"], vcd_hash, method)).encode()).hexdigest()
            power_env = dict(env, PE_STAGE="power", PE_MODE=mode, PE_VCD_FILE=str(vcd), PE_MAPPED_DIR=str(mapped),
                             PE_EXPECTED_FF=str(synthesis["ff"]), PE_EXPECTED_LATCH=str(synthesis["latch"]),
                             PE_POWER_METHOD=method, PE_START=f"{begin}fs", PE_END=f"{end}fs", PE_CYCLES=str(cycles))
            row = {"variant": variant, "mode": mode, **reported, **workload_fields}
            try:
                power = run_job(genus, run_dir / method / mode, key, power_env,
                                lambda directory: metrics_power(directory, method, mode, cycles), args.fresh)
                row.update(status="OK", **power)
                for metric in ("dynamic", "total"):
                    row[f"{metric}_energy_pj_per_mac"] = round(row[f"{metric}_mw"] * capture_ns / macs, 9)
                rows.append(row)
            except (OSError, ValueError) as error:
                print(f"  FAILED {mode}: {error}", file=sys.stderr, flush=True)
                rows.append(dict(row, status="POWER_FAILED"))
                failed = True
        write_summary(rows, output)
    print(f"Wrote {output}", flush=True)
    return int(failed)


if __name__ == "__main__":
    try:
        with (ROOT / ".genus.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            sys.exit(main())
    except (OSError, ValueError) as error:
        sys.exit(str(error))
