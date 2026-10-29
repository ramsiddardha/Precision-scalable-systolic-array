"""Generate stimulus AND Python expectations. No simulator or third-party modules."""

import argparse
import csv
import hashlib
import itertools
import json
import random
import tempfile
from collections import Counter
from dataclasses import asdict
from pathlib import Path

from reference_model import Inputs, PEModel, WIDTHS, PACK_BITS, PACK_HEX, pack

ROOT = Path(__file__).resolve().parents[1]


class Suite:
    def __init__(self, seed):
        self.seed = seed
        self.rng = random.Random(seed)
        self.model = PEModel()
        self.rows = []
        self.frames = []
        self.coverage = Counter()
        self.unique_pairs = {m: set() for m in WIDTHS}
        self.accepted = Counter()
        self.committed = Counter()
        self.labels = Counter()

    def add(self, category, label, *, glitch=0, **kwargs):
        inputs = Inputs(**kwargs)
        assert len(inputs.mode) == 2 and len(inputs.a) == len(inputs.b) == 4
        self.model.apply_async_reset(inputs)
        before = self.model.snapshot(inputs)
        accepted, _ = self.model.admission(inputs)
        if accepted and inputs.rst_n and not inputs.clear:
            self.unique_pairs[self.model.am].add((self.model.a, self.model.b))
            self.accepted[self.model.am] += 1
        if inputs.rst_n and not inputs.clear and inputs.advance and self.model.pv:
            self.committed[self.model.pm] += 1
        self.model.edge(inputs)
        after = self.model.snapshot(inputs)
        index = len(self.rows)
        self.rows.append((inputs, pack(before), pack(after), glitch, category, label))
        self.labels[category] += 1
        self.coverage["clocked_cycles"] += 1
        self.coverage["pre_and_post_samples"] += 2
        self.coverage["high_phase_checks"] += 2 * glitch
        self.coverage["reset_low_samples"] += int(not inputs.rst_n)
        self.coverage["clear_cycles"] += inputs.clear
        self.coverage["stalled_cycles"] += int(not inputs.advance and inputs.rst_n and not inputs.clear)
        self.coverage["one_sided_input_cycles"] += int(inputs.av != inputs.bv)
        self.coverage["error_samples"] += after["protocol_error"]
        return index

    def clear(self, category="control", label="clear", **kwargs):
        return self.add(category, label, clear=1, advance=0, **kwargs)

    def raw(self, value, mode, unknown=False):
        """Randomize ignored high bits; sometimes deliberately place X/Z there."""
        width = WIDTHS[mode]
        low = value & ((1 << width) - 1)
        if unknown and width < 16:
            return self.rng.choice("xz") * ((16 - width) // 4) + f"{low:0{width // 4}x}"
        return f"{((self.rng.getrandbits(16) >> width) << width) | low:04x}"

    def frame(self, mode, pairs, category, name, disturbances=False):
        assert len(pairs) == 16
        frame_id = len(self.frames)
        mode_bits = f"{mode:02b}"
        self.clear(category, f"{name}:start")
        for k, (a, b) in enumerate(pairs):
            if disturbances and k in (0, 3, 15):
                for stall in range(1 + (k == 3)):
                    self.add(category, f"{name}:stall[{k},{stall}]", advance=0,
                             mode="xx", a="xxxx", b="zzzz", av=1, bv=1, glitch=1)
            if disturbances and k in (2, 8):
                self.add(category, f"{name}:bubble[{k}]", mode="11", a="xxxx", b="zzzz")
            if disturbances and k == 10:
                self.add(category, f"{name}:A_only", mode=mode_bits, av=1,
                         a=self.raw(a, mode, True), b="xxxx")
                self.add(category, f"{name}:B_only", mode=mode_bits, bv=1,
                         a="xxxx", b=self.raw(b, mode, True))
            self.add(category, f"{name}:term[{k}]", mode=mode_bits, av=1, bv=1,
                     a=self.raw(a, mode, disturbances), b=self.raw(b, mode, disturbances))
        self.add(category, f"{name}:drain_operand", mode="xx", a="xxxx", b="xxxx")
        final_cycle = self.add(category, f"{name}:drain_product", mode="11")
        golden = sum(a * b for a, b in pairs)
        # A separate frame-level oracle also checks the token model itself.
        assert self.model.acc == golden and self.model.count == 16 and self.model.done
        assert self.model.acc_mode == mode and not self.model.stream_error
        if disturbances:
            self.add(category, f"{name}:hold_stalled", advance=0, mode="xx", av=1, bv=1,
                     a="xxxx", b="zzzz", glitch=1)
            self.add(category, f"{name}:hold_advancing", mode="xx")
        self.frames.append(dict(frame_id=frame_id, category=category, name=name,
                                mode=f"INT{WIDTHS[mode]}", final_cycle=final_cycle,
                                python_sum=golden, pairs=pairs))

    def controls(self):
        add = lambda label, **kw: self.add("control", label, **kw)
        add("initial_async_reset", rst_n=0, advance=0)
        add("release_reset", advance=0)
        for mode in WIDTHS:
            bits = f"{mode:02b}"
            self.clear(label=f"zero_INT{WIDTHS[mode]}")
            add("valid_zero_pair", mode=bits, av=1, bv=1)
            add("zero_product_capture", mode="xx")
            add("zero_product_commit", mode="11")
            assert self.model.count == 1 and self.model.acc == 0
            # Both ignored upper bits and live precision must be irrelevant.
            self.clear(label="ignored_upper_start")
            add("ignored_upper_pair", mode=bits, av=1, bv=1,
                a=self.raw(-3, mode, True), b=self.raw(5, mode, True), glitch=1)
            add("stored_mode_capture", mode="xx", a="xxxx", b="zzzz")
            add("stored_mode_commit", mode="11")
            assert self.model.acc == -15 and self.model.count == 1
            self.clear(label="one_sided_start")
            add("A_only", mode=bits, av=1, a=self.raw(-1, mode), b="xxxx")
            add("B_only", mode=bits, bv=1, a="zzzz", b=self.raw(2, mode))
            add("no_cross_cycle_pair", mode="xx")
            add("unpaired_drain", mode="11")
            assert self.model.count == 0 and self.model.acc == 0

        # Clear and asynchronous reset at each pipeline occupancy.
        for flush in ("clear", "reset"):
            for occupancy in (0, 1, 2, 3, 7):
                self.clear(label=f"{flush}_occupancy_{occupancy}_start")
                for k in range(occupancy):
                    add("fill_before_flush", mode="10", a="8000", b="7fff", av=1, bv=1)
                if flush == "clear":
                    self.clear(label="clear_overrides_stall_and_valid", av=1, bv=1,
                               mode="10", a="1234", b="5678", glitch=1)
                else:
                    add("async_reset_without_rising_edge", rst_n=0, advance=0,
                        av=1, bv=1, mode="10", a="1234", b="5678")
                    add("release_after_flush", advance=0)
                add("flush_drain1")
                add("flush_drain2")
                assert self.model.count == 0 and not self.model.pv

        for bad_mode in ("11", "xx", "x0", "0x", "z1"):
            for av, bv in ((1, 0), (0, 1), (1, 1)):
                self.clear(label="invalid_mode_start")
                add("invalid_mode_ignored_when_stalled", advance=0, mode=bad_mode,
                    av=av, bv=bv, a="xxxx", b="zzzz", glitch=1)
                assert not self.model.stream_error
                add("invalid_mode_flags_error", mode=bad_mode, av=av, bv=bv,
                    a="xxxx", b="zzzz")
                assert self.model.stream_error
                add("error_is_sticky", mode="00", av=1, bv=1, a="0002", b="0003")
                add("sticky_error_blocks_pair")
                add("sticky_error_holds_stalled", advance=0)
                self.clear(label="clear_error")
                assert not self.model.stream_error

        # Precision changes fail with a product pending and with one committed.
        for first, second in itertools.permutations(WIDTHS, 2):
            for committed in (False, True):
                self.clear(label="precision_violation_start")
                add("first_precision_pair", mode=f"{first:02b}", av=1, bv=1,
                    a=self.raw(-2, first), b=self.raw(3, first))
                if committed:
                    add("first_capture")
                    add("first_commit")
                add("changed_precision_in_hop", mode=f"{second:02b}", av=1, bv=1,
                    a=self.raw(2, second), b=self.raw(3, second))
                add("changed_precision_rejected")
                add("rejected_pair_not_counted")
                assert self.model.stream_error and self.model.acc == -6 and self.model.count == 1

        # An input error does not destroy a previously accepted pending product.
        self.clear(label="pending_error_start")
        add("pending_good1", mode="01", av=1, bv=1, a="fffd", b="0005")
        add("pending_good2", mode="01", av=1, bv=1, a="0002", b="0004")
        add("input_error_with_pending_product", mode="11", av=1, a="xxxx")
        add("accepted_pending_product_drains")
        assert self.model.stream_error and self.model.acc == -7 and self.model.count == 2
        # Reset is the other way to recover from an error.
        add("async_reset_clears_error", rst_n=0, advance=0)
        add("release_reset_after_error", advance=0)

        for mode in WIDTHS:
            # One extra pair with a full pipeline, and one after result_valid.
            for after_done in (False, True):
                self.clear(label="overflow_start")
                for k in range(16):
                    add("overflow_legal_term", mode=f"{mode:02b}", av=1, bv=1, a="0001", b="0001")
                if after_done:
                    add("overflow_drain1")
                    add("overflow_drain2")
                add("seventeenth_external_pair", mode=f"{mode:02b}", av=1, bv=1, a="0002", b="0003")
                add("seventeenth_pair_rejected")
                add("overflow_final_drain")
                assert self.model.stream_error and self.model.acc == 16 and self.model.count == 16
                add("overflow_result_holds", advance=0, mode="xx", glitch=1)
        self.clear(label="control_end")

    def build(self, profile, random_frames, int16_pairs):
        self.controls()
        for mode, width in WIDTHS.items():
            lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
            uniform = [(0, 0), (lo, lo), (hi, hi), (lo, hi), (hi, lo),
                       (lo, -1), (-1, lo), (-1, -1), (1, -1), (hi, 1), (lo, 1)]
            for n, pair in enumerate(uniform):
                self.frame(mode, [pair] * 16, "directed", f"INT{width}_uniform_{n}", True)
            self.frame(mode, [(hi, hi), (hi, -hi)] * 8, "directed", f"INT{width}_cancellation", True)
            self.frame(mode, [(lo, lo), (lo, hi)] * 8, "directed", f"INT{width}_alternating", True)
            # INT4 guard-carry/borrow transitions cross 8-bit and return to zero.
            self.frame(mode, [(lo, lo)] * 8 + [(lo, -lo - 1)] * 8,
                       "directed", f"INT{width}_carry_borrow", True)

        for mode in (0, 1):
            width = WIDTHS[mode]
            if mode == 1 and profile == "quick":
                continue
            values = range(-(1 << (width - 1)), 1 << (width - 1))
            iterator = iter(itertools.product(values, repeat=2))
            index = 0
            while pairs := list(itertools.islice(iterator, 16)):
                self.frame(mode, pairs, "exhaustive_pairs", f"INT{width}_all_pairs_{index}")
                index += 1

        # Signed extremes and nibble/byte/halfword transition boundaries.
        bounds = {-32768, -32767, 32766, 32767, -1, 0, 1}
        for bit in (3, 4, 7, 8, 11, 12, 15):
            for sign in (-1, 1):
                for offset in (-1, 0, 1):
                    value = sign * (1 << bit) + offset
                    if -32768 <= value <= 32767:
                        bounds.add(value)
        bound_pairs = list(itertools.product(sorted(bounds), repeat=2))
        self.coverage["INT16_boundary_pairs_requested"] = len(bound_pairs)
        for start in range(0, len(bound_pairs), 16):
            block = bound_pairs[start:start + 16]
            self.frame(2, block + [(0, 0)] * (16 - len(block)), "int16_boundaries", f"INT16_boundary_{start // 16}")
        for start in range(0, int16_pairs, 16):
            block = [(self.rng.randint(-32768, 32767), self.rng.randint(-32768, 32767))
                     for _ in range(min(16, int16_pairs - start))]
            self.frame(2, block + [(0, 0)] * (16 - len(block)), "int16_random_pairs", f"INT16_random_pair_{start // 16}")
        for frame_id in range(random_frames):
            for mode, width in WIDTHS.items():
                lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
                pairs = [(self.rng.randint(lo, hi), self.rng.randint(lo, hi)) for _ in range(16)]
                self.frame(mode, pairs, "random_control_frames", f"INT{width}_random_frame_{frame_id}", True)
        self.clear(label="final_clear")

    def write(self, out, profile, random_frames, int16_pairs):
        out.mkdir(parents=True, exist_ok=True)
        vector_path = out / "vectors.txt"
        with vector_path.open("w", encoding="ascii", newline="\n") as vectors, \
                (out / "cycles.csv").open("w", encoding="utf-8", newline="") as metadata:
            vectors.write(f"{len(self.rows)}\n")
            writer = csv.writer(metadata)
            writer.writerow(["cycle", "category", "label", "rst_n", "clear", "advance", "mode", "a", "b", "av", "bv", "high_phase_probe"])
            for index, (i, before, after, glitch, category, label) in enumerate(self.rows):
                vectors.write(f"{index} {i.rst_n} {i.clear} {i.advance} {i.mode} {i.a} {i.b} {i.av} {i.bv} "
                              f"{before:0{PACK_HEX}x} {after:0{PACK_HEX}x} {glitch}\n")
                writer.writerow([index, category, label, *asdict(i).values(), glitch])
        with (out / "frames.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.writer(stream)
            writer.writerow(["frame_id", "category", "name", "mode", "final_cycle", "python_sum", "a_terms", "b_terms"])
            for f in self.frames:
                writer.writerow([f[k] for k in ("frame_id", "category", "name", "mode", "final_cycle", "python_sum")]
                                + [" ".join(str(a) for a, _ in f["pairs"]), " ".join(str(b) for _, b in f["pairs"])])
        summary = dict(profile=profile, seed=self.seed, random_frames_per_mode=random_frames,
                       int16_random_pairs_requested=int16_pairs, pack_bits=PACK_BITS,
                       completed_legal_frames=len(self.frames), counters=dict(self.coverage),
                       frame_categories=dict(Counter(f["category"] for f in self.frames)),
                       cycle_categories=dict(self.labels),
                       modes={f"INT{w}": dict(unique_accepted_pairs=len(self.unique_pairs[m]),
                                              possible_pairs=1 << (2 * w),
                                              accepted_pairs=self.accepted[m], committed_products=self.committed[m],
                                              legal_frames=sum(f["mode"] == f"INT{w}" for f in self.frames))
                              for m, w in WIDTHS.items()},
                       vectors_sha256=hashlib.sha256(vector_path.read_bytes()).hexdigest(),
                       metadata_sha256={name: hashlib.sha256((out / name).read_bytes()).hexdigest()
                                        for name in ("cycles.csv", "frames.csv")},
                       limitation="Finite RTL simulation; INT16 pairs and full 16-term sequences are not exhaustive. "
                                  "Unknowns are tested in ignored operand bits and mode, not active arithmetic fields.")
        if profile == "full":
            assert len(self.unique_pairs[0]) == 256 and len(self.unique_pairs[1]) == 65536
        (out / "coverage.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"Generated {len(self.rows):,} cycles and {len(self.frames):,} complete legal frames ({profile}, seed={self.seed}).")
        for mode, detail in summary["modes"].items():
            print(f"  {mode}: {detail['unique_accepted_pairs']:,} unique accepted operand pairs; {detail['legal_frames']:,} legal frames")
        return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("quick", "full"), default="full")
    parser.add_argument("--seed", type=int, default=20261029)
    parser.add_argument("--random-frames", type=int, help="per precision; defaults to 8 quick / 100 full")
    parser.add_argument("--int16-pairs", type=int, help="random INT16 pairs; defaults to 256 quick / 8192 full")
    parser.add_argument("--out", type=Path, default=ROOT / "vectors")
    args = parser.parse_args()
    random_frames = args.random_frames if args.random_frames is not None else (8 if args.profile == "quick" else 100)
    int16_pairs = args.int16_pairs if args.int16_pairs is not None else (256 if args.profile == "quick" else 8192)
    if random_frames < 0 or int16_pairs < 0:
        parser.error("counts must be nonnegative")
    suite = Suite(args.seed)
    suite.build(args.profile, random_frames, int16_pairs)
    output = args.out.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    # Publish only complete files. coverage.json goes last as the commit marker.
    with tempfile.TemporaryDirectory(prefix=".pe_vector_build_", dir=output.parent) as staging:
        staging = Path(staging)
        suite.write(staging, args.profile, random_frames, int16_pairs)
        output.mkdir(parents=True, exist_ok=True)
        for name in ("vectors.txt", "cycles.csv", "frames.csv", "coverage.json"):
            (staging / name).replace(output / name)


if __name__ == "__main__":
    main()
