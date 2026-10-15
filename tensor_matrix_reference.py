"""Independent matrix answers and input vectors for our tensor-unit project.

Run this file for a small example. Add --array-demo for the current 16x16 demo.
Add --generate to create the vector suite and packed RTL input/output files.
"""

import argparse
import json                 # saves matrices and test info in a readable data file
import random               #generates repeatable random test inputs                  
from pathlib import Path    


WIDTHS = {0: 4, 1: 8, 2: 16}
DEFAULT_SEED = 20261008 #starting setting for random generator,using same seed produces same test data 
DEMO_A = [[-3, 4], [2, -1]]
DEMO_B = [[2, -2], [3, 1]]


def precision_width(mode):
    if type(mode) is not int or mode not in WIDTHS:
        raise ValueError("Use mode 0 (INT4), 1 (INT8), or 2 (INT16).")
    return WIDTHS[mode]


def decode_input(raw_value, mode):
    """Interpret the selected signed field of a raw 16-bit input bus."""
    width = precision_width(mode)
    if type(raw_value) is not int or not 0 <= raw_value <= 0xFFFF:
        raise ValueError("A raw input bus value must be an integer from 0 to 65535.")
    value = raw_value & ((1 << width) - 1)
    if value >= (1 << (width - 1)):
        value = value - (1 << width)
    return value


def encode_input(value, mode, upper_bits=0):
    """Put a signed value in its lower field; allow noise in unused bus bits."""
    width = precision_width(mode)
    if type(value) is not int or not -(1 << (width - 1)) <= value < (1 << (width - 1)):
        raise ValueError("The signed input is outside the selected precision's range.")
    if type(upper_bits) is not int or not 0 <= upper_bits <= 0xFFFF:
        raise ValueError("upper_bits must be a raw 16-bit value.")
    field_mask = (1 << width) - 1
    return (upper_bits & (0xFFFF ^ field_mask)) | (value & field_mask)
#This helps test whether the RTL correctly ignore unused upper bits

def matrix_shape(matrix):
    """Check a nonempty integer matrix with dimensions at most 16."""
    if not isinstance(matrix, (list, tuple)) or not 1 <= len(matrix) <= 16:
        raise ValueError("A matrix must have between 1 and 16 rows.")
    if not isinstance(matrix[0], (list, tuple)) or not 1 <= len(matrix[0]) <= 16:
        raise ValueError("A matrix must have between 1 and 16 columns.")
    columns = len(matrix[0])
    for row in matrix:
        if not isinstance(row, (list, tuple)) or len(row) != columns:
            raise ValueError("All rows must have the same length.")
        if any(type(value) is not int for value in row):
            raise ValueError("Matrix entries must be integers.")
    return len(matrix), columns


def matrix_multiply(A, B):
    """Multiply signed integer matrices using the mathematical definition."""
    rows, terms = matrix_shape(A)
    b_rows, columns = matrix_shape(B)
    if terms != b_rows:
        raise ValueError("The number of A columns must equal the number of B rows.")

    C = [[0 for j in range(columns)] for i in range(rows)]
    for i in range(rows):
        for j in range(columns):
            for k in range(terms):
                C[i][j] = C[i][j] + A[i][k] * B[k][j]
    return C


def reference_model(A, B, precision=16):
    # Calculate C = A x B from signed inputs valid for INT4, INT8 or INT16.

    if type(precision) is not int or precision not in (4, 8, 16):
        raise ValueError("precision must be 4, 8 or 16.")
    mode = {4: 0, 8: 1, 16: 2}[precision]
    return reference_from_raw(encode_matrix(A, mode), encode_matrix(B, mode), mode)


def reference_from_raw(A_raw, B_raw, mode):
    """Apply the RTL bus interpretation, then calculate exact matrix answers."""
    precision_width(mode)
    matrix_shape(A_raw)
    matrix_shape(B_raw)
    A = [[decode_input(value, mode) for value in row] for row in A_raw]
    B = [[decode_input(value, mode) for value in row] for row in B_raw]
    return matrix_multiply(A, B)


def encode_matrix(matrix, mode, rng=None):
    """Convert signed test data to raw buses, optionally varying unused bits."""
    precision_width(mode)
    matrix_shape(matrix)
    return [[encode_input(value, mode, rng.getrandbits(16) if rng else 0)
             for value in row] for row in matrix]


def pack_input_frames(A_raw, B_raw):
    """Pack square-matrix raw words into the tensor_array input-frame format.

    In frame k, lane i carries A[i][k] and lane j carries B[k][j].
    Lane zero occupies bits [15:0]. The RTL supplies the boundary skew.
    """
    n, columns = matrix_shape(A_raw)
    if columns != n or matrix_shape(B_raw) != (n, n):
        raise ValueError("Frame packing requires two equal square matrices.")
    for matrix in (A_raw, B_raw):
        if any(not 0 <= value <= 0xFFFF for row in matrix for value in row):
            raise ValueError("Each raw input word must be from 0 to 65535.")
    a_frames, b_frames = [], []
    for k in range(n):
        a_frame, b_frame = 0, 0
        for lane in range(n):
            a_frame |= A_raw[lane][k] << (16 * lane)
            b_frame |= B_raw[k][lane] << (16 * lane)
        a_frames.append(a_frame)
        b_frames.append(b_frame)
    return a_frames, b_frames


def pack_result_matrix(C):
    """Encode C as row-major signed 36-bit fields for the c_matrix bus."""
    n, columns = matrix_shape(C)
    if columns != n:
        raise ValueError("Result-bus packing requires a square matrix.")
    packed = 0
    mask = (1 << 36) - 1
    for i in range(n):
        for j in range(n):
            value = C[i][j]
            if not -(1 << 35) <= value < (1 << 35):
                raise OverflowError("An expected result does not fit signed 36 bits.")
            packed |= (value & mask) << (36 * (i * n + j))
    return packed


def make_cases(seed=DEFAULT_SEED):
    """Deterministic data for 2x2, 4x4 and 16x16 checks in every precision."""
    rng = random.Random(seed)
    cases = []

    def add_case(name, mode, A, B, use_upper_noise=True):
        A_raw = encode_matrix(A, mode, rng if use_upper_noise else None)
        B_raw = encode_matrix(B, mode, rng if use_upper_noise else None)
        cases.append({
            "name": name,
            "mode": mode,
            "precision_bits": precision_width(mode),
            "n": len(A),
            "A_raw": A_raw,
            "B_raw": B_raw,
            "C_expected": reference_from_raw(A_raw, B_raw, mode),
        })

    add_case("demo_int4_2x2", 0, DEMO_A, DEMO_B, use_upper_noise=False)

    for n in (2, 4, 16):
        identity = [[int(i == j) for j in range(n)] for i in range(n)]
        zeros = [[0 for j in range(n)] for i in range(n)]
        for mode in (0, 1, 2):
            width = precision_width(mode)
            lo = -(1 << (width - 1))
            hi = (1 << (width - 1)) - 1
            boundaries = [lo, lo + 1, -1, 0, 1, hi - 1, hi]
            A = [[boundaries[(i * n + j) % len(boundaries)]
                  for j in range(n)] for i in range(n)]
            B = [[boundaries[(3 * i + j + 2) % len(boundaries)]
                  for j in range(n)] for i in range(n)]
            minimum = [[lo for j in range(n)] for i in range(n)]
            maximum = [[hi for j in range(n)] for i in range(n)]
            alternating = [[1 if (i + j) % 2 == 0 else -1
                            for j in range(n)] for i in range(n)]
            sparse_A = [[0 for j in range(n)] for i in range(n)]
            sparse_B = [[0 for j in range(n)] for i in range(n)]
            sparse_A[n - 1][0] = -1
            sparse_B[0][n - 1] = hi
            prefix = f"int{width}_{n}x{n}"
            add_case(prefix + "_zeros", mode, zeros, B)
            add_case(prefix + "_identity_right", mode, A, identity)
            add_case(prefix + "_identity_left", mode, identity, B)
            add_case(prefix + "_all_min_min", mode, minimum, minimum)
            add_case(prefix + "_all_max_max", mode, maximum, maximum)
            add_case(prefix + "_all_min_max", mode, minimum, maximum)
            add_case(prefix + "_mixed_signs", mode, A, B)
            add_case(prefix + "_sparse", mode, sparse_A, sparse_B)
            add_case(prefix + "_alternating_signs", mode, alternating, alternating)
            for sample in range(5):
                A = [[rng.randint(lo, hi) for j in range(n)] for i in range(n)]
                B = [[rng.randint(lo, hi) for j in range(n)] for i in range(n)]
                add_case(prefix + f"_random_{sample:02d}", mode, A, B)
    return cases


def export_cases(destination, seed=DEFAULT_SEED):
    """Write row-major vectors and packed frames for the fixed 16x16 top."""
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    cases = make_cases(seed)
    A_words, B_words, C_words = [], [], []
    A_frames, B_frames, C_matrices, modes = [], [], [], []
    mac_operations = 0

    for case in cases:
        n = case["n"]
        case["word_offset"] = len(A_words)
        case["word_count"] = n * n
        A_words.extend(value for row in case["A_raw"] for value in row)
        B_words.extend(value for row in case["B_raw"] for value in row)
        C_words.extend(value for row in case["C_expected"] for value in row)
        mac_operations = mac_operations + n * n * n
        if n == 16:
            packed_a, packed_b = pack_input_frames(case["A_raw"], case["B_raw"])
            case["frame_offset"] = len(A_frames)
            case["frame_count"] = 16
            case["matrix_offset"] = len(C_matrices)
            A_frames.extend(packed_a)
            B_frames.extend(packed_b)
            C_matrices.append(pack_result_matrix(case["C_expected"]))
            modes.append(case["mode"])

    # Keep expected arithmetic exact; only the exported bit representation is encoded.
    if any(not -(1 << 35) <= value < (1 << 35) for value in C_words):
        raise OverflowError("An expected result does not fit the 36-bit result bus.")
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
        "packed_layout": {
            "a_frame": "frame k: A[i][k] at bits 16*i +: 16",
            "b_frame": "frame k: B[k][j] at bits 16*j +: 16",
            "c_matrix": "C[i][j] at bits 36*(16*i+j) +: 36",
            "order": "16x16 cases only, in the same order as the cases array",
        },
        "cases": cases,
    }
    (destination / "tensor_matrix_cases.json").write_text(
        json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    (destination / "tensor_A16.mem").write_text(
        "".join(f"{value:04x}\n" for value in A_words), encoding="ascii")
    (destination / "tensor_B16.mem").write_text(
        "".join(f"{value:04x}\n" for value in B_words), encoding="ascii")
    (destination / "tensor_C36.mem").write_text(
        "".join(f"{value & ((1 << 36) - 1):09x}\n" for value in C_words),
        encoding="ascii")
    (destination / "tensor_A_frames256.mem").write_text(
        "".join(f"{value:064x}\n" for value in A_frames), encoding="ascii")
    (destination / "tensor_B_frames256.mem").write_text(
        "".join(f"{value:064x}\n" for value in B_frames), encoding="ascii")
    (destination / "tensor_C_matrices9216.mem").write_text(
        "".join(f"{value:02304x}\n" for value in C_matrices), encoding="ascii")
    (destination / "tensor_modes.mem").write_text(
        "".join(f"{value:x}\n" for value in modes), encoding="ascii")
    return payload


def show_demo(precision=4):
    print(f"MATRIX REFERENCE DEMO: INT{precision}, 2x2")
    print("A =", DEMO_A)
    print("B =", DEMO_B)
    C = reference_model(DEMO_A, DEMO_B, precision)
    print("C =", C)
    for i in range(2):
        for j in range(2):
            terms = " + ".join(f"({DEMO_A[i][k]})*({DEMO_B[k][j]})" for k in range(2))
            print(f"C[{i}][{j}] = {terms} = {C[i][j]}")
    print("Modes: 0=INT4, 1=INT8, 2=INT16; mode 3 is reserved.")
    print("This computes expected values. RTL array timing is checked separately.")


def show_array_demo(precision=4):
    """Use the exact A/B data from tensor_array_16x16_demo_tb.sv."""
    A = [[1 for j in range(16)] for i in range(16)]
    B = [[j - 8 for j in range(16)] for k in range(16)]
    C = reference_model(A, B, precision)
    print(f"FULL ARRAY REFERENCE DEMO: INT{precision}, 16x16")
    print("Every A entry is 1; every B row is [-8, -7, ..., 7].")
    print("Every C row must be 16 times the corresponding B row.")
    print("C row 0 =", C[0])
    print("C row 15 =", C[15])
    print("256 outputs; 16 products per output; 4096 mathematical MACs.")
    print("This computes expected values. RTL array timing is checked separately.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--precision", type=int, choices=(4, 8, 16), default=4,
                        help="signed precision for the demo (default: 4)")
    parser.add_argument("--array-demo", action="store_true",
                        help="show the 16x16 example used by the RTL demo")
    parser.add_argument("--generate", action="store_true", help="write the matrix vector suite")
    parser.add_argument("--output-dir", type=Path,
                        default=Path(__file__).resolve().parent / "vectors")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    args = parser.parse_args()
    if args.array_demo:
        show_array_demo(args.precision)
    else:
        show_demo(args.precision)
    if args.generate:
        payload = export_cases(args.output_dir, args.seed)
        print(f"GENERATED {payload['case_count']} matrix cases, "
              f"{payload['word_count_per_memory']} expected entries, "
              f"{payload['mac_operations']} mathematical MAC operations.")
        print(f"PACKED {payload['full_array_case_count']} full-array cases: "
              f"{payload['packed_frame_count']} input frames per A/B file.")
        print("Vectors written to:", args.output_dir.resolve())


if __name__ == "__main__":
    main()
