# Precision-Scalable 16x16 Systolic Tensor Unit

A VLSI Design Laboratory project on the RTL design and power-aware implementation of a signed matrix-multiplication engine with INT4, INT8 and INT16 operand modes.

For compatible input matrices, the expected calculation is:

`C[i][j] = sum(A[i][k] * B[k][j] for k in range(K))`

The Python model provides expected numerical results and reproducible input vectors. The Verilog implementation will be checked against these results using hardware testbenches.

**Current milestone:** the Python model and the two unsigned 4x4 multiplier tiles are verified. The configurable signed multiplier, MAC, PE and complete array are the next implementation stages.

**Target:** 256 PEs in a 16x16 array, signed INT4/INT8/INT16 operands, and a 300 MHz clock. The clock rate and power savings remain targets until measured on the corresponding implementation.

## Start here

- [Python reference model and commands](reference_model/README.md)
- [Verilog design files](rtl/README.md)
- [Hardware testbenches](tb/README.md)
- [Synthesis scripts and constraints](synthesis/README.md)
- [Architecture notes and presentations](docs/README.md)
- [Selected verification and synthesis results](reports/README.md)
- [Implementation roadmap](docs/roadmap.md)

## Project goals

- Implement a 16x16 systolic matrix-multiplication engine.
- Support signed INT4, INT8 and INT16 operands.
- Evaluate the registered implementation against a 300 MHz timing target.
- Study precision-dependent activation and operand isolation.
- Check arithmetic correctness and hardware control behavior.
- Compare area, timing and power using documented synthesis settings.

These are design goals. Record achieved results in `reports/` with the tested source revision and tool settings.

## Repository organization

| Location | Contents |
| --- | --- |
| `reference_model/` | Python arithmetic model, editable runner and model tests |
| `rtl/` | Synthesizable Verilog/SystemVerilog design modules |
| `tb/` | Verilog/SystemVerilog testbenches and RTL checks |
| `synthesis/` | Synthesis scripts and timing constraints |
| `docs/` | Architecture diagrams, design notes and presentation sources |
| `reports/` | Selected test summaries and synthesis comparisons |
| `vectors/` | Regenerable test data; created by the command below and ignored by Git |
| `README.md` | Project overview and first commands |
| `.gitignore` | Patterns for generated files that should stay outside commits |
| `.github/workflows/verify.yml` | Automated Python and unsigned-tile checks after upload |

## Target architecture

Each PE will contain one shared multiplier assembled from sixteen unsigned 4x4 tiles. Runtime precision selects one tile for INT4, four tiles for INT8, or all sixteen for INT16. BASIC and HSM are alternative implementations of a tile.

The planned datapath is signed-input decoding, unsigned tile products, weighted CSA reduction, final product reconstruction and sign restoration, followed by registered accumulation. A moves right and B moves down between neighbouring PEs.

The tile grid and the PE array are different levels of the design. See the [architecture notes](docs/architecture.md) for the widths and planned control boundaries.

## Current reference-model status

- Signed INT4, INT8 and INT16 arithmetic is implemented.
- Compatible rectangular matrices with each dimension from 1 to 16 are supported by the arithmetic functions.
- Square 2x2, 4x4 and 16x16 cases are generated for all three modes.
- The deterministic vector suite contains **127 matrix cases**, including **42 full 16x16 cases**.
- The supplied Python test file contains **13 test methods** with multiple assertions and input cases.
- These 13 test methods passed when rechecked on 18 October 2026.

## Current hardware status

| Block | Status | Evidence or next action |
| --- | --- | --- |
| BASIC unsigned 4x4 tile | Verified in RTL simulation | All 256 unsigned input pairs |
| HSM unsigned 4x4 tile | Verified in RTL simulation | Same 256 pairs; independent repeated-addition expectation |
| Precision/sign decoder | Next integration step | Select signed fields and form unsigned magnitudes |
| Configurable tiled multiplier | Planned | Tile isolation, CSA reduction and sign restoration |
| Registered MAC and PE | Planned | Accumulation, valid/control handling and operand forwarding |
| 16x16 systolic array | Planned | Input sequencing and comparison with the Python matrix answers |
| Synthesis and activity-based power comparison | Pending for the documented implementations | Publish scripts, constraints, configuration and matching reports |

See the [verification record](reports/verification/2026-10-18.md). The verification workflow in this update is ready to run on GitHub once uploaded; a hosted CI run has not yet been recorded here.

## Run the Python model

Install Python 3. The three Python files use the standard library and need no additional packages.

Run these commands from the repository's top-level folder:

```bash
# Enter your own matrices by editing PRECISION, A and B in this file.
python3 reference_model/run_my_reference.py

# Check the Python reference model.
python3 reference_model/test_tensor_matrix_reference.py

# Display the built-in 16x16 example in INT8 mode.
python3 reference_model/tensor_matrix_reference.py --array-demo --precision 8

# Generate reproducible test data for every precision.
python3 reference_model/tensor_matrix_reference.py --generate --output-dir vectors
```

On Windows, replace `python3` with `py` if you use the Python launcher.

The editable runner currently prints:

```text
Expected C = A x B:
[13, 22]
[-7, -10]
```

It also saves `reference_model/my_reference_output.json`. Both that file and generated vector folders are ignored by the included `.gitignore`.

## Precision and output format

| Precision | Raw-bus mode code | Signed operand range |
| --- | --- | --- |
| INT4 | 0 | -8 to 7 |
| INT8 | 1 | -128 to 127 |
| INT16 | 2 | -32768 to 32767 |

Mode 3 is reserved. The public Python API uses `precision=4`, `8` or `16`; the raw-bus functions use mode codes 0, 1 or 2.

Raw input words are 16 bits wide. The selected lower 4, 8 or 16 bits are interpreted as a signed two's-complement operand. Expected matrix sums use exact Python integers; exported result fields are signed 36-bit values.

## Verification workflow

1. Generate the selected inputs and expected outputs in Python.
2. Apply those inputs to the corresponding RTL testbench.
3. Check each hardware result against the expected Python value.
4. Check hardware-specific behavior such as reset, valid signals, stalls, clear and output timing in the RTL testbench.
5. Record the simulator, source revision, command and result.

Passing Python tests validates the reference-model checks. Hardware correctness requires RTL simulation and comparison.

The current unsigned-tile testbench checks both candidates against repeated addition. Integration with the Python matrix-vector interface is a later milestone. The [verification guide](docs/verification.md) explains the distinct test counts and checking methods.

## Development conventions

- Use one descriptive filename for each module; normally match the module name.
- Keep testbenches in `tb/` and name them `<module>_tb.v` or `<module>_tb.sv`.
- Edit and commit existing files instead of making `final2`, `new` or `latest` copies.
- Add a short README entry with a module's purpose, interface and tested command when adding it.
- Keep reusable scripts in Git and regenerate temporary outputs locally.

After each implementation step, update the relevant folder guide, run its checks, record the result and make a descriptive commit. Keep implementation status separate from measured performance.

## Team

- Ram Siddardha Tammireddi
- Pruthvi Raj L.

VLSI Design Laboratory, IIT Delhi. Guides: Prof. Kaushik Saha and Prof. Jayadeva.

## Study reference

The HSM tile is based on the difference-of-squares approach studied in [US7873823B2](https://patents.google.com/patent/US7873823B2/en). Performance claims for a patent implementation are separate from measurements of this repository's RTL.
