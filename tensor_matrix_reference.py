"""Independent matrix answers and input vectors for our tensor-unit project.

Run this file for a small example. Add --array-demo for the current 16x16 demo.
Add --generate to create the vector suite and packed RTL input/output files.
"""

# The arithmetic reference is independent of the hardware architecture.
# This file predicts numerical results; RTL simulation checks control and cycle behavior.
# argparse reads command options, json writes records, random creates test values, and Path handles files.
import argparse
import json                 # saves matrices and test info in a readable data file
import random               #generates repeatable random test inputs                  
from pathlib import Path    


# Mode codes used by the RTL: 0 = INT4, 1 = INT8, 2 = INT16. Mode 3 is reserved.
# Mode and width describe each number; matrix row and column counts are separate choices.
WIDTHS = {0: 4, 1: 8, 2: 16}
DEFAULT_SEED = 20261008 #starting setting for random generator,using same seed produces same test data 
# Fixed demonstration inputs for direct command-line runs and hand-calculated tests.
# These constants are separate from the editable A/B variables in run_my_reference.py.
DEMO_A = [[-3, 4], [2, -1]]
DEMO_B = [[2, -2], [3, 1]]


# Translate a valid mode into its operand width; callers also use this to validate a mode.
# subclasses.
def precision_width(mode):
    if type(mode) is not int or mode not in WIDTHS:
        raise ValueError("Use mode 0 (INT4), 1 (INT8), or 2 (INT16).")
    # Dictionary lookup: for example, mode 0 returns width 4.
    return WIDTHS[mode]


# Raw buses are unsigned bit patterns. Decode the selected lower field as a signed number.
# Example: raw 0x000D in INT4 selects 1101, which represents -3.
def decode_input(raw_value, mode):
    """Interpret the selected signed field of a raw 16-bit input bus."""
    width = precision_width(mode)
    # The physical input field is 16 bits, so its raw integer must be between 0 and 65535.
    if type(raw_value) is not int or not 0 <= raw_value <= 0xFFFF:
        raise ValueError("A raw input bus value must be an integer from 0 to 65535.")
    # A width-bit mask has ones only in the selected field: width 4 gives mask 0x000F.
    # AND removes unused upper bits before interpreting the operand's sign.
    value = raw_value & ((1 << width) - 1)
    # Values at or above 2**(width-1) have the selected field's sign bit set.
    # Subtracting 2**width recovers the negative value: 13 - 16 = -3 for INT4.
    if value >= (1 << (width - 1)):
        value = value - (1 << width)
    return value


# Convert one signed operand into the raw bit pattern placed on the RTL input bus.
# With upper_bits=0, -3 becomes 0x000D in INT4, 0x00FD in INT8, or 0xFFFD in INT16.
def encode_input(value, mode, upper_bits=0):
    """Put a signed value in its lower field; allow noise in unused bus bits."""
    width = precision_width(mode)
    # Enforce -2**(width-1) <= value < 2**(width-1), the selected signed input range.
    if type(value) is not int or not -(1 << (width - 1)) <= value < (1 << (width - 1)):
        raise ValueError("The signed input is outside the selected precision's range.")
    # Optional upper_bits is also a 16-bit pattern; test generators use it for unused-bit checks.
    if type(upper_bits) is not int or not 0 <= upper_bits <= 0xFFFF:
        raise ValueError("upper_bits must be a raw 16-bit value.")
    # Keep the selected field's low bits, including a negative operand's two's-complement pattern.
    field_mask = (1 << width) - 1
    # XOR with 0xFFFF makes the complementary upper-field mask; OR joins disjoint fields.
    # Example: value=-3, mode=0, upper_bits=0xABC0 produces the raw word 0xABCD.
    return (upper_bits & (0xFFFF ^ field_mask)) | (value & field_mask)
#This helps test whether the RTL correctly ignore unused upper bits

# Validate a nonempty rectangular integer matrix and return (row_count, column_count).
# Supporting dimensions up to 16 includes small unit cases and the complete 16x16 case.
def matrix_shape(matrix):
    """Check a nonempty integer matrix with dimensions at most 16."""
    # Validate the container and row count before accessing matrix[0].
    if not isinstance(matrix, (list, tuple)) or not 1 <= len(matrix) <= 16:
        raise ValueError("A matrix must have between 1 and 16 rows.")
    # The first row defines the column count; an empty row is invalid.
    if not isinstance(matrix[0], (list, tuple)) or not 1 <= len(matrix[0]) <= 16:
        raise ValueError("A matrix must have between 1 and 16 columns.")
    columns = len(matrix[0])
    # Every row must have the same length. any(...) detects any non-integer entry.
    for row in matrix:
        if not isinstance(row, (list, tuple)) or len(row) != columns:
            raise ValueError("All rows must have the same length.")
        if any(type(value) is not int for value in row):
            raise ValueError("Matrix entries must be integers.")
    # A caller can unpack the two returned dimensions into two variables.
    return len(matrix), columns


# Mathematical reference: C[i][j] = sum over k of A[i][k] * B[k][j].
# Python integers keep sums exact; this calculation does not wrap to the input precision.
def matrix_multiply(A, B):
    """Multiply signed integer matrices using the mathematical definition."""
    # A is rows x terms and B must be terms x columns; C will be rows x columns.
    rows, terms = matrix_shape(A)
    b_rows, columns = matrix_shape(B)
    if terms != b_rows:
        raise ValueError("The number of A columns must equal the number of B rows.")

    # Allocate a separate zero-filled list for each result row before accumulating
    # products.
    C = [[0 for j in range(columns)] for i in range(rows)]
    # i selects the output row; j selects the output column.
    for i in range(rows):
        for j in range(columns):
            # k pairs row i of A with column j of B and visits every contribution to this
            # output.
            for k in range(terms):
                # Multiply the next pair and add it to this output's running sum.
                C[i][j] = C[i][j] + A[i][k] * B[k][j]
    return C


# Public entry point for editable signed inputs: reference_model(A, B, precision=4/8/16).
# The default 16 applies only when the caller omits precision; the runner passes its choice.
def reference_model(A, B, precision=16):
    # Calculate C = A x B from signed inputs valid for INT4, INT8 or INT16.

    if type(precision) is not int or precision not in (4, 8, 16):
        raise ValueError("precision must be 4, 8 or 16.")
    # Translate the human-facing precision into the mode code used by the shared raw-bus path.
    mode = {4: 0, 8: 1, 16: 2}[precision]
    # Encode A first, encode B second, then interpret those buses and calculate C.
    # The round trip shares the input-format rules used by raw-vector tests.
    # Signed Python arithmetic itself needs no encoding; this route also validates operand
    # ranges.
    return reference_from_raw(encode_matrix(A, mode), encode_matrix(B, mode), mode)


# Entry point for already encoded buses, such as raw words supplied to an RTL testbench.
# Decode using the selected precision before performing mathematical multiplication.
def reference_from_raw(A_raw, B_raw, mode):
    """Apply the RTL bus interpretation, then calculate exact matrix answers."""
    # Validate the mode even before walking matrix entries; invalid modes raise ValueError.
    precision_width(mode)
    matrix_shape(A_raw)
    matrix_shape(B_raw)
    # Nested comprehensions visit each row and each entry, preserving the matrix shape.
    A = [[decode_input(value, mode) for value in row] for row in A_raw]
    B = [[decode_input(value, mode) for value in row] for row in B_raw]
    # Return the completed signed result through reference_model to its caller when used
    # there.
    return matrix_multiply(A, B)


# Apply the single-number encoder to every matrix entry while retaining its row/column layout.
# rng=None fills unused upper bits with zeros; a supplied generator varies those bits.
def encode_matrix(matrix, mode, rng=None):
    """Convert signed test data to raw buses, optionally varying unused bits."""
    precision_width(mode)
    matrix_shape(matrix)
    # The conditional chooses random 16-bit upper-bit candidates or zero for each operand.
    # Only unused bits are taken from that candidate; the selected signed field stays
    # correct.
    return [[encode_input(value, mode, rng.getrandbits(16) if rng else 0)
             for value in row] for row in matrix]


# A frame groups one operand per array input lane into one wide word.
# Full size: 16 lanes x 16 bits = 256 bits per A frame and per B frame.
def pack_input_frames(A_raw, B_raw):
    """Pack square-matrix raw words into the tensor_array input-frame format.

    In frame k, lane i carries A[i][k] and lane j carries B[k][j].
    Lane zero occupies bits [15:0]. The RTL supplies the boundary skew.
    """
    # This packing layout requires two equal square matrices; the arithmetic helper also supports rectangles.
    n, columns = matrix_shape(A_raw)
    if columns != n or matrix_shape(B_raw) != (n, n):
        raise ValueError("Frame packing requires two equal square matrices.")
    # Check A and then B. any(...) reports whether at least one raw entry exceeds its 16-bit slot.
    for matrix in (A_raw, B_raw):
        if any(not 0 <= value <= 0xFFFF for row in matrix for value in row):
            raise ValueError("Each raw input word must be from 0 to 65535.")
    # Plural names collect all frames; singular a_frame and b_frame hold the current frame only.
    a_frames, b_frames = [], []
    # Frame k contains column k of A and row k of B, matching the shared multiplication
    # index k.
    for k in range(n):
        # Reset each new frame word to zero so fields from the previous frame cannot carry
        # over.
        a_frame, b_frame = 0, 0
        for lane in range(n):
            # Shift each operand by its lane's starting bit; OR combines the
            # non-overlapping 16-bit slots.
            # Lane 0 occupies bits 15:0; lane 1 occupies bits 31:16; lane 15 occupies bits
            # 255:240.
            a_frame |= A_raw[lane][k] << (16 * lane)
            b_frame |= B_raw[k][lane] << (16 * lane)
        # append adds the completed integer as one list item, then the next k builds
        # another frame.
        a_frames.append(a_frame)
        b_frames.append(b_frame)
    return a_frames, b_frames


# Pack an already calculated output matrix into one integer with a 36-bit field per result.
# At 16x16 this gives 256 x 36 = 9216 bits, with C[0][0] in the lowest field.
def pack_result_matrix(C):
    """Encode C as row-major signed 36-bit fields for the c_matrix bus."""
    n, columns = matrix_shape(C)
    if columns != n:
        raise ValueError("Result-bus packing requires a square matrix.")
    packed = 0
    # A 36-bit all-ones mask converts negative results into their unsigned two's-complement
    # fields.
    mask = (1 << 36) - 1
    for i in range(n):
        for j in range(n):
            value = C[i][j]
            # Require the signed 36-bit range before encoding, so an oversized answer is
            # reported.
            if not -(1 << 35) <= value < (1 << 35):
                raise OverflowError("An expected result does not fit signed 36 bits.")
            # i*n+j numbers outputs row by row. Multiplying by 36 gives the field's
            # starting bit.
            # Encode the value, shift it into that field, and OR it into the combined
            # result word.
            packed |= (value & mask) << (36 * (i * n + j))
    return packed


# Build test inputs and their predicted numerical answers; RTL execution happens
# separately.
# Total: one fixed demo + 3 sizes x 3 modes x (9 directed + 5 random) = 127 matrix cases.
def make_cases(seed=DEFAULT_SEED):
    """Deterministic data for 2x2, 4x4 and 16x16 checks in every precision."""
    # A local seeded generator makes the same request reproducible without relying on
    # global random state.
    rng = random.Random(seed)
    cases = []

    # This nested helper records one case in the enclosing cases list when called below.
    def add_case(name, mode, A, B, use_upper_noise=True):
        # Optional upper noise deliberately varies unused bus bits; it is test data, not
        # electrical noise.
        A_raw = encode_matrix(A, mode, rng if use_upper_noise else None)
        B_raw = encode_matrix(B, mode, rng if use_upper_noise else None)
        # Keep identifying metadata, encoded inputs, and the expected signed result
        # together.
        cases.append({
            "name": name,
            "mode": mode,
            "precision_bits": precision_width(mode),
            "n": len(A),
            "A_raw": A_raw,
            "B_raw": B_raw,
            "C_expected": reference_from_raw(A_raw, B_raw, mode),
        })

    # Start with a recognizable hand-calculated demo; zero upper bits make its exported hex
    # easy to inspect.
    add_case("demo_int4_2x2", 0, DEMO_A, DEMO_B, use_upper_noise=False)

    # n selects matrix dimensions; each size is tested at INT4, INT8 and INT16
    # independently.
    for n in (2, 4, 16):
        # int(i == j) gives 1 on the diagonal and 0 elsewhere; identity and zeros have
        # known products.
        identity = [[int(i == j) for j in range(n)] for i in range(n)]
        zeros = [[0 for j in range(n)] for i in range(n)]
        for mode in (0, 1, 2):
            width = precision_width(mode)
            # Compute the selected signed input limits, such as lo=-8 and hi=7 for INT4.
            lo = -(1 << (width - 1))
            hi = (1 << (width - 1)) - 1
            # Exercise both endpoints, nearby values, zero and +/-1; modulo indexing
            # repeats this list safely.
            boundaries = [lo, lo + 1, -1, 0, 1, hi - 1, hi]
            # Different index expressions arrange the same boundary values differently in A
            # and B.
            A = [[boundaries[(i * n + j) % len(boundaries)]
                  for j in range(n)] for i in range(n)]
            B = [[boundaries[(3 * i + j + 2) % len(boundaries)]
                  for j in range(n)] for i in range(n)]
            # Uniform extreme inputs stress accumulated magnitude; output values may exceed
            # operand width.
            minimum = [[lo for j in range(n)] for i in range(n)]
            maximum = [[hi for j in range(n)] for i in range(n)]
            # Even i+j gives +1 and odd i+j gives -1, creating a predictable checkerboard
            # product.
            alternating = [[1 if (i + j) % 2 == 0 else -1
                            for j in range(n)] for i in range(n)]
            # Sparse inputs start at zero and get one nonzero entry each; only the last C
            # entry is nonzero.
            sparse_A = [[0 for j in range(n)] for i in range(n)]
            sparse_B = [[0 for j in range(n)] for i in range(n)]
            sparse_A[n - 1][0] = -1
            sparse_B[0][n - 1] = hi
            # Names such as int4_16x16_sparse identify the precision, size and input
            # pattern in logs.
            prefix = f"int{width}_{n}x{n}"
            # Directed cases: zero and identity products, three extreme combinations, mixed
            # signs, sparse and alternating.
            add_case(prefix + "_zeros", mode, zeros, B)
            add_case(prefix + "_identity_right", mode, A, identity)
            add_case(prefix + "_identity_left", mode, identity, B)
            add_case(prefix + "_all_min_min", mode, minimum, minimum)
            add_case(prefix + "_all_max_max", mode, maximum, maximum)
            add_case(prefix + "_all_min_max", mode, minimum, maximum)
            add_case(prefix + "_mixed_signs", mode, A, B)
            add_case(prefix + "_sparse", mode, sparse_A, sparse_B)
            add_case(prefix + "_alternating_signs", mode, alternating, alternating)
            # Add five reproducible random pairs per size/mode. randint includes both
            # signed endpoints.
            # The :02d formatting labels samples as 00, 01, 02, 03 and 04.
            for sample in range(5):
                A = [[rng.randint(lo, hi) for j in range(n)] for i in range(n)]
                B = [[rng.randint(lo, hi) for j in range(n)] for i in range(n)]
                add_case(prefix + f"_random_{sample:02d}", mode, A, B)
    # Return the collection of case dictionaries; no files have been written by this
    # function.
    return cases


# Export all cases as individual operand/result words and full-size cases as packed array
# buses.
# Offsets describe positions in combined files so a reader can locate each case.
def export_cases(destination, seed=DEFAULT_SEED):
    """Write row-major vectors and packed frames for the fixed 16x16 top."""
    destination = Path(destination)
    # Create missing parent folders and allow an existing output folder.
    destination.mkdir(parents=True, exist_ok=True)
    cases = make_cases(seed)
    # Individual-word lists contain all sizes. Packed-frame/result lists contain 16x16
    # cases only.
    A_words, B_words, C_words = [], [], []
    A_frames, B_frames, C_matrices, modes = [], [], [], []
    mac_operations = 0

    # Walk the recorded cases in order and add each case's entries to the combined lists.
    for case in cases:
        n = case["n"]
        # The starting offset counts words, not bytes. A 2x2 case adds four words to each
        # A/B/C list.
        case["word_offset"] = len(A_words)
        case["word_count"] = n * n
        # Flatten row by row; extend adds each entry separately rather than adding a nested
        # row list.
        A_words.extend(value for row in case["A_raw"] for value in row)
        B_words.extend(value for row in case["B_raw"] for value in row)
        C_words.extend(value for row in case["C_expected"] for value in row)
        # n*n outputs each contain n products: n**3 mathematical MACs, separate from RTL
        # cycle timing.
        mac_operations = mac_operations + n * n * n
        # This condition selects matrix size, so full-size cases in all three precisions
        # enter this block.
        if n == 16:
            packed_a, packed_b = pack_input_frames(case["A_raw"], case["B_raw"])
            # Frame offsets count 256-bit input frames; matrix offsets count complete
            # 9216-bit result words.
            # Each full-size case adds sixteen A/B frames and one packed C matrix.
            case["frame_offset"] = len(A_frames)
            case["frame_count"] = 16
            case["matrix_offset"] = len(C_matrices)
            # extend adds sixteen frame items; append below adds one packed matrix and one
            # mode item.
            A_frames.extend(packed_a)
            B_frames.extend(packed_b)
            C_matrices.append(pack_result_matrix(case["C_expected"]))
            modes.append(case["mode"])

    # Keep expected arithmetic exact; only the exported bit representation is encoded.
    if any(not -(1 << 35) <= value < (1 << 35) for value in C_words):
        raise OverflowError("An expected result does not fit the 36-bit result bus.")
    # This record describes the saved format and includes the cases with their newly
    # recorded offsets.
    # Version 2 describes this file layout; input/output word sizes describe the bus
    # representations.
    payload = {
        "format_version": 2,
        "seed": seed,
        "case_count": len(cases),
        "word_count_per_memory": len(A_words),
        "mac_operations": mac_operations,
        "input_word_bits": 16,
        "output_word_bits": 36,
        "layout": "row-major; each case follows the previous case in all three files",
        "full_array_case_count": len(C_matrices),
        "packed_frame_count": len(A_frames),
        # Layout strings document Verilog bit slices; they do not execute Verilog or model
        # clock cycles.
        "packed_layout": {
            "a_frame": "frame k: A[i][k] at bits 16*i +: 16",
            "b_frame": "frame k: B[k][j] at bits 16*j +: 16",
            "c_matrix": "C[i][j] at bits 36*(16*i+j) +: 36",
            "order": "16x16 cases only, in the same order as the cases array",
        },
        "cases": cases,
    }
    # Save the full record as readable JSON, including raw inputs and exact signed expected
    # results.
    (destination / "tensor_matrix_cases.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    # One 16-bit input word per line needs four hexadecimal digits; 04x pads leading zeros.
    # The .mem files are hexadecimal test data that a compatible RTL testbench can read.
    (destination / "tensor_A16.mem").write_text(
        "".join(f"{value:04x}\n" for value in A_words), encoding="ascii")
    (destination / "tensor_B16.mem").write_text(
        "".join(f"{value:04x}\n" for value in B_words), encoding="ascii")
    # Mask each signed result only when writing its 36-bit field; nine hex digits represent
    # 36 bits.
    (destination / "tensor_C36.mem").write_text(
        "".join(f"{value & ((1 << 36) - 1):09x}\n" for value in C_words),
        encoding="ascii")
    # A 256-bit frame needs 64 hex digits. Each line groups sixteen input operands.
    (destination / "tensor_A_frames256.mem").write_text(
        "".join(f"{value:064x}\n" for value in A_frames), encoding="ascii")
    (destination / "tensor_B_frames256.mem").write_text(
        "".join(f"{value:064x}\n" for value in B_frames), encoding="ascii")
    # A complete result word needs 9216/4 = 2304 hex digits; the lowest field is printed at
    # the right.
    (destination / "tensor_C_matrices9216.mem").write_text(
        "".join(f"{value:02304x}\n" for value in C_matrices), encoding="ascii")
    # One mode per packed full-array case, in matching case order. ASCII suffices for hex
    # text.
    (destination / "tensor_modes.mem").write_text(
        "".join(f"{value:x}\n" for value in modes), encoding="ascii")
    # Return metadata to the command-line caller and export tests after all files have been
    # written.
    return payload


# Display the fixed 2x2 example and explain each already calculated output using printed
# terms.
def show_demo(precision=4):
    print(f"MATRIX REFERENCE DEMO: INT{precision}, 2x2")
    print("A =", DEMO_A)
    print("B =", DEMO_B)
    # Calculate the numerical answer through the same public API used by the editable
    # runner.
    C = reference_model(DEMO_A, DEMO_B, precision)
    print("C =", C)
    for i in range(2):
        for j in range(2):
            # Here terms is text: f-strings form each product expression and join places "
            # + " between them.
            # The displayed answer comes from C, which was calculated before these display
            # loops.
            terms = " + ".join(f"({DEMO_A[i][k]})*({DEMO_B[k][j]})" for k in range(2))
            print(f"C[{i}][{j}] = {terms} = {C[i][j]}")
    print("Modes: 0=INT4, 1=INT8, 2=INT16; mode 3 is reserved.")
    print("This computes expected values. RTL array timing is checked separately.")


# Display a full-size example with sixteen contributions per output and an easy closed-form
# answer.
def show_array_demo(precision=4):
    """Use the exact A/B data from tensor_array_16x16_demo_tb.sv."""
    # A has sixteen independent all-ones rows; B repeats the row -8, -7, ..., 7 sixteen
    # times.
    A = [[1 for j in range(16)] for i in range(16)]
    B = [[j - 8 for j in range(16)] for k in range(16)]
    # Every C[i][j] equals 16*(j-8). These inputs fit all modes, so their numeric answers
    # match.
    C = reference_model(A, B, precision)
    print(f"FULL ARRAY REFERENCE DEMO: INT{precision}, 16x16")
    print("Every A entry is 1; every B row is [-8, -7, ..., 7].")
    print("Every C row must be 16 times the corresponding B row.")
    # The entire C matrix has been computed; show its first and last rows to keep the
    # display short.
    print("C row 0 =", C[0])
    print("C row 15 =", C[15])
    print("256 outputs; 16 products per output; 4096 mathematical MACs.")
    print("This computes expected values. RTL array timing is checked separately.")


# Command-line entry point: select a display and optionally generate the saved vector
# suite.
# Example: py tensor_matrix_reference.py --array-demo --precision 8 --generate.
def main():
    # Define option rules first. The module docstring supplies the description shown by
    # --help.
    parser = argparse.ArgumentParser(description=__doc__)
    # Precision controls the displayed demo; type=int converts text and choices rejects
    # unsupported widths.
    parser.add_argument("--precision", type=int, choices=(4, 8, 16), default=4,
                        help="signed precision for the demo (default: 4)")
    # store_true flags default to False and become True when present; they need no
    # following value.
    parser.add_argument("--array-demo", action="store_true",
                        help="show the 16x16 example used by the RTL demo")
    parser.add_argument("--generate", action="store_true", help="write the matrix vector suite")
    # By default, place generated vectors beside this script; a supplied path can select
    # another folder.
    parser.add_argument("--output-dir", type=Path,
                        default=Path(__file__).resolve().parent / "vectors")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    # Read the actual command. Hyphenated options become attributes such as
    # args.array_demo.
    args = parser.parse_args()
    # Display either the full-array example or the small hand-calculated example.
    if args.array_demo:
        show_array_demo(args.precision)
    else:
        show_demo(args.precision)
    # This is an independent choice after either display. Generation always includes all
    # three modes.
    if args.generate:
        payload = export_cases(args.output_dir, args.seed)
        # Read counts from the returned payload and print where the generated files were
        # saved.
        print(f"GENERATED {payload['case_count']} matrix cases, "
              f"{payload['word_count_per_memory']} expected entries, "
              f"{payload['mac_operations']} mathematical MAC operations.")
        print(f"PACKED {payload['full_array_case_count']} full-array cases: "
              f"{payload['packed_frame_count']} input frames per A/B file.")
        print("Vectors written to:", args.output_dir.resolve())


# Run main only when this file is executed directly. Imports make the functions available
# without automatically displaying a demo or exporting cases.
if __name__ == "__main__":
    main()
