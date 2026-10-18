# Verification plan and coverage

There are different checking layers. Their counts describe different things
and should not be added together or presented as interchangeable coverage.

| Layer | Current check | Meaning |
| --- | --- | --- |
| Python model | 13 test methods | Automated checks of arithmetic, formats, input validation and export |
| Signed decoding in Python | 196608 comparisons | Every 16-bit raw word interpreted in each of three modes |
| Generated matrix suite | 127 cases | Deterministic A/B/precision sets and expected C matrices |
| Unsigned tile RTL | 256 input pairs | Every unsigned 4x4 pair, checked for both BASIC and HSM |
| Shared signed multiplier, MAC, PE and array | Planned | Integration, control and full numerical-output checks |

## Python reference-model tests

The thirteen methods check hand-calculated small/rectangular results, signed
limits, small/full-size packing, a predictable 16x16 demo, invalid packing,
exhaustive decoding, known encodings and ignored upper bits, identity/zero and
sixteen-term extrema, selected generated properties, exported layouts and
invalid inputs. See the [test source](../reference_model/test_tensor_matrix_reference.py).

The exhaustive decoder loops over 65536 raw words and checks INT4, INT8 and
INT16: 65536*3 = 196608 comparisons. This is exhaustive raw-word decoding,
not exhaustive A/B multiplication or exhaustive matrix input coverage.

## The 127 generated matrix cases

For each size 2x2, 4x4 and 16x16, and each precision INT4/8/16, the generator
creates nine directed patterns and five random cases. One extra INT4 demo gives:

`3 sizes * 3 precisions * (9 directed + 5 random) + 1 demo = 127 cases`

Directed patterns are zeros, right identity, left identity, minimum/minimum,
maximum/maximum, minimum/maximum, mixed signs, sparse and alternating signs.
The suite includes 82 directed cases, 45 random cases and 42 full-size cases.

Selected patterns are checked with independent mathematical properties.
Export/layout checks cover all generated cases. The test suite does not compare
all 127 answers with independently hand-calculated matrices. Expected values
are intended for later RTL comparison; generating a case does not mean an RTL
array has simulated it.

## Unsigned 4x4 tile test

Both candidate RTL circuits receive the same A/B pair. The testbench builds the
expected answer by repeated addition, then checks each circuit separately.
All 16*16 pairs are tested. See [running instructions](../tb/README.md).

## Integration checks to add

1. Decoder: signs, magnitude endpoints, ignored upper bits and reserved mode.
2. Shared multiplier: enabled/disabled operation, INT4/INT8 pairs and INT16
   boundary/random cases against Python; compare BASIC and HSM configurations.
3. MAC: product latency, sign extension, accumulation, reset, clear and bubbles.
4. PE: forwarding, valid alignment, enable/stall behavior and mode boundaries.
5. Array: input skew, complete matrix results and documented output timing.

Power optimizations also need evidence that inactive logic's activity decreases
while outputs and protocol behavior remain correct. Numerical agreement alone
does not measure switching power or establish timing closure.
