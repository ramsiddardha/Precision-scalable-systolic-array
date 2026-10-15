"""Editable inputs for the project's signed Python reference model.

Edit PRECISION, A and B below. Set USE_FULL_ARRAY_EXAMPLE to True to run the ready-made 16x16 example.
"""

# This runner supplies signed numbers to the reference calculation in the second file.
# It displays the returned matrix and saves the selected example as JSON.

import json                  # helps save inputs and outputs in a readable file
from pathlib import Path     # helps identify where the file should be saved
 
# Import makes the calculation function available here; the actual call appears below.

from tensor_matrix_reference import reference_model # reference model function is called from our second python file


# Choose 4, 8 or 16 operand bits.
# Precision sets each operand's allowed signed range, independently of matrix dimensions.
# INT4: -8..7; INT8: -128..127; INT16: -32768..32767.
PRECISION = 4

USE_FULL_ARRAY_EXAMPLE = False
# False: use the A/B lists below. True: use the 16x16 example below them.

# These are the inputs you can edit.
# A's column count must equal B's row count for matrix multiplication.
A = [
    [-5, 6],
    [2, -3],
]

B = [
    [1, -2],
    [3, 2],
]

# The indented block runs only when the option is True and constructs fresh matrices.
# The inner comprehension builds a row; the outer comprehension builds sixteen rows.
if USE_FULL_ARRAY_EXAMPLE:
    
    A = [[1 for j in range(16)] for i in range(16)]            # A has sixteen rows, each with sixteen entries equal to 1.

    B = [[j - 8 for j in range(16)] for i in range(16)]        # B has sixteen identical rows: [-8, -7, ..., 7].

# Each C[i][j] is the sum over k of A[i][k] * B[k][j].
# Input precision restricts operands; accumulated outputs can require more bits.
C_expected = reference_model(A, B, precision=PRECISION)        # Calculate all expected output values.

# Display the chosen precision and each matrix row in the PowerShell terminal.
# str(PRECISION) converts the integer into text for joining to the printed label.
print("Signed input precision: INT" + str(PRECISION))
print("A:")
for row in A:
    print(row)
print("B:")
for row in B:
    print(row)
print("Expected C = A x B:")
# The multiplication has already finished; this loop displays its returned rows.
for row in C_expected:
    print(row)

# Keep the inputs and answer together for a demonstration or RTL comparison.
# __file__ locates this script; resolve() obtains its full path and parent selects its folder.
# The Path / filename operation joins paths, placing the JSON beside this script.
output_file = Path(__file__).resolve().parent / "my_reference_output.json"
# Build a dictionary containing the precision, original inputs and expected answer.
# json.dumps converts that dictionary into text; indent=2 makes the saved text readable.
# write_text saves the text and replaces the previous example file on the next run.
# UTF-8 specifies text-file encoding; operand bit encoding is handled in the second file.
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
    encoding="utf-8",   # We specify it so the saved file uses a consistent text format across Windows and Linux.
)
# Display the file location so the saved example can be opened for inspection.
print("Saved inputs and expected output to:", output_file) #This displays the output path so you can find and open the JSON file.
