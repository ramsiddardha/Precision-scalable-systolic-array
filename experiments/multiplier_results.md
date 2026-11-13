# 4×4 Multiplier Selection

The standalone unsigned 4×4 multipliers were synthesized in Cadence Genus
using TSMC65 LP typical and a 3.333 ns virtual clock. Power estimates are
pre-layout and vectorless. Cell area is reported in Genus library units.

## 1. Initial multiplier comparison

| Architecture | Mapped cells | Cell area | Data-path delay (ns) | Setup slack (ns) | Switching power (µW) | Total power (µW) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Direct multiplication (`a * b`) | 52 | 119.880 | 0.525 | +2.308 | 8.753 | 19.700 |
| Dadda | 55 | 119.520 | 0.586 | +2.246 | 9.820 | 20.715 |
| **Wallace** | **46** | **115.560** | 0.599 | +2.234 | 8.961 | 21.119 |
| Braun array | 47 | 119.520 | 0.685 | +2.148 | 9.395 | 22.081 |
| Radix-4 Booth | 70 | 168.480 | 0.833 | +2.000 | 16.159 | 37.220 |

Wallace was selected for further optimization because it had the smallest
mapped cell area among the five candidates shown and met the setup constraint.

## 2. Initial Wallace versus final Wallace tile

| Metric | Initial Wallace + ripple carry | Final Wallace + vector prefix | Change |
| --- | ---: | ---: | ---: |
| Mapped cells | 46 | 34 | −26.1% |
| Cell area | 115.560 | 109.440 | −5.3% |
| Data-path delay | 0.599 ns | 0.611 ns | +12 ps |
| Setup slack | +2.234 ns | +2.222 ns | −12 ps |
| Internal power | 12.15070 µW | 10.97280 µW | −9.7% |
| Switching power | 8.96142 µW | 6.81352 µW | −24.0% |
| Dynamic power | 21.11212 µW | 17.78632 µW | −15.8% |
| Leakage power | 6.69792 nW | 6.98561 nW | +4.3% |
| Total power | 21.1188 µW | 17.7933 µW | −15.7% |

Both implementations use three Wallace compression levels. The initial
design adds the final two rows with a ripple-carry chain. The final design
uses an explicit 8-bit vectorized Kogge–Stone-style prefix adder with
carry-combine spans of 1, 2, and 4 bits.

We selected Wallace + vector prefix as the shared unsigned 4×4 tile for the
signed PE multiplier. It reduced switching power by 24.0% and mapped area by
5.3%, with a 12 ps increase in data-path delay and +2.222 ns setup slack.
