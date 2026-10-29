# How your single-PE verification works

## 1. The arithmetic answer is simple

A legal frame has 16 pairs of operands, and one precision throughout:

```python
products = [a[k] * b[k] for k in range(16)]
answer = sum(products)
```

Python uses signed integers, so it does not need your tile multiplier, CSA
tree, final CPA or CLA accumulator to calculate the answer. That independence
is useful: a mistake in the RTL arithmetic should disagree with Python.

For example, sixteen pairs with A=2 and B=3 have sixteen products of 6.
The final answer is 96. The expected running sums are 6, 12, 18, ..., 96.

The generator also checks its pipeline model's final value against this
separate frame-level `sum(a*b for a,b in pairs)` calculation.

## 2. Your PE has three stages

On each advancing rising edge, the stages act on their **old** input state:

1. The operand registers capture the new external A/B input and forward it.
2. The product register captures the product of the previously stored operands.
3. The accumulator consumes the previously stored product.

The Python model represents those stages as tokens with values, precision
and valid bits. It predicts when arithmetic should happen, not the internal
adder/multiplier implementation.

Starting after clear, with sixteen consecutive valid input pairs and no
bubbles or stalls, the example above behaves like this:

| Advancing edge | New external pair | Product captured | Product accumulated | Count | Sum | Done |
|---:|---|---|---|---:|---:|---:|
| 1 | Pair 1 | None | None | 0 | 0 | 0 |
| 2 | Pair 2 | Product 1 = 6 | None | 0 | 0 | 0 |
| 3 | Pair 3 | Product 2 = 6 | Product 1 = 6 | 1 | 6 | 0 |
| 4 | Pair 4 | Product 3 = 6 | Product 2 = 6 | 2 | 12 | 0 |
| 16 | Pair 16 | Product 15 = 6 | Product 14 = 6 | 14 | 84 | 0 |
| 17 | Invalid inputs | Product 16 = 6 | Product 15 = 6 | 15 | 90 | 0 |
| 18 | Invalid inputs | None | Product 16 = 6 | 16 | 96 | 1 |

This is why TWO drain edges are required after sending the last pair.
`advance=0` holds all stages. An advancing bubble clears the input valids
while already pending work can move. Those are different operations.

`clear=1` starts a new frame and flushes the pipeline, including during a
stall. `rst_n=0` resets asynchronously. The bench tests each rule.

## 3. Which bits Python interprets

The precision selects the signed operand field:

| Mode | Operand field | Signed range | Product width | Accumulator width |
|---|---|---|---:|---:|
| `00` INT4 | Input bits 3:0 | -8 to 7 | 8 | 12 |
| `01` INT8 | Input bits 7:0 | -128 to 127 | 16 | 20 |
| `10` INT16 | Input bits 15:0 | -32768 to 32767 | 32 | 36 |

For INT4, raw input `fffd` means -3 because the active low nibble is `d`.
An input `xxxd` also means -3 for this test: the upper 12 bits are ignored.
Unknowns in active arithmetic bits are outside this numeric reference's scope.

The model converts the low field to a Python signed integer before doing
`a*b`, and checks that each running sum fits the selected accumulator width.

## 4. Files Python produces

`generate_vectors.py` creates four files:

- `vectors.txt`: simulation input and exact expected pre/post sample buses.
- `cycles.csv`: readable labels and control/input values for every cycle.
- `frames.csv`: the 16 A values, 16 B values and final Python sum for each legal frame.
- `coverage.json`: profile, seed, tested-pair counts and integrity hashes.

The first line of `vectors.txt` is the number of clocked steps. Each later
line contains 12 fields:

| Position | Meaning |
|---:|---|
| 1 | Zero-based cycle ID |
| 2 | `rst_n` |
| 3 | `clear` |
| 4 | `advance` |
| 5 | Two-bit mode, including X/Z in selected control tests |
| 6, 7 | Raw 16-bit A and B values in hexadecimal |
| 8, 9 | A-valid and B-valid |
| 10 | Python's expected comparison bus before the rising edge |
| 11 | Python's expected comparison bus after the rising edge |
| 12 | Whether to run the high-clock control-change state-hold probe |

The 166-bit comparison bus packs the public outputs, selected pipeline state,
tile mask and current combinational product. Its field names/widths are in
`reference_model.py:FIELDS`, in the same order as the SV `observed` bus.
It is a convenient transport encoding; each sum is still calculated with
ordinary Python integer arithmetic.

This package uses streaming `$fscanf` instead of a generated `.vh` array-size
header. Regenerating a different workload changes the file's first-line count;
the bench reads it automatically.

## 5. What the SystemVerilog testbench does

For each line, `systolic_pe_python_tb.sv`:

1. Reads the controls, inputs and Python expected values with `$fscanf`.
2. Drives them while `clk=0`, giving the clock-gating latches time to settle.
3. Samples and checks the pre-edge output bus. Reset assertions are checked
   here before another rising edge can occur.
4. Raises `clk`, waits for registered and combinational updates, and checks
   the post-edge bus.
5. Logs both samples to `rtl_results.csv`.
6. For selected rows, changes/restores controls while `clk=1` and checks that
   stored state remains equal to its immediately preceding post-edge value.

The arithmetic reference does not run inside the SV bench: expected
products, sums, counts and flags all came from Python. The comparison uses
four-state inequality (`!==`), so an unexpected X/Z output also fails.

The bench prints up to twelve initial mismatch messages, keeps recording,
and ends with `$fatal` when any check fails. It writes a completion-status
file only after reaching the declared final vector. File/format problems
also abort the run.

## 6. Why a second Python comparison is useful

`compare_results.py` reads the saved simulator trace and the golden vectors.
It requires every pre/post row in order, with no missing, duplicate or extra
rows. It checks the vector/metadata hashes, every bus field, the final
simulator status and the high-clock check count.

It creates two particularly useful tables:

- `product_and_sum_comparison.csv`: for every consumed product, the Python
  and RTL product, running sum and term count.
- `frame_comparison.csv`: for every complete legal frame, the Python and RTL
  final sum, plus PASS/FAIL. Completion requires count=16, correct precision,
  `result_valid=1` and `protocol_error=0`.

For example, the delivered INT4 uniform minimum-times-minimum frame has
A=-8, B=-8 for each term. Its product is +64, and its final sum is +1024.
Both values appear in the comparison CSVs. The analogous INT16 frame reaches
17,179,869,184, demonstrating why a 32-bit accumulator is insufficient.

## 7. What PASS establishes

PASS means the supplied RTL agreed with Python for the specific generated
workload, both in arithmetic and the checked pipeline/control behavior.
Every INT4 and INT8 value pair was exercised in the full profile. Complete
16-term frames include boundary patterns, cancellation and random values,
with and without stalls/bubbles.

Each negative control test has an expected answer too. For example, a valid
reserved-mode input must set the sticky protocol error. That assertion is a
successful test when it matches Python. A result from an error-marked frame
is excluded from the complete legal-frame totals.

There are 2^32 possible INT16 operand pairs and 2^512 possible INT16
16-term input sequences even before considering control histories. The
delivered INT16 workload samples those possibilities; it is not exhaustive.

The exact unchanged RTL hashes and the simulator configuration are retained
with the validated run. Functional PASS does not substitute for your Genus
timing, mapped-cell or activity-based power analysis.

## 8. Finding a failure

Use the first failure in `comparison_report.txt` or the simulator console:

```text
cycle 460 post [INT4_uniform_1:term[0]]:
multiplier_product: Python=64 RTL=-64
```

That example is from an intentional wrong-sign mutation used to test the
checker. The correct uploaded RTL passes it. The label identifies the test;
`cycles.csv` gives its controls/input values. The field name identifies which
part of the observed behavior first differs.

For a waveform, run a quick-profile Icarus test with `--vcd`, or inspect the
bench's `dut` hierarchy in Vivado. The complete frame terms are in `frames.csv`.
