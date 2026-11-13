## Latest SA16 designs

Both designs implement a 16×16 output-stationary systolic array for
signed INT4, INT8, and INT16 matrix multiplication. Each includes
LS-PE (Baseline) and LS-PE (Group Ripple).

| Design | Input handling |
| --- | --- |
| [Buffered SA16](designs/SA16_BUFFERED_BASELINE_GROUP_RIPPLE/README.md) | Loads matrices into A/B buffers and schedules operands into the mesh. |
| [On-chip-skew SA16](designs/SA16_ONCHIP_SKEW_BASELINE_GROUP_RIPPLE/README.md) | Streams operands into on-chip skew registers that align the input lanes. |
## Design selection and results

- [4×4 multiplier selection](experiments/multiplier_results.md) — five multiplier candidates, followed by the Wallace ripple-carry and vector-prefix comparison.
- [Single-PE comparison](experiments/pe_results.md) — BK-PE, LS-PE (Baseline), and LS-PE (Group Ripple).

### Array gate-level power

| Design | Synthesis clock | Analysis clock | Results |
| --- | ---: | ---: | --- |
| Buffered SA16 | 3.000 ns | 3.000 ns | [308-cycle results](results/buffered_array_3ns_gate_phase_summary.csv) |
| Buffered SA16 | 3.000 ns | 3.3333 ns | [308-cycle results](results/buffered_array_mapped_3ns_gate_phase_at_3p3333_summary.csv) |
| On-chip-skew SA16 | 3.000 ns | 3.3333 ns | [51-cycle results](results/onchip_gate_3p3333_summary.csv) |
