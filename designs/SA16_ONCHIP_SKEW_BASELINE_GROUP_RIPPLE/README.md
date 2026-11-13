# SA16 mesh with on-chip input skew

The synthesis top is `systolic_array_skew_top`. Baseline and Group Ripple
share the 16×16 mesh controller and input skewer. They differ in
`13.cla_prefix_36.v`, the carry network between 4-bit groups in each PE's
accumulator. The modes are signed INT4, INT8, and INT16.

## Interface and schedule

Pulse `start` when `start_ready` is high. The controller captures `mode`
and clears the mesh and skew-valid pipeline. For each of the first 16 RUN
steps, present a pair of 256-bit vectors before the rising edge with
`input_ready=1`. For step `k`, put `A[i][k]` in A lane `i` and `B[k][j]`
in B lane `j`. Lane 0 occupies bits 15:0 of each vector. Narrow signed
operands use the low 4 or 8 bits of each 16-bit lane with the upper bits
zero. The testbench drives all lanes with the same `k` on each input edge.

The hardware delays lane `i` by `i` enabled RUN steps, with shared
clock gating per delay stage. The mesh sees skewed operands for RUN
steps 0–30 and drains through RUN step 47. Keep `step_enable=1` for
the measured workload. Sample results when `done=1` and `error=0`.
The measured matrix spans 51 cycles, comprising start, clear, 48 RUN
cycles, and check. The first 16 RUN cycles consume the unskewed vectors.
Input traffic uses a 512-bit aggregate data interface.

The testbench checks every lane's skewed operands and valid bit on all
48 RUN steps. It checks all 256 signed dot products at completion.
The default capture records 10 matrices, 510 clock cycles, and 40,960
checked MACs per variant and precision. Both variants use the same seed
and vector schedule.

## 1. Capture activity in Vivado 2024.1

Extract the ZIP. In the Vivado Tcl Console, use the actual extracted path.

```tcl
set env(SA_PERIOD) 3.333
source {C:/path/to/SA16_ONCHIP_SKEW_BASELINE_GROUP_RIPPLE/01_RUN_VIVADO.tcl}
```

Set `env(SA_PERIOD)` to `3.000` and source the launcher again for the other
period. The Windows batch launcher `01_RUN_VCD_WINDOWS.cmd` accepts
`SA_PERIOD` from Command Prompt and defaults to 3.333 ns.

Wait for the message reporting six checked VCD captures for each period.
The VCD and matching `_runinfo.txt` for each precision are under
`variants/<variant>/activity/3p333/` or `variants/<variant>/activity/3ns/`.
Transfer the package and its activity directories in binary mode.

## 2. Synthesize and run time-based power in Genus 23

Use the dirac1 tmux pane where `GENUS_BIN` is set. Run from the extracted
project root.

```bash
bash 02_RUN_GENUS.sh --period 3.333 --time-based
bash 02_RUN_GENUS.sh --period 3.000 --time-based
```

Each variant is synthesized once per period with all three precision
modes available. Its three Joules power jobs use the resulting mapped
checkpoint and RTL-to-gate activity map. The flow checks the VCD source
checksums and measured schedule before synthesis, and checks annotation
and frame coverage before accepting time-based power.

Use `--check-captures` to validate the transferred files. The default
setup-margin optimization target is 250 ps and the CSV reports achieved
nominal slack. The constraints use the same TSMC65 LP typical library,
I/O assumptions, and nominal clock uncertainty as the previous comparison.

## Results

- `onchip_skew_array_<period>_time_based_summary.csv` reports timing,
  area, power, checked MACs, capture time, and energy per MAC.
- `runs/<period>/<variant>/synth/` contains the mapped netlist, timing,
  area, hierarchy, checkpoint, and activity map.
- `runs/<period>/<variant>/time_based/<mode>/` contains activity and
  power reports.

These pre-layout estimates cover the mesh, controller, and on-chip input
skewer over the 51-cycle schedule. For comparison, the earlier buffered
run measured the matrix-loading phase as part of its end-to-end window.
