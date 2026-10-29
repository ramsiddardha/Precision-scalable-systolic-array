"""Independent integer/token model of the public single-PE contract.

This model uses Python's signed integers for multiplication and addition. It
does not reproduce the tile multiplier, CSA tree, CLA, storage slices or gates.
Only the three pipeline stages and the documented admission rules are modeled.
"""

from dataclasses import dataclass


WIDTHS = {0: 4, 1: 8, 2: 16}
TILE_MASKS = {0: 0x0001, 1: 0x0033, 2: 0xFFFF}
# High to low in both the Python and SystemVerilog comparison bus.
FIELDS = (
    ("a_out", 16), ("b_out", 16),
    ("a_valid_out", 1), ("b_valid_out", 1),
    ("acc_q", 36), ("acc_mode_q", 2), ("term_count", 5),
    ("result_valid", 1), ("protocol_error", 1),
    ("product_q", 32), ("product_mode_q", 2), ("product_valid_q", 1),
    ("a_mode_q", 2), ("b_mode_q", 2),
    ("tile_enabled", 16), ("multiplier_product", 32),
)
PACK_BITS = sum(width for _, width in FIELDS)
PACK_HEX = (PACK_BITS + 3) // 4
STATE_BITS = PACK_BITS - 48


def signed(value, width):
    """Interpret the low width bits as a signed two's-complement integer."""
    value &= (1 << width) - 1
    return value - (1 << width) if value & (1 << (width - 1)) else value


def selected_mode(bits):
    # A reserved or four-state mode is deliberately invalid.
    return {"00": 0, "01": 1, "10": 2}.get(bits.lower())


def operand(word, mode):
    width = WIDTHS[mode]
    low_digits = word.lower()[-(width // 4):]
    if any(c in low_digits for c in "xz"):
        raise ValueError("Unknown bits in an ACTIVE operand field are outside this oracle's scope")
    return signed(int(low_digits, 16), width)


def pack(values):
    result = 0
    for name, width in FIELDS:
        result = (result << width) | (int(values[name]) & ((1 << width) - 1))
    return result


def unpack(value):
    result = {}
    for name, width in reversed(FIELDS):
        result[name] = value & ((1 << width) - 1)
        value >>= width
    for name, width in (("a_out", 16), ("b_out", 16), ("acc_q", 36),
                        ("product_q", 32), ("multiplier_product", 32)):
        result[name] = signed(result[name], width)
    return result


@dataclass(frozen=True)
class Inputs:
    rst_n: int = 1
    clear: int = 0
    advance: int = 1
    mode: str = "00"
    a: str = "0000"
    b: str = "0000"
    av: int = 0
    bv: int = 0


class PEModel:
    def __init__(self):
        self.reset()

    def reset(self):
        self.a = self.b = self.am = self.bm = self.av = self.bv = 0
        self.p = self.pm = self.pv = 0
        self.acc = self.acc_mode = self.count = 0
        self.done = self.stream_error = self.mac_error = 0

    def admission(self, inputs):
        frame_mode = self.acc_mode if self.count else self.pm if self.pv else None
        ready = (inputs.rst_n and not inputs.clear and inputs.advance
                 and self.am in WIDTHS and not self.mac_error
                 and self.count + self.pv < 16
                 and (frame_mode is None or frame_mode == self.am))
        paired = bool(self.av and self.bv)
        accepted = bool(paired and self.am == self.bm and not self.stream_error and ready)
        error_event = bool(((inputs.av or inputs.bv) and selected_mode(inputs.mode) is None)
                           or (paired and (self.am != self.bm or not ready)))
        return accepted, error_event

    def snapshot(self, inputs):
        accepted, _ = self.admission(inputs)
        return dict(
            a_out=self.a, b_out=self.b, a_valid_out=self.av, b_valid_out=self.bv,
            acc_q=self.acc, acc_mode_q=self.acc_mode, term_count=self.count,
            result_valid=self.done, protocol_error=self.stream_error or self.mac_error,
            product_q=self.p, product_mode_q=self.pm, product_valid_q=self.pv,
            a_mode_q=self.am, b_mode_q=self.bm,
            tile_enabled=TILE_MASKS[self.am] if accepted else 0,
            multiplier_product=self.a * self.b if accepted else 0,
        )

    def apply_async_reset(self, inputs):
        if not inputs.rst_n:
            self.reset()

    def edge(self, inputs):
        if not inputs.rst_n or inputs.clear:
            self.reset()
            return
        if not inputs.advance:
            return

        # All decisions use OLD token state, as in a synchronous pipeline.
        accepted, error_event = self.admission(inputs)
        new_product = self.a * self.b
        new_product_mode = self.am
        if self.pv:
            legal = (self.pm in WIDTHS and self.count < 16
                     and (self.count == 0 or self.pm == self.acc_mode))
            if legal:
                self.acc += self.p
                self.acc_mode = self.pm
                self.count += 1
                self.done = int(self.count == 16)
                acc_width = 2 * WIDTHS[self.acc_mode] + 4
                assert -(1 << (acc_width - 1)) <= self.acc < (1 << (acc_width - 1))
            else:
                self.mac_error = 1
        self.pv = int(accepted)
        if accepted:
            self.p, self.pm = new_product, new_product_mode
        self.stream_error |= int(error_event)

        mode = selected_mode(inputs.mode)
        self.av = int(bool(inputs.av and mode is not None))
        self.bv = int(bool(inputs.bv and mode is not None))
        if self.av:
            self.a, self.am = operand(inputs.a, mode), mode
        if self.bv:
            self.b, self.bm = operand(inputs.b, mode), mode
