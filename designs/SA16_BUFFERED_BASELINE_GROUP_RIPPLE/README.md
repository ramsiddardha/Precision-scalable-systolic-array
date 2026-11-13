# Buffered SA16 comparison

The synthesis top is `systolic_array_power_top`. Baseline and Group Ripple use
the same 16×16 mesh, controller, input sequencer, and two 256×16 A/B buffers.
Their only RTL difference is `13.cla_prefix_36.v`, the carry network between
4-bit groups in each PE's accumulator.

The RTL testbench writes A and B in row-major order. It checks the 256 outputs
against a signed matrix multiplication for every measured matrix. A measured
matrix takes 308 cycles with continuous loading: start, 256 paired writes,
mesh clear, 48 run cycles, completion check, and one cycle to return to IDLE.
An INT16 zero-matrix warm-up initializes every buffer bit before capture. It is
outside the measurement window. The default is 10 measured matrices, 3,080
clock cycles and 40,960 checked MACs per precision. Both variants use the same
seed and input schedule.

## 1. Capture the VCDs in Vivado 2024.1

Extract the ZIP. In the Vivado Tcl Console, set the period and source the
launcher using its actual path:

```tcl
set env(SA_PERIOD) 3.333
source {C:/path/to/SA16_BUFFERED_BASELINE_GROUP_RIPPLE/01_RUN_VIVADO.tcl}
```

Use `set env(SA_PERIOD) 3.000` and source the launcher again for 3.000 ns.
The Windows `01_RUN_VCD_WINDOWS.cmd` launcher is also included. It uses
`SA_PERIOD` from Command Prompt and defaults to 3.333 ns.

Wait for `DONE: 6 checked buffered-array VCD captures` for each period.
Keep each VCD with its `_runinfo.txt` file. They are under
`variants/<variant>/activity/3p333/` and `variants/<variant>/activity/3ns/`.
A successful capture writes a PASS sidecar with matching RTL, testbench, and
VCD checksums. Use binary transfer for the full project with its activity
directories. For a shorter pilot only, set `env(SA_MATRICES)` to `1` before
capture. Use the same matrix count for both variants and all modes.

## 2. Synthesize and report power in Genus 23

Use the tmux pane where `GENUS_BIN` already points to the working Genus 23
executable. Change to the extracted project root on dirac1. Use local scratch
for the working copy if the AFS timeout issue recurs.

```bash
bash 02_RUN_GENUS.sh --period 3.333
bash 02_RUN_GENUS.sh --period 3.000
```

Each command synthesizes each variant once with all precision modes available.
The three VCD-based average-activity power jobs per variant reuse that mapped
database. Both periods use TSMC65 LP typical and the same provisional I/O
constraints and nominal clock uncertainty as the previous mesh comparison.
The default optimization setup-margin target is 250 ps. The CSV separately
reports achieved nominal setup slack.

For the same Joules time-based method as the previous mesh study, add
`--time-based`. A completed matching synthesis checkpoint is reused:

```bash
bash 02_RUN_GENUS.sh --period 3.333 --time-based
bash 02_RUN_GENUS.sh --period 3.000 --time-based
```

The longer buffered capture increases the number of per-cycle power frames.
The VCDs, run directories, and summaries are separated by clock period.
A positional variant name runs just that variant and writes a separate
summary. Use `--check-captures` to validate the captures before starting Genus.

## Results

- `buffered_array_<period>_<method>_summary.csv` contains cell area, timing,
  power, checked MACs, capture time, and energy per MAC for the two variants.
- `runs/<period>/<variant>/synth/` contains the mapped netlist, constraints,
  timing, area, hierarchy, and the Genus checkpoint and native activity map.
- `runs/<period>/<variant>/<method>/<mode>/` contains the activity and power reports.

The measurements cover the full buffered DUT, including operand loading.
They are pre-layout power estimates based on RTL activity. The clock-period
tags are `3p333` and `3ns`. Preserve the summaries from scratch after a run.
