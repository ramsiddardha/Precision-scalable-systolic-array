# Precision-Scalable 16x16 Systolic Tensor Unit

A VLSI Design Laboratory project on the RTL design and power-aware implementation of a signed matrix-multiplication engine with INT4, INT8 and INT16 operand modes.

For compatible input matrices, the expected calculation is:

`C[i][j] = sum(A[i][k] * B[k][j] for k in range(K))`

The Python model provides expected numerical results and reproducible input vectors. The Verilog implementation will be checked against these results using hardware testbenches.

## Start here

- [Python reference model and commands](reference_model/README.md)
- [Verilog design files](rtl/README.md)
- [Hardware testbenches](tb/README.md)
- [Synthesis scripts and constraints](synthesis/README.md)
- [Architecture notes and presentations](docs/README.md)
- [Selected verification and synthesis results](reports/README.md)

## Project goals

- Implement a 16x16 systolic matrix-multiplication engine.
- Support signed INT4, INT8 and INT16 operands.
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

## Current reference-model status

- Signed INT4, INT8 and INT16 arithmetic is implemented.
- Compatible rectangular matrices with each dimension from 1 to 16 are supported by the arithmetic functions.
- Square 2x2, 4x4 and 16x16 cases are generated for all three modes.
- The deterministic vector suite contains **127 matrix cases**, including **42 full 16x16 cases**.
- The supplied Python test file contains **13 test methods** with multiple assertions and input cases.
- These 13 test methods passed when checked on 16 October 2026.

RTL implementation is in progress. Document each uploaded module and its actual verification status in `rtl/README.md` and `tb/README.md`.

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

## Development conventions

- Use one descriptive filename for each module; normally match the module name.
- Keep testbenches in `tb/` and name them `<module>_tb.v` or `<module>_tb.sv`.
- Edit and commit existing files instead of making `final2`, `new` or `latest` copies.
- Add a short README entry with a module's purpose, interface and tested command when adding it.
- Keep reusable scripts in Git and regenerate temporary outputs locally.
