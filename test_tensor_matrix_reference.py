"""Checks for the mathematical oracle, signed bus decoding and exported files."""

# This suite runs Python functions; the Vivado testbench separately verifies hardware.
# Thirteen test methods contain many assertions and input cases, rather than thirteen input pairs.
# Expected values come from hand calculations, mathematical properties, or independent byte layouts.
import json
# Temporary folders let export tests write files without relying on the project's existing vectors.
import tempfile
# unittest discovers test_ methods, runs checks, and reports failures and errors.
import unittest
from pathlib import Path

# Import the functions under test. The reference file's main guard prevents automatic CLI
# execution.
from tensor_matrix_reference import (
    DEMO_A, DEMO_B, decode_input, encode_input, encode_matrix,
    export_cases, make_cases, matrix_multiply, reference_from_raw,
    reference_model, pack_input_frames, pack_result_matrix,
)


# Inheriting TestCase supplies assertion methods accessed through self in each test method.
# assertEqual compares an actual result with its expected value.
# assertRaises checks that invalid input raises the specified exception; acceptance would
# fail the test.
class MatrixReferenceTests(unittest.TestCase):
    # Check the small demonstration against a literal answer calculated by hand.
    # Reuse the same signed operands in all modes to check raw encoding/decoding around the
    # arithmetic.
    def test_hand_calculated_demo(self):
        # For example C[0][0] = (-3)*2 + 4*3 = 6; C[0][1] = (-3)*(-2) + 4*1 = 10.
        expected = [[6, 10], [1, -5]]
        self.assertEqual(matrix_multiply(DEMO_A, DEMO_B), expected)
        for mode in (0, 1, 2):
            self.assertEqual(reference_from_raw(encode_matrix(DEMO_A, mode),
                             encode_matrix(DEMO_B, mode), mode), expected)

    # The arithmetic helper supports compatible rectangular matrices: 2x3 times 3x2 gives
    # 2x2.
    # The literal result is independent of the matrix_multiply implementation being
    # checked.
    def test_hand_calculated_rectangular_product(self):
        A = [[1, -2, 3], [-4, 5, -6]]
        B = [[7, -1], [-2, 3], [1, -4]]
        self.assertEqual(matrix_multiply(A, B), [[14, -19], [-44, 43]])

    # Check the public signed-input API, legal endpoints, and values just beyond each
    # precision range.
    # 1x1 matrices isolate one multiplication while exercising the same reference entry
    # point.
    def test_signed_reference_api_and_precision_limits(self):
        for precision, lo, hi in ((4, -8, 7), (8, -128, 127),
                                  (16, -32768, 32767)):
            self.assertEqual(reference_model(DEMO_A, DEMO_B, precision),
                             [[6, 10], [1, -5]])
            # Minimum times minimum stresses the signed minimum's positive product
            # magnitude.
            self.assertEqual(reference_model([[lo]], [[lo]], precision), [[lo * lo]])
            self.assertEqual(reference_model([[lo]], [[hi]], precision), [[lo * hi]])
            # Values one below lo or one above hi must raise ValueError rather than being
            # silently wrapped.
            for invalid in (lo - 1, hi + 1):
                with self.assertRaises(ValueError):
                    reference_model([[invalid]], [[1]], precision)
        # Precision arguments are widths 4/8/16, not mode numbers 0/1/2; booleans are
        # rejected too.
        for precision in (0, 1, 2, 3, 32, True):
            with self.assertRaises(ValueError):
                reference_model([[1]], [[1]], precision)

    # Hard-coded hexadecimal words verify lane placement and negative result
    # representation.
    # For a two-lane frame, the first operand occupies the low 16 bits and the second the
    # next 16.
    def test_hand_calculated_packed_demo(self):
        a_frames, b_frames = pack_input_frames(encode_matrix(DEMO_A, 0),
                                               encode_matrix(DEMO_B, 0))
        # A frame 0 combines raw 0x000D in lane 0 and 0x0002 in lane 1, giving 0x0002000D.
        self.assertEqual(a_frames, [0x0002000D, 0x000F0004])
        self.assertEqual(b_frames, [0x000E0002, 0x00010003])
        # Four 36-bit output fields need 144 bits, or 36 hexadecimal characters in total.
        # The rightmost nine hex characters hold C[0][0]; the leftmost field encodes -5.
        self.assertEqual(f"{pack_result_matrix([[6, 10], [1, -5]]):036x}",
                         "ffffffffb00000000100000000a000000006")

    # Check full 256-bit frames against a separate byte-concatenation construction.
    # Position-dependent operand values make row, column, and lane swaps visible.
    def test_full_array_packing_against_byte_layout(self):
        A = [[1000 * i + k for k in range(16)] for i in range(16)]
        B = [[2000 * k + j for j in range(16)] for k in range(16)]
        a_frames, b_frames = pack_input_frames(A, B)
        # A 256-bit frame occupies 32 bytes, while each 16-bit operand occupies two bytes.
        # Little-endian byte order places the lowest lane first in the byte sequence being
        # compared.
        for k in range(16):
            # Independent byte concatenation checks lane zero, lane order,
            # A column order and B row order on the actual 256-bit buses.
            self.assertEqual(a_frames[k].to_bytes(32, "little"),
                             b"".join(A[i][k].to_bytes(2, "little") for i in range(16)))
            self.assertEqual(b_frames[k].to_bytes(32, "little"),
                             b"".join(B[k][j].to_bytes(2, "little") for j in range(16)))
        # Distinct outputs from -128 through 127 exercise field order and both signs.
        C = [[16 * i + j - 128 for j in range(16)] for i in range(16)]
        packed_c = pack_result_matrix(C)
        for i in range(16):
            for j in range(16):
                # Extract one 36-bit field using its row-major position and a 36-bit mask.
                raw = (packed_c >> (36 * (16 * i + j))) & ((1 << 36) - 1)
                # Five bytes hold 40 bits: shift left four so the 36-bit sign reaches bit
                # 39.
                # Signed byte interpretation followed by an arithmetic right shift recovers
                # the original value.
                decoded = int.from_bytes((raw << 4).to_bytes(5, "big"),
                                         "big", signed=True) >> 4
                self.assertEqual(decoded, C[i][j])

    # With A all ones and every B row equal, each output column is sixteen times its B
    # value.
    # Construct that expected answer directly, independently of the reference
    # multiplication loops.
    def test_current_rtl_demo_against_closed_form(self):
        A = [[1] * 16 for i in range(16)]
        B = [list(range(-8, 8)) for k in range(16)]
        expected = [list(range(-128, 128, 16)) for i in range(16)]
        # The common input range -8..7 is legal in every precision, so all three modes must
        # agree here.
        for precision in (4, 8, 16):
            self.assertEqual(reference_model(A, B, precision), expected)

    # Packing requires equal square matrices and unsigned 16-bit input words.
    # Result packing also rejects non-square matrices and outputs outside signed 36 bits.
    def test_invalid_frame_and_result_inputs(self):
        # Include rectangular/mismatched shapes plus raw values -1 and 65536, which exceed
        # bus bounds.
        for A, B in (([[1, 2]], [[1], [2]]), ([[1]], [[1, 2], [3, 4]]),
                     ([[-1]], [[1]]), ([[65536]], [[1]])):
            with self.assertRaises(ValueError):
                pack_input_frames(A, B)
        with self.assertRaises(ValueError):
            pack_result_matrix([[1, 2]])
        # Check just outside both signed 36-bit endpoints to catch an off-by-one range
        # error.
        for value in (-(1 << 35) - 1, 1 << 35):
            with self.assertRaises(OverflowError):
                pack_result_matrix([[value]])

    # Cover all 65,536 raw input words in each of the three modes.
    # Derive expected values with signed bytes rather than calling encode_input or
    # decode_input.
    def test_decode_against_signed_byte_interpretation(self):
        # Independent oracle: shift the selected field to a byte/word sign bit,
        # interpret signed bytes, then shift back. Includes every 16-bit pattern.
        for raw in range(65536):
            # Move the low nibble's sign bit to a byte's sign position, interpret signed,
            # then shift back.
            expected4 = int.from_bytes(bytes([(raw & 15) << 4]), "big", signed=True) >> 4
            # An INT8 operand is the selected low byte interpreted as signed.
            expected8 = int.from_bytes(bytes([raw & 255]), "big", signed=True)
            # INT16 uses both bytes, with the full word's top bit determining the sign.
            expected16 = int.from_bytes(raw.to_bytes(2, "big"), "big", signed=True)
            self.assertEqual(decode_input(raw, 0), expected4)
            self.assertEqual(decode_input(raw, 1), expected8)
            self.assertEqual(decode_input(raw, 2), expected16)

    # Check known two's-complement patterns so an encoder/decoder round trip cannot hide a
    # shared mistake.
    # The selected lower bits carry the operand; unrelated upper bits must not affect INT4
    # results.
    def test_known_encodings_and_ignored_upper_bits(self):
        self.assertEqual(encode_input(-3, 0), 0x000D)
        self.assertEqual(encode_input(-3, 1), 0x00FD)
        self.assertEqual(encode_input(-3, 2), 0xFFFD)
        # In INT4, combine lower field D with upper pattern ABC0; the resulting ABCD still
        # means -3.
        self.assertEqual(encode_input(-3, 0, 0xABC0), 0xABCD)
        self.assertEqual(decode_input(0xABCD, 0), -3)
        # A0/A1 share the same low nibbles, and B0/B1 do too; only unused upper bits
        # differ.
        A0 = [[0x000D, 0x0004], [0x0002, 0x000F]]
        A1 = [[0xABCD, 0x1234], [0xFFF2, 0x987F]]
        B0 = [[0x0002, 0x000E], [0x0003, 0x0001]]
        B1 = [[0x3212, 0xABCE], [0x5553, 0x8881]]
        self.assertEqual(reference_from_raw(A0, B0, 0), [[6, 10], [1, -5]])
        self.assertEqual(reference_from_raw(A1, B1, 0), [[6, 10], [1, -5]])

    # Check full-size identity/zero properties and the largest positive sixteen-term sum.
    # For width w, the minimum operand is -2**(w-1); sixteen minimum-squared products give
    # expected_max.
    def test_identity_zero_and_sixteen_term_extrema(self):
        for mode, lo, hi, expected_max in (
            (0, -8, 7, 1024),
            (1, -128, 127, 262144),
            (2, -32768, 32767, 17179869184),
        ):
            # These matrix identities supply expected results without another
            # multiplication implementation.
            identity = [[int(i == j) for j in range(16)] for i in range(16)]
            A = [[lo if (i + j) % 2 else hi for j in range(16)] for i in range(16)]
            zero = [[0] * 16 for i in range(16)]
            self.assertEqual(matrix_multiply(A, identity), A)
            self.assertEqual(matrix_multiply(identity, A), A)
            self.assertEqual(matrix_multiply(A, zero), zero)
            # Build 16-bit raw patterns with a mask, independently of the encoder being
            # tested elsewhere.
            # The decoder must select the correct signed subfield for each mode.
            minimum_raw = [[lo & 0xFFFF] * 16 for i in range(16)]
            maximum_raw = [[hi] * 16 for i in range(16)]
            # Expected maxima 1024, 262144, and 17179869184 fit signed 12-, 20-, and 36-bit
            # accumulators.
            self.assertEqual(reference_from_raw(minimum_raw, minimum_raw, mode),
                             [[expected_max] * 16 for i in range(16)])
            self.assertEqual(reference_from_raw(minimum_raw, maximum_raw, mode),
                             [[16 * lo * hi] * 16 for i in range(16)])

    # Check selected generated patterns against direct mathematical properties.
    # Case suffixes identify which independent expected-output rule applies.
    def test_generated_case_properties(self):
        for case in make_cases():
            n = case["n"]
            C = case["C_expected"]
            # Zero products must yield an all-zero output matrix.
            if case["name"].endswith("_zeros"):
                self.assertEqual(C, [[0] * n for i in range(n)])
            elif case["name"].endswith("_alternating_signs"):
                # Checkerboard signs multiply to a fixed sign per output; summing n terms
                # gives +n or -n.
                expected = [[n if (i + j) % 2 == 0 else -n
                             for j in range(n)] for i in range(n)]
                self.assertEqual(C, expected)
            elif case["name"].endswith("_sparse"):
                # The sparse construction contributes -1*hi only to the last output entry.
                hi = (1 << (case["precision_bits"] - 1)) - 1
                expected = [[0] * n for i in range(n)]
                expected[n - 1][n - 1] = -hi
                self.assertEqual(C, expected)

    # Exercise real export files as well as returned metadata, including every generated
    # case.
    # Check word offsets, hexadecimal widths, signed results, packed frames, and
    # full-matrix layout.
    def test_exported_memory_layout_and_signed_results(self):
        # The temporary directory is created for this test and removed automatically
        # afterwards.
        with tempfile.TemporaryDirectory() as directory:
            payload = export_cases(directory)
            root = Path(directory)
            # Read the saved JSON back and compare it with the dictionary returned by
            # export_cases.
            stored = json.loads((root / "tensor_matrix_cases.json").read_text())
            self.assertEqual(stored, payload)
            # splitlines converts each text file into a list containing one hex word per
            # item.
            a_lines = (root / "tensor_A16.mem").read_text().splitlines()
            b_lines = (root / "tensor_B16.mem").read_text().splitlines()
            c_lines = (root / "tensor_C36.mem").read_text().splitlines()
            # The first case is the fixed demo, so its first four input/output words are
            # known by hand.
            self.assertEqual(a_lines[:4], ["000d", "0004", "0002", "000f"])
            self.assertEqual(b_lines[:4], ["0002", "000e", "0003", "0001"])
            self.assertEqual(c_lines[:4],
                             ["000000006", "00000000a", "000000001", "ffffffffb"])
            # Track an independent running word index rather than trusting each case's
            # stored offset.
            offset = 0
            for case in payload["cases"]:
                # Each n x n case contributes n**2 words to each individual A/B/C memory
                # file.
                count = case["n"] ** 2
                self.assertEqual(case["word_offset"], offset)
                self.assertEqual(case["word_count"], count)
                # Convert saved hexadecimal words to integers and compare their order with
                # flattened source matrices.
                self.assertEqual([int(word, 16) for word in a_lines[offset:offset + count]],
                                 [value for row in case["A_raw"] for value in row])
                self.assertEqual([int(word, 16) for word in b_lines[offset:offset + count]],
                                 [value for row in case["B_raw"] for value in row])
                # Outputs are stored as unsigned 36-bit patterns; recover their signed
                # values before comparison.
                decoded_c = []
                for word in c_lines[offset:offset + count]:
                    self.assertEqual(len(word), 9)
                    # Shift a 36-bit word to the sign bit of a signed 40-bit value.
                    # Align bit 35 with bit 39 of a signed five-byte word, then shift back
                    # to recover negatives.
                    value = int.from_bytes((int(word, 16) << 4).to_bytes(5, "big"),
                                           "big", signed=True) >> 4
                    decoded_c.append(value)
                self.assertEqual(decoded_c,
                                 [value for row in case["C_expected"] for value in row])
                # Advance by words, not bits or bytes, to the next case's starting
                # position.
                offset = offset + count
            # Matching final lengths catches both missing words and unexpected extra words.
            self.assertEqual(len(a_lines), offset)
            self.assertEqual(len(b_lines), offset)
            self.assertEqual(len(c_lines), offset)
            # Read the separate packed files, which include only the full 16x16 matrix
            # cases.
            a_frames = (root / "tensor_A_frames256.mem").read_text().splitlines()
            b_frames = (root / "tensor_B_frames256.mem").read_text().splitlines()
            matrices = (root / "tensor_C_matrices9216.mem").read_text().splitlines()
            modes = (root / "tensor_modes.mem").read_text().splitlines()
            full_cases = [case for case in payload["cases"] if case["n"] == 16]
            # Fourteen cases per precision give 42 full-size cases, each with sixteen
            # frames: 672 frames.
            self.assertEqual(len(full_cases), 42)
            self.assertEqual(payload["packed_frame_count"], 672)
            self.assertEqual(payload["full_array_case_count"], 42)
            self.assertEqual(len(a_frames), 672)
            self.assertEqual(len(b_frames), 672)
            self.assertEqual(len(matrices), 42)
            self.assertEqual(len(modes), 42)
            # enumerate supplies the full-array case index alongside its metadata
            # dictionary.
            # One expected result word and mode correspond to sixteen consecutive A/B frame
            # words.
            for index, case in enumerate(full_cases):
                self.assertEqual(case["frame_offset"], 16 * index)
                self.assertEqual(case["frame_count"], 16)
                self.assertEqual(case["matrix_offset"], index)
                self.assertEqual(int(modes[index], 16), case["mode"])
                for k in range(16):
                    a_word = a_frames[16 * index + k]
                    b_word = b_frames[16 * index + k]
                    # A 256-bit frame needs exactly 64 hex digits and must match the
                    # independent operand-byte order.
                    self.assertEqual(len(a_word), 64)
                    self.assertEqual(len(b_word), 64)
                    self.assertEqual(int(a_word, 16).to_bytes(32, "little"),
                        b"".join(case["A_raw"][i][k].to_bytes(2, "little")
                                 for i in range(16)))
                    self.assertEqual(int(b_word, 16).to_bytes(32, "little"),
                        b"".join(case["B_raw"][k][j].to_bytes(2, "little")
                                 for j in range(16)))
                # A complete 9216-bit result needs 2304 hex digits: 256 separate nine-digit
                # fields.
                self.assertEqual(len(matrices[index]), 2304)
                # Read the printed result fields from right to left;
                # each nine-digit field is a signed 36-bit C element.
                for position in range(256):
                    # Output position zero is in the rightmost field of the printed hex
                    # word.
                    # Slice one field at a time to check the saved layout independently of
                    # pack_result_matrix.
                    end = len(matrices[index]) - 9 * position
                    raw = int(matrices[index][end - 9:end], 16)
                    decoded = int.from_bytes((raw << 4).to_bytes(5, "big"),
                                             "big", signed=True) >> 4
                    # divmod gives row = position//16 and column = position%16 for the
                    # original output matrix.
                    i, j = divmod(position, 16)
                    self.assertEqual(decoded, case["C_expected"][i][j])

    # Check error handling for reserved modes, bad matrix containers/shapes, and
    # out-of-range values.
    # A passing assertRaises means the invalid request was correctly rejected.
    def test_invalid_modes_shapes_and_bus_values(self):
        # Only integer modes 0, 1 and 2 are accepted by the raw-bus API; mode 3 is
        # reserved.
        for mode in (-1, 3, 4, True):
            with self.assertRaises(ValueError):
                reference_from_raw([[1]], [[1]], mode)
        # Include empty, empty-row, ragged, floating-point, and oversized matrix inputs.
        for bad_matrix in ([], [[]], [[1], [1, 2]], [[1.5]], [[1]] * 17):
            with self.assertRaises(ValueError):
                matrix_multiply(bad_matrix, [[1]])
        with self.assertRaises(ValueError):
            # A has two columns but B has one row, so these dimensions cannot be
            # multiplied.
            matrix_multiply([[1, 2]], [[1]])
        for raw in (-1, 65536):
            with self.assertRaises(ValueError):
                reference_from_raw([[raw]], [[1]], 0)
        # These signed numbers lie just outside INT4's legal -8..7 input range.
        for value in (-9, 8):
            with self.assertRaises(ValueError):
                encode_input(value, 0)


# Direct execution runs all discovered test methods. Importing this file only defines them.
# verbosity=2 prints each test's name and status, followed by the overall result.
if __name__ == "__main__":
    unittest.main(verbosity=2)
