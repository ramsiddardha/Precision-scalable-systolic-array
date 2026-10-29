# RTL testbenches

This folder contains simulation sources for individual arithmetic blocks and the complete single processing element (PE). Synthesizable design sources are in [rtl/](../rtl/).

Compile one selected testbench top with its required design sources. Testbench files are simulation inputs; the Genus design-source list should contain RTL, not testbenches.

## Complete-PE testbenches

| File and simulation top | Main role | Expected-data source | Additional dependency |
| --- | --- | --- | --- |
| [systolic_pe_python_tb.sv](systolic_pe_python_tb.sv) — `systolic_pe_python_tb` | Compare PE state before and after every sampled edge with Python expectations | A dedicated Python-generated cycle-vector file | Matching PE cycle-vector generator and its output |
| [pe_combined_equivalence_tb.sv](pe_combined_equivalence_tb.sv) — `pe_combined_equivalence_tb` | Compare the optimized BASIC PE with the earlier reference PE and an independent scoreboard | Signed 64-bit arithmetic and token scoreboard inside the bench | RTL defining `systolic_pe_signed_reference` and its dependencies |
| [systolic_pe_power_tb.sv](systolic_pe_power_tb.sv) — `systolic_pe_power_tb` | Exercise one PE for per-precision switching activity, while checking sums and gated clocks | Deterministic stimulus and signed arithmetic inside the bench | Current PE RTL; external Tcl only if using the Vivado-controlled VCD-export flow |

These three benches operate on **one complete PE**, including forwarding registers, multiplier, product register and accumulator. They are separate from full 16x16-array verification.

## Python-versus-RTL verification

The Python bench reads stimulus and all expected arithmetic/control results from a cycle-vector file. It performs no reference multiplication or reference accumulation itself.

Each vector row supplies the controls, operands, expected pre-edge state, expected post-edge state and whether to perform a high-phase clock-gating probe.

It compares a 166-bit observation containing:

- Forwarded A/B values, valid bits and stored precision.
- Accumulator value, mode, term count, completion and protocol error.
- Registered product, its precision and valid bit.
- Combinational multiplier product and enabled-tile mask.

Four-state comparison rejects unexpected X/Z values in observed results. A high-phase probe changes controls while the source clock stays high, then verifies that the 118 observed storage-state bits remain unchanged. Combinational multiplier outputs are excluded from that storage check.

### Required vectors and paths

| Runtime option | Default path | Meaning |
| --- | --- | --- |
| `+VECTORS=...` | `vectors/vectors.txt` | Python-generated cycle stimulus and expected states |
| `+RESULTS=...` | `results/rtl_results.csv` | Observed pre/post samples |
| `+STATUS=...` | `results/simulation_status.txt` | RUNNING, PASS or FAIL summary |
| `+VCD=...` | Disabled unless supplied | Optional DUT waveform dump |

Create the output directory before running. The vector file starts with a row count; each following row has the twelve fields read by the testbench.

**Dependency:** the matching cycle-vector generator is separate from these uploaded testbench files. The source refers to `verification/reference_model.py:FIELDS` for the packed observation order. That generator is not currently included in this repository.

The matrix-reference scripts in [reference_model/](../reference_model/) calculate matrix answers and export matrix-format vectors. Their existing exports do not directly supply this bench's cycle/control-vector format.

### Example run

From the repository root, with Icarus Verilog installed and compatible cycle vectors already generated:

```bash
mkdir -p build results
iverilog -g2012 -s systolic_pe_python_tb \
  -o build/pe_python.vvp rtl/*.v tb/systolic_pe_python_tb.sv

vvp build/pe_python.vvp \
  +VECTORS=vectors/vectors.txt \
  +RESULTS=results/rtl_results.csv \
  +STATUS=results/simulation_status.txt
```

Add `+VCD=results/pe_python.vcd` to the simulation command when waveforms are needed. The default PE architecture is BASIC (`USE_HSM=0`) and the default clock period is 3.333 ns.

Expected successful log prefix:

```text
PYTHON-GOLDEN PE TEST PASSED:
```

The counts printed afterward depend on the generated vector suite.

## Optimized-versus-reference simulation

The equivalence bench instantiates:

- `systolic_pe_signed_reference` as `dut_reference`.
- The current `systolic_pe_signed` as `dut_candidate`.

Both instances use `USE_HSM=0`. The bench generates **90 sixteen-term frames**, cycling through INT4, INT8 and INT16: 30 frames per mode and 1,440 generated arithmetic pairs, plus directed control scenarios.

Independent arithmetic produces expected products and prefix sums. A separate token scoreboard checks forwarding, pipeline alignment, stalls, bubbles, clear/reset, one-sided valid streams, precision changes, extra terms and sticky errors.

**Dependency:** the earlier reference implementation and all its required modules must be compiled alongside the current RTL. The current `rtl/` folder does not define `systolic_pe_signed_reference`; adding this bench alone does not make that comparison runnable.

This is finite simulation-based equivalence checking. It is not a formal equivalence proof or exhaustive coverage of all possible frames.

Add `+DUMP_VCD` when running to write `systolic_pe_signed.vcd`. That dump includes the equivalence bench's hierarchy, including the reference and candidate instances.

Expected successful message:

```text
COMBINED OPTIMIZED PE EQUIVALENCE TEST PASSED (USE_HSM=0)
```

## Power workload and VCD activity

The power bench is self-contained with the current PE RTL: it needs no Python program or external vector file.

It uses deterministic operands with directed corner cases, checks running sums and forwarding, verifies tile masks, and counts precision-dependent register-clock edges. It also checks the optimized INT4 accumulator guard-field clock against independent signed addition.

| Setting | Default | Meaning |
| --- | --- | --- |
| `USE_HSM` parameter | `0` | BASIC PE; this workload rejects nonzero values |
| `CLOCK_PERIOD_NS` parameter | `3.333` | Keep consistent with the synthesis configuration |
| `+POWER_MODE=0` | `0` | INT4 workload |
| `+POWER_MODE=1` | — | INT8 workload |
| `+POWER_MODE=2` | — | INT16 workload |
| `+NUM_FRAMES=100` | `100` | Number of complete sixteen-term frames |

Each frame contains one clear cycle, sixteen input cycles and two pipeline-drain cycles: **19 source-clock periods per frame**. At the default frame count, each precision run exercises 1,600 products.

### Portable VCD example

The bench's portable dump is enabled only when compiled with `PE_PORTABLE_DUMP`. The runtime `VCD_FILE` option chooses the output filename.

```bash
mkdir -p build results
iverilog -g2012 -DPE_PORTABLE_DUMP -s systolic_pe_power_tb \
  -o build/pe_power.vvp rtl/*.v tb/systolic_pe_power_tb.sv

vvp build/pe_power.vvp +POWER_MODE=0 +NUM_FRAMES=100 \
  +VCD_FILE=results/pe_int4.vcd
vvp build/pe_power.vvp +POWER_MODE=1 +NUM_FRAMES=100 \
  +VCD_FILE=results/pe_int8.vcd
vvp build/pe_power.vvp +POWER_MODE=2 +NUM_FRAMES=100 \
  +VCD_FILE=results/pe_int16.vcd
```

The simulation checks remain active while recording. A successful run prints `PE POWER TEST PASSED:` with its precision, architecture and frame/product counts.

### Vivado and Genus flow

The original Vivado-controlled flow exports VCD through a separate Tcl script. That script is not among these three uploaded files. Keep `PE_PORTABLE_DUMP` disabled when that script owns VCD recording.

The bench exposes `capture_ready` and `capture_done` markers. The intended activity interval starts at `4*CLOCK_PERIOD_NS` and ends at `(4 + 19*NUM_FRAMES)*CLOCK_PERIOD_NS`, excluding reset/warm-up and including frame clears, inputs and drains.

For power comparison:

1. Simulate one precision mode per run using the same architecture, clock period, frame count and workload settings.
2. Export activity for the DUT instance `systolic_pe_power_tb.dut`.
3. Synthesize the corresponding `systolic_pe_signed` RTL in Genus with matching parameters and timing constraints.
4. Annotate the VCD with the correct DUT-to-design hierarchy mapping; inspect annotation coverage and unmapped signals.
5. Record the library corner, constraints, workload, activity interval and resulting power report.

A VCD records signal transitions. Genus combines annotated activity with the mapped cells and library data to estimate power. The testbench itself is not synthesized.

## Existing unsigned-tile verification

| Source file | Simulation top | Designs checked |
| --- | --- | --- |
| [unsigned_4bit_multiplier_tb.v](unsigned_4bit_multiplier_tb.v) | `unsigned_4x4_compare_tb` | BASIC and HSM unsigned 4x4 tiles |

This testbench applies all `16*16 = 256` unsigned input pairs. Both circuits are compared against independent repeated addition. Its `#1` settling delay does not measure physical circuit delay.

From the repository root:

```bash
mkdir -p build
iverilog -g2012 -s unsigned_4x4_compare_tb -o build/tiles.vvp \
  rtl/unsigned_basic_4bit_multiplier.v \
  rtl/unsigned_hsm_4bit_multiplier.v \
  tb/unsigned_4bit_multiplier_tb.v
vvp build/tiles.vvp
```

Expected successful message:

```text
PASS: all 256 input pairs matched for BASIC and HSM.
```

In Vivado, add the two tile files as design sources, add this bench as a simulation source, select `unsigned_4x4_compare_tb` as the simulation top and run the behavioral simulation.

The other existing block-level benches remain in this folder. Select their own tops and supply their required dependencies when running them.

## Verification records

Record the source revision, simulator, command, vector seed/profile, frame counts and actual result for each run. Compiling a bench or uploading a previous passing bench does not establish that the current repository passes it.

The uploaded testbench contents are preserved. This update documents their roles and dependencies; it does not add generated vector files, waveform dumps, reference-model RTL or Genus reports.
