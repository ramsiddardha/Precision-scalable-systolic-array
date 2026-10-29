"""Strict second comparison of the simulator CSV against Python golden vectors."""

import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

from reference_model import FIELDS, PACK_BITS, unpack

ROOT = Path(__file__).resolve().parents[1]


def compare(vectors_dir, results_dir):
    coverage = json.loads((vectors_dir / "coverage.json").read_text(encoding="utf-8"))
    vector_file = vectors_dir / "vectors.txt"
    if hashlib.sha256(vector_file.read_bytes()).hexdigest() != coverage["vectors_sha256"]:
        raise ValueError("Vector hash differs from coverage.json; regenerate a consistent vector set")
    for name, expected_hash in coverage["metadata_sha256"].items():
        if hashlib.sha256((vectors_dir / name).read_bytes()).hexdigest() != expected_hash:
            raise ValueError(f"Incomplete or inconsistent {name}; regenerate vectors")
    with (vectors_dir / "cycles.csv").open(newline="", encoding="utf-8") as stream:
        metadata = {int(row["cycle"]): row for row in csv.DictReader(stream)}
    with (vectors_dir / "frames.csv").open(newline="", encoding="utf-8") as stream:
        frames = {int(row["final_cycle"]): row for row in csv.DictReader(stream)}
    if len(metadata) != coverage["counters"]["clocked_cycles"] or len(frames) != coverage["completed_legal_frames"]:
        raise ValueError("Cycle/frame metadata count differs from coverage.json")
    errors = []
    bad_samples = 0
    checked_samples = 0
    field_failures = Counter()
    frame_results = []
    product_checks = 0
    failed_product_checks = 0
    vector_count = 0
    categories = Counter()
    results_dir.mkdir(parents=True, exist_ok=True)

    with vector_file.open(encoding="ascii") as expected_stream, \
            (results_dir / "rtl_results.csv").open(newline="", encoding="utf-8") as actual_stream, \
            (results_dir / "product_and_sum_comparison.csv").open("w", newline="", encoding="utf-8") as product_stream:
        product_writer = csv.DictWriter(product_stream, fieldnames=(
            "cycle", "category", "mode", "term_count", "python_product", "rtl_product",
            "python_running_sum", "rtl_running_sum", "result"))
        product_writer.writeheader()
        vector_count = int(expected_stream.readline())
        actual_rows = iter(csv.DictReader(actual_stream))
        for cycle in range(vector_count):
            tokens = expected_stream.readline().split()
            if len(tokens) != 12 or int(tokens[0]) != cycle:
                raise ValueError(f"Malformed golden vector at cycle {cycle}")
            if cycle not in metadata:
                raise ValueError(f"Missing cycle label at {cycle}")
            for phase, golden_word in (("pre", tokens[9]), ("post", tokens[10])):
                actual = next(actual_rows, None)
                if actual is None:
                    errors.append(f"Missing RTL samples from cycle {cycle} phase {phase}")
                    break
                if actual["cycle"] != str(cycle) or actual["phase"] != phase:
                    errors.append(f"Out-of-order/duplicate sample: expected {cycle},{phase}; got {actual['cycle']},{actual['phase']}")
                    break
                checked_samples += 1
                categories[metadata[cycle]["category"]] += 1
                expected = unpack(int(golden_word, 16))
                observed_text = actual["observed"].strip().lower()
                observed = None
                if not re.fullmatch(r"[0-9a-f]{42}", observed_text) or int(observed_text, 16) >= (1 << PACK_BITS):
                    differences = ["unknown_or_malformed_output"]
                else:
                    observed = unpack(int(observed_text, 16))
                    differences = [name for name, _ in FIELDS if expected[name] != observed[name]]
                    # Also verify the human-readable CSV columns are truthful.
                    display_fields = {"a_signed": "a_out", "b_signed": "b_out", "acc_signed": "acc_q",
                                      "term_count": "term_count", "result_valid": "result_valid", "protocol_error": "protocol_error"}
                    for column, field in display_fields.items():
                        if actual[column] != str(observed[field]):
                            differences.append(f"CSV_{column}")
                if differences:
                    bad_samples += 1
                    field_failures.update(differences)
                    if len(errors) < 12:
                        detail = "; ".join(f"{name}: Python={expected.get(name)} RTL={observed.get(name) if observed else observed_text}"
                                           for name in differences)
                        errors.append(f"cycle {cycle} {phase} [{metadata[cycle]['label']}]: {detail}")
                if phase == "pre":
                    pre_expected, pre_observed = expected, observed
                elif tokens[1:4] == ["1", "0", "1"] and pre_expected["product_valid_q"]:
                    # The OLD product register is consumed on this edge.
                    product_checks += 1
                    rtl_product = pre_observed["product_q"] if pre_observed else "UNKNOWN"
                    rtl_sum = observed["acc_q"] if observed else "UNKNOWN"
                    product_ok = bool(observed and pre_observed and
                                      rtl_product == pre_expected["product_q"] and
                                      rtl_sum == expected["acc_q"] and
                                      observed["term_count"] == expected["term_count"])
                    failed_product_checks += int(not product_ok)
                    product_writer.writerow(dict(cycle=cycle, category=metadata[cycle]["category"],
                        mode=f"INT{(4, 8, 16)[pre_expected['product_mode_q']]}",
                        term_count=expected["term_count"], python_product=pre_expected["product_q"],
                        rtl_product=rtl_product, python_running_sum=expected["acc_q"],
                        rtl_running_sum=rtl_sum, result="PASS" if product_ok else "FAIL"))
                if phase == "post" and cycle in frames:
                    frame = frames[cycle]
                    rtl_sum = observed["acc_q"] if observed else "UNKNOWN"
                    width_mode = {"INT4": 0, "INT8": 1, "INT16": 2}[frame["mode"]]
                    passed = bool(observed and rtl_sum == int(frame["python_sum"])
                                  and observed["term_count"] == 16 and observed["result_valid"] == 1
                                  and observed["protocol_error"] == 0 and observed["acc_mode_q"] == width_mode)
                    frame_results.append({**{k: frame[k] for k in ("frame_id", "category", "name", "mode", "final_cycle", "python_sum")},
                                          "rtl_sum": rtl_sum, "result": "PASS" if passed else "FAIL"})
            else:
                continue
            break
        if next(actual_rows, None) is not None:
            errors.append("Unexpected extra RTL samples")
        if expected_stream.read().strip():
            errors.append("Unconsumed golden vectors")

    if checked_samples != 2 * vector_count:
        errors.append(f"Sample count: got {checked_samples}, expected {2 * vector_count}")
    if len(frame_results) != len(frames):
        errors.append(f"Frame count: got {len(frame_results)}, expected {len(frames)}")
    status_path = results_dir / "simulation_status.txt"
    status = status_path.read_text(encoding="utf-8").strip() if status_path.exists() else "MISSING"
    status_match = re.fullmatch(r"PASS cycles=(\d+) samples=(\d+) high_checks=(\d+) errors=0 USE_HSM=([01])", status)
    if not status_match or tuple(map(int, status_match.groups()[:3])) != (
            vector_count, 2 * vector_count, coverage["counters"]["high_phase_checks"]):
        errors.append(f"Simulator completion/high-phase-check status is not valid: {status}")
    failed_frames = sum(row["result"] != "PASS" for row in frame_results)
    passed = not errors and bad_samples == 0 and failed_frames == 0 and failed_product_checks == 0
    summary = dict(result="PASS" if passed else "FAIL", profile=coverage["profile"],
                   seed=coverage["seed"], cycles=vector_count, samples_checked=checked_samples,
                   high_phase_checks=coverage["counters"]["high_phase_checks"],
                   legal_frames_compared=len(frame_results), failed_frames=failed_frames,
                   products_and_running_sums_compared=product_checks, failed_product_checks=failed_product_checks,
                   mismatched_samples=bad_samples, field_failures=dict(field_failures),
                   modes=coverage["modes"], samples_by_category=dict(categories),
                   simulator_status=status, first_errors=errors[:12],
                   vectors_sha256=coverage["vectors_sha256"], limitation=coverage["limitation"])
    results_dir.mkdir(parents=True, exist_ok=True)
    (results_dir / "comparison_summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    with (results_dir / "frame_comparison.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=("frame_id", "category", "name", "mode", "final_cycle", "python_sum", "rtl_sum", "result"))
        writer.writeheader()
        writer.writerows(frame_results)
    lines = [f"PYTHON vs RTL: {summary['result']}", f"Profile: {coverage['profile']}; seed: {coverage['seed']}",
             f"Clocked cycles: {vector_count:,}", f"Pre/post samples compared: {checked_samples:,}",
             f"High-phase clock-gating state checks: {summary['high_phase_checks']:,}",
             f"Complete legal 16-term frames: {len(frame_results):,}; failed: {failed_frames}",
             f"Products and running sums compared: {product_checks:,}; failed: {failed_product_checks}",
             f"Mismatched samples: {bad_samples}"]
    for mode, counts in coverage["modes"].items():
        lines.append(f"{mode}: {counts['unique_accepted_pairs']:,}/{counts['possible_pairs']:,} unique operand pairs, "
                     f"{counts['legal_frames']:,} complete legal frames")
    lines += ["", *errors[:12], coverage["limitation"]]
    report = "\n".join(lines) + "\n"
    (results_dir / "comparison_report.txt").write_text(report, encoding="utf-8")
    print(report)
    return passed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vectors", type=Path, default=ROOT / "vectors")
    parser.add_argument("--results", type=Path, default=ROOT / "results")
    args = parser.parse_args()
    try:
        passed = compare(args.vectors.resolve(), args.results.resolve())
    except (OSError, ValueError, KeyError, csv.Error) as exc:
        print(f"COMPARISON FAILED: {exc}")
        raise SystemExit(1) from exc
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
