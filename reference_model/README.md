# Python functional reference model

The model calculates the expected signed matrix result independently of the
hardware multiplier architecture:

`C[i][j] = sum(A[i][k] * B[k][j] for k in range(K))`

It is the numerical answer key for future RTL comparisons. It uses Python
arithmetic rather than reproducing HSM tiles, CSA wiring, registers or clock
cycles. The Python functions support compatible rectangular matrices whose
individual dimensions are from 1 through 16.

## The three files

| File | Role |
| --- | --- |
| `run_my_reference.py` | Editable inputs; calls the model, prints C and saves the selected example |
| `tensor_matrix_reference.py` | Arithmetic, input encoding/decoding and deterministic vector export |
| `test_tensor_matrix_reference.py` | Checks the model, signed formats, invalid inputs and exported layouts |

Keep these names and keep the files together so the existing imports work.
Python 3 is required; all dependencies are in its standard library. Local
validation used Python 3.12.14. The supplied CI configuration selects Python 3.12.

## Choose your inputs

Edit these settings in `run_my_reference.py`:

```python
PRECISION = 4
USE_FULL_ARRAY_EXAMPLE = False
A = [[-5, 6], [2, -3]]
B = [[1, -2], [3, 2]]
```

Use precision 4, 8 or 16. Each entry must be in the corresponding signed range:
INT4 -8..7; INT8 -128..127; INT16 -32768..32767. A's column count must match
B's row count. Matrix dimensions and operand precision are independent choices.

From the repository root in Windows PowerShell:

```powershell
py .\reference_model\run_my_reference.py
```

The example returns `[[13, 22], [-7, -10]]` and saves the inputs and result to
`reference_model/my_reference_output.json`. That generated file is ignored by Git.
On Linux/macOS, use `python3 reference_model/run_my_reference.py`.

## Validate the reference model

```powershell
py .\reference_model\test_tensor_matrix_reference.py
```

Expected final status: `Ran 13 tests` followed by `OK`. These are thirteen
test methods containing many checks, not thirteen input pairs.

To run only the exhaustive raw-word decoding test:

```powershell
py -m unittest discover -s reference_model -p test_tensor_matrix_reference.py -k test_decode_against_signed_byte_interpretation -v
```

It checks 65,536 raw input words in each of three modes: 196,608 decoding
comparisons. It does not exhaustively test matrix multiplication.

## Full-size demo and vector export

```powershell
py .\reference_model\tensor_matrix_reference.py --array-demo --precision 8
py .\reference_model\tensor_matrix_reference.py --generate --output-dir vectors
```

Replace `py` with `python3` and use forward slashes on Linux/macOS.
The export contains all three precisions, irrespective of the displayed demo's
precision. It generates 127 matrix cases: 82 directed and 45 reproducible random
cases, including 42 full 16x16 cases. The default seed is 20261008.

JSON stores the case descriptions and expected answers. The seven `.mem` files
store individual operand/result words and packed full-array data for compatible
RTL testbenches. Generate them locally rather than committing repeated copies.
See the [verification guide](../docs/verification.md) for coverage details.

## Scope

Signed operand interpretation and exact numerical results are modeled. Exported
results use 36-bit signed fields. Pipeline latency, reset/clear behavior, valid
signals, stalls, switching power, area and timing closure require RTL/tool checks.
