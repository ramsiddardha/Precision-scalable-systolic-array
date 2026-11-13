## Latest SA16 designs

Both designs implement a 16×16 output-stationary systolic array for
signed INT4, INT8, and INT16 matrix multiplication. Each includes
LS-PE (Baseline) and LS-PE (Group Ripple).

| Design | Input handling |
| --- | --- |
| [Buffered SA16](designs/SA16_BUFFERED_BASELINE_GROUP_RIPPLE/README.md) | Loads matrices into A/B buffers and schedules operands into the mesh. |
| [On-chip-skew SA16](designs/SA16_ONCHIP_SKEW_BASELINE_GROUP_RIPPLE/README.md) | Streams operands into on-chip skew registers that align the input lanes. |
