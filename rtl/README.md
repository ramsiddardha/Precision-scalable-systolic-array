# Synthesizable RTL

The current RTL implements two unsigned 4x4 multiplier candidates. Each accepts
inputs from 0 through 15 and produces an 8-bit product from 0 through 225.

| Source file | Module | Description |
| --- | --- | --- |
| `unsigned_basic_4bit_multiplier.v` | `basic_unsigned_4x4` | Direct multiplication using `*` |
| `unsigned_hsm_4bit_multiplier.v` | `hsm_unsigned_4x4` | Difference-of-squares multiplication with parity correction |
| Same HSM file | `hsm4_square_4bit` | Builds a 4-bit input's square from two 2-bit squares and a cross term |
| Same HSM file | `hsm4_rom_square_2bit` | Four-entry combinational square lookup |

The filenames and module names are different in the current sources; use the
module names above when choosing an elaboration top. The HSM helper modules are
already included in the HSM file. Do not add duplicate copies of them.

## HSM arithmetic

For unsigned inputs `a` and `b`:

- `p = floor((a+b)/2)`
- `q = floor(abs(a-b)/2)`
- `correction = min(a,b)` when input parity differs, otherwise zero
- `product = p*p - q*q + correction`

The four-bit squarer splits `value = 4*k + r` and reconstructs
`value*value = 16*k*k + 8*k*r + r*r`. Its small ROM-style `case` statements
describe combinational logic; the RTL does not require a physical memory macro.

## Verification

Both top-level tile candidates passed all 256 unsigned A/B pairs in the
[shared testbench](../tb/README.md). The expectation comes from repeated
addition, independently of the BASIC `*` expression and HSM identity.

## Next RTL blocks

1. Precision/sign decoder: interpret signed INT4/8/16 and form magnitudes.
2. Tile control and wrapper: select BASIC or HSM at elaboration and isolate
   unused tiles according to runtime precision.
3. Sixteen-tile multiplier: align products, perform CSA reduction, finish
   product reconstruction and restore the sign.
4. Registered MAC and PE: accumulate products and forward operands.
5. Systolic array and input sequencing.

These blocks are planned; the current two tile files do not implement the full
signed precision-scalable multiplier. See [architecture](../docs/architecture.md).
