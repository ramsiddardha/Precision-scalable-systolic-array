# Verification Status

## Single-PE verification

The BASIC single PE (`USE_HSM=0`) passed Python-backed verification in Vivado XSim for INT4, INT8 and INT16.

Full-profile run with seed `20261029`:

| Check | Result |
|---|---:|
| Complete legal 16-term frames | 5,082 |
| Clocked cycles | 100,408 |
| Pre/post comparisons | 200,816 |
| Product and running-sum comparisons | 81,440 |
| High-phase state-hold checks | 3,478 |
| Mismatched samples | 0 |

## Coverage

- INT4: all 256 operand pairs.
- INT8: all 65,536 operand pairs.
- INT16: 11,643 distinct sampled operand pairs.
- Checks include forwarding, pipeline timing, stalls, bubbles, reset, clear, completion and expected protocol errors.

INT4/INT8 operand-pair coverage is exhaustive. Complete 16-term sequences and INT16 pair coverage are not exhaustive.

## Supporting checks

The PE Python reference passed nine sanity tests.

The checker detected three intentional RTL faults: incorrect product sign, early completion and unsafe combinational clock gating.

The earlier matrix reference model remains in `reference_model/`. Its tests and vector format are separate from the PE cycle model.

## Instructions and evidence

- [Run single-PE verification](../verification/README.md)
- [Understand the verification flow](VERIFICATION_EXPLAINED.md)
- [Recorded Vivado results](../reports/verification/single_pe/2026-10-29/)

Full-array RTL verification is a separate milestone. Timing and power require corresponding implementation reports.
