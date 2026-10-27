# Precision-Configurable Single-PE RTL

This folder contains 19 Verilog source files implementing one signed,
precision-configurable systolic processing element (PE). It supports INT4,
INT8 and INT16 multiplication and accumulates sixteen products per frame.

The PE forwards registered A operands to the right and B operands downward.
Its accumulated result stays local: this is an output-stationary design.
The sixteen multiplier tiles inside ONE PE are separate from the planned
16x16 array of PEs. Full-array integration is a subsequent milestone.

## Main modules

| Use | Top module |
| --- | --- |
| Complete PE with A/B forwarding | `systolic_pe_signed` |
| Registered MAC without A/B forwarding registers | `tiled_mac_signed` |
| Combinational signed multiplier | `tiled_multiplier_signed` |

## Source files

| File | Module | Purpose |
| --- | --- | --- |
| `unsigned_basic_4bit_multiplier.v` | `basic_unsigned_4x4` | Unsigned 4x4 multiplication using `*` |
| `unsigned_hsm_4bit_multiplier.v` | `hsm_unsigned_4x4` | Unsigned 4x4 multiplication using squares and parity correction |
| `precision_decode_mag.v` | `precision_decode_mag` | Interpret signed operands and produce magnitudes and a sign flag |
| `tile_enable_decode.v` | `tile_enable_decode` | Select the required 1, 4 or 16 tiles |
| `tile4_unsigned.v` | `tile4_unsigned` | Select BASIC/HSM at elaboration and isolate disabled tile inputs |
| `tile_product_bank.v` | `tile_product_bank` | Instantiate sixteen tiles and align their product rows |
| `csa_3to2.v` | `csa_3to2` | Reduce three 32-bit rows to sum and unshifted carry rows |
| `csa_tree_16x32.v` | `csa_tree_16x32` | Local/shared reduction with precision-dependent isolation and bypasses |
| `precision_final_adder.v` | `precision_final_adder` | Add the selected CSA rows to form the magnitude product |
| `precision_sign_restore.v` | `precision_sign_restore` | Restore the sign and format the signed 32-bit product |
| `tiled_multiplier_signed.v` | `tiled_multiplier_signed` | Connect the complete combinational multiplier |
| `precision_product_register.v` | `precision_product_register` | Store the product, precision and valid bit |
| `cla4.v` | `cla4` | Four-bit carry-lookahead adder with group generate/propagate |
| `cla_prefix_36.v` | `cla_prefix_36` | Nine four-bit CLAs connected by a parallel carry-prefix network |
| `precision_accumulator_adder.v` | `precision_accumulator_adder` | Extend the product and perform precision-controlled accumulation addition |
| `precision_accumulator.v` | `precision_accumulator` | Store the running sum, frame mode, term count and completion/error status |
| `tiled_mac_signed.v` | `tiled_mac_signed` | Connect multiplier, product register and accumulator with admission control |
| `precision_operand_register.v` | `precision_operand_register` | Store one A or B operand together with its mode and valid bit |
| `systolic_pe_signed.v` | `systolic_pe_signed` | Connect two operand registers and the MAC into one complete PE |

The HSM file also contains `hsm4_square_4bit` and `hsm4_rom_square_2bit`.
Do not add duplicate copies of these helpers. The two tile filenames differ
from their module names; use module names when choosing an elaboration top.

## Runtime precision modes

| Precision | `mode` | Enabled tiles | Signed product bits | Accumulator bits | Active four-bit CLAs |
| --- | --- | --- | --- | --- | --- |
| INT4 | `00` | 1 | 8 | 12 | 3 |
| INT8 | `01` | 4 | 16 | 20 | 5 |
| INT16 | `10` | 16 | 32 | 36 | 9 |

A/B ports remain 16 bits wide. INT4 interprets bits [3:0] as signed, INT8
interprets bits [7:0] as signed, and INT16 uses all sixteen bits. Upper input
bits are ignored in narrow modes. Product and accumulator output buses remain
signed 32-bit and 36-bit buses, with sign extension as needed. Accumulator
widths support sixteen signed products accumulated from zero.

Mode `11` is reserved. A valid operand token using it raises a PE protocol error.

## BASIC versus HSM

`USE_HSM` is an elaboration-time parameter, independent of runtime `mode`:

- `USE_HSM=0`: BASIC tiles, selected for the current PE architecture.
- `USE_HSM=1`: HSM tiles, retained for comparison.

The supplied parameter default is **1**. Explicitly override it to **0** on
the PE, MAC or multiplier top when building BASIC. The value propagates to all
tiles; both architectures are not instantiated together inside one tile.

For HSM unsigned tile inputs:

- `p = floor((a+b)/2)`
- `q = floor(abs(a-b)/2)`
- `correction = min(a,b)` when input parity differs, otherwise zero
- `product = p*p - q*q + correction`

The squarer splits `value = 4*k + r` and uses
`value*value = 16*k*k + 8*k*r + r*r`. ROM-style case statements describe
combinational lookup logic; a physical memory macro is not required.

## Multiplier reduction

Each tile produces eight bits. Fixed wiring zero-extends and shifts that
product into one weighted 32-bit row. `partial_products[511:0]` packs sixteen
separate rows; it is a wire bus, not a 512-bit storage register.

The local groups contain tiles `{0,1,4,5}`, `{2,3,6,7}`, `{8,9,12,13}` and
`{10,11,14,15}`. Each group uses two CSAs. Six shared CSAs reduce the eight
local output rows to two, following `8 -> 6 -> 4 -> 3 -> 2`.

- INT4 bypasses every CSA and both sections of the final CPA.
- INT8 uses group 0's two local CSAs and the lower 16-bit CPA section.
- INT16 uses all fourteen CSAs and both 16-bit CPA sections.

CSA carry outputs are unshifted: `total = sum + (carry << 1)`. Align each carry
once at its receiving stage. The 32-bit reduction interfaces rely on the
nonnegative tile-product total fitting in 32 bits; they do not support
arbitrary overflowing sums of sixteen 32-bit inputs.

The CSA tree must have `mode` and `enable` input ports, as connected by
`tiled_multiplier_signed`. The older tree without those ports is incompatible
with this multiplier top.

## PE datapath and control

1. A/B operand registers capture inputs, precision and independent valid bits.
2. Their outputs feed the local multiplier and the neighbouring PEs.
3. The product register captures an accepted product and its mode/valid metadata.
4. The accumulator adder adds the stored product to the previous local sum.
5. The accumulator register stores the new sum and feeds it back to the adder.

Common controls are `clk`, active-low asynchronous `rst_n`, synchronous `clear`
and pipeline step enable `advance`. Clear has priority over advance. Stalls hold
pipeline state. Advancing bubbles clear operand/product valid bits while
holding their data; the accumulator retains its running sum.

The PE accepts up to sixteen matching pairs per frame. Precision stays
consistent within a frame; clear/reset starts a new frame. `term_count` counts
consumed products. `result_valid` stays asserted after the sixteenth consumed
product until clear/reset. `protocol_error` is sticky; a result with this flag
asserted is invalid.

Starting from clear, edge 1 captures the first A/B pair, edge 2 captures its
product, and edge 3 accumulates it. Sixteen uninterrupted external pairs finish
on advancing edge 18. Continue advancing with invalid inputs after the last
pair to drain the pipeline.

Forwarding links have no independent ready/retry handshake. Connected PEs share
clock, reset, clear and advance. The array input schedule must align matching
A/B tokens. One-sided valid streams during fill/drain are supported.

## Switching-reduction techniques

- Operand isolation holds disabled multiplier and CSA inputs at zero.
- Precision selection bypasses unused reduction paths and adder sections.
- The accumulator masks unused CLA operands and cuts carry-prefix
  generate/propagate paths at active-to-inactive boundaries.
- Register write enables retain unused precision slices.

The RTL does not explicitly instantiate clock-gating cells or power gates.
Register enables do not by themselves stop the clock network. Power comparisons
require representative switching activity and identical synthesis conditions.

## Verification and remaining integration

Local verification completed includes exhaustive 256-pair BASIC/HSM unsigned
tile tests, block-level tests, single-PE Python/RTL comparison over 90 completed
sixteen-term frames, and a 2x2 PE connection test. Single-PE checks include
resets, clear, stalls, bubbles, operand forwarding and protocol errors.

The committed unsigned-tile bench is `tb/unsigned_4bit_multiplier_tb.v`.
Upload the additional PE/block testbenches, vector generator and required input
files alongside the RTL to make the complete local verification reproducible.
RTL sources alone do not provide those simulation inputs.

Full 16x16 array integration, input sequencing and full-array verification
remain subsequent milestones. Per-precision activity-based power analysis is
also pending; preliminary synthesis power is not a measured power-saving result.
