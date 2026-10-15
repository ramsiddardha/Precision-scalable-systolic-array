"""Checks for the mathematical oracle, signed bus decoding and exported files."""

import json
import tempfile
import unittest
from pathlib import Path

from tensor_matrix_reference import (
    DEMO_A, DEMO_B, decode_input, encode_input, encode_matrix,
    export_cases, make_cases, matrix_multiply, reference_from_raw,
    reference_model, pack_input_frames, pack_result_matrix,
)


class MatrixReferenceTests(unittest.TestCase):
    def test_hand_calculated_demo(self):
        expected = [[6, 10], [1, -5]]
        self.assertEqual(matrix_multiply(DEMO_A, DEMO_B), expected)
        for mode in (0, 1, 2):
            self.assertEqual(reference_from_raw(encode_matrix(DEMO_A, mode),
                             encode_matrix(DEMO_B, mode), mode), expected)

    def test_hand_calculated_rectangular_product(self):
        A = [[1, -2, 3], [-4, 5, -6]]
        B = [[7, -1], [-2, 3], [1, -4]]
        self.assertEqual(matrix_multiply(A, B), [[14, -19], [-44, 43]])

    def test_signed_reference_api_and_precision_limits(self):
        for precision, lo, hi in ((4, -8, 7), (8, -128, 127),
                                  (16, -32768, 32767)):
            self.assertEqual(reference_model(DEMO_A, DEMO_B, precision),
                             [[6, 10], [1, -5]])
            self.assertEqual(reference_model([[lo]], [[lo]], precision), [[lo * lo]])
            self.assertEqual(reference_model([[lo]], [[hi]], precision), [[lo * hi]])
            for invalid in (lo - 1, hi + 1):
                with self.assertRaises(ValueError):
                    reference_model([[invalid]], [[1]], precision)
        for precision in (0, 1, 2, 3, 32, True):
            with self.assertRaises(ValueError):
                reference_model([[1]], [[1]], precision)

    def test_hand_calculated_packed_demo(self):
        a_frames, b_frames = pack_input_frames(encode_matrix(DEMO_A, 0),
                                               encode_matrix(DEMO_B, 0))
        self.assertEqual(a_frames, [0x0002000D, 0x000F0004])
        self.assertEqual(b_frames, [0x000E0002, 0x00010003])
        self.assertEqual(f"{pack_result_matrix([[6, 10], [1, -5]]):036x}",
                         "ffffffffb00000000100000000a000000006")

    def test_full_array_packing_against_byte_layout(self):
        A = [[1000 * i + k for k in range(16)] for i in range(16)]
        B = [[2000 * k + j for j in range(16)] for k in range(16)]
        a_frames, b_frames = pack_input_frames(A, B)
        for k in range(16):
            # Independent byte concatenation checks lane zero, lane order,
            # A column order and B row order on the actual 256-bit buses.
            self.assertEqual(a_frames[k].to_bytes(32, "little"),
                             b"".join(A[i][k].to_bytes(2, "little") for i in range(16)))
            self.assertEqual(b_frames[k].to_bytes(32, "little"),
                             b"".join(B[k][j].to_bytes(2, "little") for j in range(16)))
        C = [[16 * i + j - 128 for j in range(16)] for i in range(16)]
        packed_c = pack_result_matrix(C)
        for i in range(16):
            for j in range(16):
                raw = (packed_c >> (36 * (16 * i + j))) & ((1 << 36) - 1)
                decoded = int.from_bytes((raw << 4).to_bytes(5, "big"),
                                         "big", signed=True) >> 4
                self.assertEqual(decoded, C[i][j])

    def test_current_rtl_demo_against_closed_form(self):
        A = [[1] * 16 for i in range(16)]
        B = [list(range(-8, 8)) for k in range(16)]
        expected = [list(range(-128, 128, 16)) for i in range(16)]
        for precision in (4, 8, 16):
            self.assertEqual(reference_model(A, B, precision), expected)

    def test_invalid_frame_and_result_inputs(self):
        for A, B in (([[1, 2]], [[1], [2]]), ([[1]], [[1, 2], [3, 4]]),
                     ([[-1]], [[1]]), ([[65536]], [[1]])):
            with self.assertRaises(ValueError):
                pack_input_frames(A, B)
        with self.assertRaises(ValueError):
            pack_result_matrix([[1, 2]])
        for value in (-(1 << 35) - 1, 1 << 35):
            with self.assertRaises(OverflowError):
                pack_result_matrix([[value]])

    def test_decode_against_signed_byte_interpretation(self):
        # Independent oracle: shift the selected field to a byte/word sign bit,
        # interpret signed bytes, then shift back. Includes every 16-bit pattern.
        for raw in range(65536):
            expected4 = int.from_bytes(bytes([(raw & 15) << 4]), "big", signed=True) >> 4
            expected8 = int.from_bytes(bytes([raw & 255]), "big", signed=True)
            expected16 = int.from_bytes(raw.to_bytes(2, "big"), "big", signed=True)
            self.assertEqual(decode_input(raw, 0), expected4)
            self.assertEqual(decode_input(raw, 1), expected8)
            self.assertEqual(decode_input(raw, 2), expected16)

    def test_known_encodings_and_ignored_upper_bits(self):
        self.assertEqual(encode_input(-3, 0), 0x000D)
        self.assertEqual(encode_input(-3, 1), 0x00FD)
        self.assertEqual(encode_input(-3, 2), 0xFFFD)
        self.assertEqual(encode_input(-3, 0, 0xABC0), 0xABCD)
        self.assertEqual(decode_input(0xABCD, 0), -3)
        A0 = [[0x000D, 0x0004], [0x0002, 0x000F]]
        A1 = [[0xABCD, 0x1234], [0xFFF2, 0x987F]]
        B0 = [[0x0002, 0x000E], [0x0003, 0x0001]]
        B1 = [[0x3212, 0xABCE], [0x5553, 0x8881]]
        self.assertEqual(reference_from_raw(A0, B0, 0), [[6, 10], [1, -5]])
        self.assertEqual(reference_from_raw(A1, B1, 0), [[6, 10], [1, -5]])

    def test_identity_zero_and_sixteen_term_extrema(self):
        for mode, lo, hi, expected_max in (
            (0, -8, 7, 1024),
            (1, -128, 127, 262144),
            (2, -32768, 32767, 17179869184),
        ):
            identity = [[int(i == j) for j in range(16)] for i in range(16)]
            A = [[lo if (i + j) % 2 else hi for j in range(16)] for i in range(16)]
            zero = [[0] * 16 for i in range(16)]
            self.assertEqual(matrix_multiply(A, identity), A)
            self.assertEqual(matrix_multiply(identity, A), A)
            self.assertEqual(matrix_multiply(A, zero), zero)
            minimum_raw = [[lo & 0xFFFF] * 16 for i in range(16)]
            maximum_raw = [[hi] * 16 for i in range(16)]
            self.assertEqual(reference_from_raw(minimum_raw, minimum_raw, mode),
                             [[expected_max] * 16 for i in range(16)])
            self.assertEqual(reference_from_raw(minimum_raw, maximum_raw, mode),
                             [[16 * lo * hi] * 16 for i in range(16)])

    def test_generated_case_properties(self):
        for case in make_cases():
            n = case["n"]
            C = case["C_expected"]
            if case["name"].endswith("_zeros"):
                self.assertEqual(C, [[0] * n for i in range(n)])
            elif case["name"].endswith("_alternating_signs"):
                expected = [[n if (i + j) % 2 == 0 else -n
                             for j in range(n)] for i in range(n)]
                self.assertEqual(C, expected)
            elif case["name"].endswith("_sparse"):
                hi = (1 << (case["precision_bits"] - 1)) - 1
                expected = [[0] * n for i in range(n)]
                expected[n - 1][n - 1] = -hi
                self.assertEqual(C, expected)

    def test_exported_memory_layout_and_signed_results(self):
        with tempfile.TemporaryDirectory() as directory:
            payload = export_cases(directory)
            root = Path(directory)
            stored = json.loads((root / "tensor_matrix_cases.json").read_text())
            self.assertEqual(stored, payload)
            a_lines = (root / "tensor_A16.mem").read_text().splitlines()
            b_lines = (root / "tensor_B16.mem").read_text().splitlines()
            c_lines = (root / "tensor_C36.mem").read_text().splitlines()
            self.assertEqual(a_lines[:4], ["000d", "0004", "0002", "000f"])
            self.assertEqual(b_lines[:4], ["0002", "000e", "0003", "0001"])
            self.assertEqual(c_lines[:4],
                             ["000000006", "00000000a", "000000001", "ffffffffb"])
            offset = 0
            for case in payload["cases"]:
                count = case["n"] ** 2
                self.assertEqual(case["word_offset"], offset)
                self.assertEqual(case["word_count"], count)
                self.assertEqual([int(word, 16) for word in a_lines[offset:offset + count]],
                                 [value for row in case["A_raw"] for value in row])
                self.assertEqual([int(word, 16) for word in b_lines[offset:offset + count]],
                                 [value for row in case["B_raw"] for value in row])
                decoded_c = []
                for word in c_lines[offset:offset + count]:
                    self.assertEqual(len(word), 9)
                    # Shift a 36-bit word to the sign bit of a signed 40-bit value.
                    value = int.from_bytes((int(word, 16) << 4).to_bytes(5, "big"),
                                           "big", signed=True) >> 4
                    decoded_c.append(value)
                self.assertEqual(decoded_c,
                                 [value for row in case["C_expected"] for value in row])
                offset = offset + count
            self.assertEqual(len(a_lines), offset)
            self.assertEqual(len(b_lines), offset)
            self.assertEqual(len(c_lines), offset)
            a_frames = (root / "tensor_A_frames256.mem").read_text().splitlines()
            b_frames = (root / "tensor_B_frames256.mem").read_text().splitlines()
            matrices = (root / "tensor_C_matrices9216.mem").read_text().splitlines()
            modes = (root / "tensor_modes.mem").read_text().splitlines()
            full_cases = [case for case in payload["cases"] if case["n"] == 16]
            self.assertEqual(len(full_cases), 42)
            self.assertEqual(payload["packed_frame_count"], 672)
            self.assertEqual(payload["full_array_case_count"], 42)
            self.assertEqual(len(a_frames), 672)
            self.assertEqual(len(b_frames), 672)
            self.assertEqual(len(matrices), 42)
            self.assertEqual(len(modes), 42)
            for index, case in enumerate(full_cases):
                self.assertEqual(case["frame_offset"], 16 * index)
                self.assertEqual(case["frame_count"], 16)
                self.assertEqual(case["matrix_offset"], index)
                self.assertEqual(int(modes[index], 16), case["mode"])
                for k in range(16):
                    a_word = a_frames[16 * index + k]
                    b_word = b_frames[16 * index + k]
                    self.assertEqual(len(a_word), 64)
                    self.assertEqual(len(b_word), 64)
                    self.assertEqual(int(a_word, 16).to_bytes(32, "little"),
                        b"".join(case["A_raw"][i][k].to_bytes(2, "little")
                                 for i in range(16)))
                    self.assertEqual(int(b_word, 16).to_bytes(32, "little"),
                        b"".join(case["B_raw"][k][j].to_bytes(2, "little")
                                 for j in range(16)))
                self.assertEqual(len(matrices[index]), 2304)
                # Read the printed result fields from right to left;
                # each nine-digit field is a signed 36-bit C element.
                for position in range(256):
                    end = len(matrices[index]) - 9 * position
                    raw = int(matrices[index][end - 9:end], 16)
                    decoded = int.from_bytes((raw << 4).to_bytes(5, "big"),
                                             "big", signed=True) >> 4
                    i, j = divmod(position, 16)
                    self.assertEqual(decoded, case["C_expected"][i][j])

    def test_invalid_modes_shapes_and_bus_values(self):
        for mode in (-1, 3, 4, True):
            with self.assertRaises(ValueError):
                reference_from_raw([[1]], [[1]], mode)
        for bad_matrix in ([], [[]], [[1], [1, 2]], [[1.5]], [[1]] * 17):
            with self.assertRaises(ValueError):
                matrix_multiply(bad_matrix, [[1]])
        with self.assertRaises(ValueError):
            matrix_multiply([[1, 2]], [[1]])
        for raw in (-1, 65536):
            with self.assertRaises(ValueError):
                reference_from_raw([[raw]], [[1]], 0)
        for value in (-9, 8):
            with self.assertRaises(ValueError):
                encode_input(value, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
