"""Sanity checks for the independent oracle: arithmetic, latency and protocol."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))
from reference_model import Inputs, PEModel, WIDTHS, operand, signed, pack, unpack


class ReferenceTests(unittest.TestCase):
    def step(self, model, **kwargs):
        inputs = Inputs(**kwargs)
        model.apply_async_reset(inputs)
        model.edge(inputs)

    def test_two_complement_and_ignored_unknown_bits(self):
        self.assertEqual(operand("xxxf", 0), -1)
        self.assertEqual(operand("zz80", 1), -128)
        self.assertEqual(operand("8000", 2), -32768)
        self.assertEqual(operand("7fff", 2), 32767)
        self.assertEqual(signed(0xFFFFFFFFF, 36), -1)

    def test_active_unknown_bits_are_rejected(self):
        with self.assertRaises(ValueError):
            operand("000x", 0)

    def test_three_stage_latency_and_18th_edge_completion(self):
        model = PEModel()
        for edge in range(1, 19):
            self.step(model, av=int(edge <= 16), bv=int(edge <= 16), a="0002", b="0003")
            self.assertEqual(model.count, max(0, edge - 2))
            self.assertEqual(model.acc, 6 * max(0, edge - 2))
            self.assertEqual(model.done, int(edge == 18))

    def test_zero_is_a_valid_product(self):
        model = PEModel()
        self.step(model, av=1, bv=1)
        self.step(model)
        self.step(model)
        self.assertEqual((model.acc, model.count), (0, 1))

    def test_stall_holds_state_and_clear_overrides_stall(self):
        model = PEModel()
        self.step(model, av=1, bv=1, a="0003", b="0002")
        before = model.__dict__.copy()
        self.step(model, advance=0, mode="xx", av=1, bv=1, a="xxxx", b="zzzz")
        self.assertEqual(model.__dict__, before)
        self.step(model, clear=1, advance=0, av=1, bv=1)
        self.assertEqual(model.__dict__, PEModel().__dict__)

    def test_sixteen_extreme_products_fit_each_accumulator(self):
        for mode, width in WIDTHS.items():
            model = PEModel()
            value = -(1 << (width - 1))
            for _ in range(16):
                self.step(model, mode=f"{mode:02b}", av=1, bv=1,
                          a=f"{value & 65535:04x}", b=f"{value & 65535:04x}")
            self.step(model)
            self.step(model)
            self.assertEqual(model.acc, 16 * value * value)
            self.assertEqual(model.count, 16)

    def test_independent_valids_never_pair_across_cycles(self):
        model = PEModel()
        self.step(model, av=1, a="0002")
        self.step(model, bv=1, b="0003")
        self.step(model)
        self.step(model)
        self.assertEqual((model.acc, model.count), (0, 0))

    def test_error_is_sticky_and_pending_product_can_drain(self):
        model = PEModel()
        self.step(model, av=1, bv=1, a="0002", b="0003")
        self.step(model)
        self.step(model, mode="11", av=1)
        self.assertEqual((model.acc, model.count, model.stream_error), (6, 1, 1))
        self.step(model)
        self.assertEqual(model.stream_error, 1)
        self.step(model, rst_n=0, advance=0)
        self.assertEqual(model.__dict__, PEModel().__dict__)

    def test_pack_preserves_signed_results(self):
        model = PEModel()
        for kwargs in (dict(av=1, bv=1, a="000d", b="0005"), {}, {}):
            self.step(model, **kwargs)
        snapshot = model.snapshot(Inputs())
        self.assertEqual(unpack(pack(snapshot)), snapshot)


if __name__ == "__main__":
    unittest.main()
