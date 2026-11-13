# Single-PE Comparison

The three PEs were evaluated in Genus at a 3.333 ns clock period. Power
values are pre-layout estimates based on RTL VCD activity. Where a row
has three values, the order is INT4 / INT8 / INT16.

| Metric | BK-PE | LS-PE (Baseline) | LS-PE (Group Ripple) |
| --- | ---: | ---: | ---: |
| Mapped cells | 1,987 | 2,062 | 2,047 |
| Mapped cell area (library units) | 5,958.36 | 5,847.48 | 5,830.20 |
| Critical data-path delay (ns) | 2.793 | 2.774 | 2.774 |
| Setup slack (ps) | +250 | +250 | +250 |
| **INT4 total power (mW)** | 0.7515 | 0.4577 | **0.4518** |
| **INT8 total power (mW)** | 1.5522 | 1.0532 | **1.0464** |
| **INT16 total power (mW)** | 2.5390 | 2.4781 | **2.4626** |
| Internal power (mW) | 0.4416 / 0.9278 / 1.5158 | 0.3237 / 0.7194 / 1.6453 | 0.3200 / 0.7160 / 1.6390 |
| Switching power (mW) | 0.3094 / 0.6239 / 1.0227 | 0.1338 / 0.3336 / 0.8325 | 0.1315 / 0.3300 / 0.8233 |
| Dynamic power (mW) | 0.7510 / 1.5517 / 2.5385 | 0.4574 / 1.0530 / 2.4778 | 0.4515 / 1.0461 / 2.4623 |
| Leakage power (µW) | 0.488 / 0.505 / 0.523 | 0.282 / 0.289 / 0.302 | 0.282 / 0.289 / 0.300 |
| Total power change versus BK-PE | Reference | −39.1% / −32.1% / −2.4% | −39.9% / −32.6% / −3.0% |

Both LS-PE variants reported lower total power than BK-PE in all three
modes.

We carried both LS-PE variants forward to array-level analysis.
LS-PE (Baseline) serves as the integration reference. LS-PE (Group
Ripple) changes the accumulator carry network and reduces single-PE
total power by 0.6–1.3% across the three modes at the same reported
setup slack.
