"""Editable inputs for the project's signed Python reference model.

Run: py run_my_reference.py
Edit PRECISION, A and B below. Set USE_FULL_ARRAY_EXAMPLE to True to run
the ready-made 16x16 example from our RTL demo.
"""

import json                  # helps save inputs and outputs in a readable file
from pathlib import Path     # helps identify where the file should be saved
 
from tensor_matrix_reference import reference_model # reference model function is called from our second python file


# Choose 4, 8 or 16 operand bits.
PRECISION = 4

USE_FULL_ARRAY_EXAMPLE = False
# False: use the A/B lists below. True: use the 16x16 example below them.

# These are the inputs you can edit.
A = [
    [-5, 6],
    [2, -3],
]

B = [
    [1, -2],
    [3, 2],
]

if USE_FULL_ARRAY_EXAMPLE:
    
    A = [[1 for j in range(16)] for i in range(16)]            # A has sixteen rows, each with sixteen entries equal to 1.

    B = [[j - 8 for j in range(16)] for i in range(16)]        # B has sixteen identical rows: [-8, -7, ..., 7].

C_expected = reference_model(A, B, precision=PRECISION)        # Calculate all expected output values.

print("Signed input precision: INT" + str(PRECISION))
print("A:")
for row in A:
    print(row)
print("B:")
for row in B:
    print(row)
print("Expected C = A x B:")
for row in C_expected:
    print(row)

# Keep the inputs and answer together for a demonstration or RTL comparison.
output_file = Path(__file__).resolve().parent / "my_reference_output.json"
output_file.write_text(
    json.dumps(
        {
            "precision_bits": PRECISION,
            "A": A,
            "B": B,
            "C_expected": C_expected,
        },
        indent=2,
    ) + "\n",
    encoding="utf-8",
)
print("Saved inputs and expected output to:", output_file)
