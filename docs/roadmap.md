# Implementation roadmap

Status as of 18 October 2026. This tracks the implementation being developed
in this repository; it does not assign an arbitrary completion percentage.

| Stage | Status | Completion evidence |
| --- | --- | --- |
| Python functional reference model | Verified | 13 automated test methods pass |
| Deterministic matrix-vector generation | Implemented | 127 cases; export/layout checks pass |
| BASIC unsigned 4x4 tile | Verified | All 256 unsigned input pairs pass |
| HSM unsigned 4x4 tile | Verified | Same 256 pairs pass against independent expectations |
| Signed precision/magnitude decoder | Next integration step | Add RTL and boundary/raw-word tests |
| Tile-enable decoder and operand-isolation wrapper | Planned | Verify 1/4/16 enabled tiles and inactive behavior |
| CSA-based shared signed multiplier | Planned | Correct weighting, reconstruction, sign and all modes |
| Registered MAC | Planned | Product pipeline, 36-bit accumulation and control |
| PE with operand forwarding | Planned | Arithmetic and A/B/valid forwarding checks |
| Small array, then 16x16 array | Planned | Sequenced inputs and matrix comparison with Python |
| Comparable Genus runs | Planned | Scripts, SDC and matched BASIC/HSM configurations |
| Precision-dependent activity/power study | Planned | Matched workloads, VCD/SAIF and documented conditions |

The decoder package prepared separately is the next block to integrate after
review and simulation. Its sources are not yet part of this repository snapshot.

## Update discipline

For each stage, add the RTL and its testbench, document the command, record
the result under `reports/`, and update this table. Keep one logical change per
commit so earlier working stages can be identified in Git history.

Examples of commit messages:

- `Add signed precision decoder and boundary tests`
- `Add tile operand isolation for INT4 INT8 and INT16`
- `Add CSA reduction and signed product reconstruction`
- `Record matched Genus results for registered multiplier candidates`

Mark a feature verified only after its relevant checks pass. Mark a performance
target achieved only after the corresponding implementation has been measured.
