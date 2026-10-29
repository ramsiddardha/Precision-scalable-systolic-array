# Precision-scalable processing-element RTL

This folder contains **20 Verilog source files defining 22 modules** for one signed, output-stationary systolic processing element (PE). The PE forwards A to the right and B downward, multiplies aligned operand pairs, and accumulates a sixteen-term dot product.

The design supports INT4, INT8 and INT16 operands. Precision controls which multiplier tiles, reduction sections, adder slices and register-bank clocks are active.

**PE top module:** [systolic_pe_signed](systolic_pe_signed.v).

This source set implements the single-PE datapath. A complete 16x16 array additionally needs the array interconnect, boundary scheduling and controller.

## Precision modes

| Mode | Operand range | Enabled 4x4 tiles | Active product bits | Active accumulator bits |
| --- | --- | --- | --- | --- |
| `2'b00` — INT4 | -8 to 7 | 1 | 8 | 12 |
| `2'b01` — INT8 | -128 to 127 | 4 | 16 | 20 |
| `2'b10` — INT16 | -32768 to 32767 | 16 | 32 | 36 |
| `2'b11` | Reserved | 0 | Inactive | No valid operation |

Operands arrive on 16-bit buses. Only the selected low 4, 8 or 16 bits determine the signed input value. Products are sign-extended onto a common 32-bit bus; accumulated results are sign-extended onto a common 36-bit bus.

For sixteen products, the selected accumulator width is `2*operand_width + 4`.

Keep one precision mode for a complete frame and its pipeline drain. Clear or reset the PE before starting the next frame.

## How the datapath works

1. **Capture and forward:** two `precision_operand_register` instances store A and B independently, with their precision and valid bits.
2. **Decode signed inputs:** `precision_decode_mag` produces unsigned magnitudes and the product sign.
3. **Multiply chunks:** `tile_product_bank` instantiates sixteen unsigned 4x4 tiles; precision enables 1, 4 or 16 of them.
4. **Reduce weighted rows:** `csa_tree_16x32` selects a precision-dependent reduction path. `precision_final_adder` combines its sum and carry rows.
5. **Restore the product sign:** `precision_sign_restore` reconstructs the signed product, which enters `precision_product_register`.
6. **Accumulate:** `precision_accumulator` adds each registered product using `precision_accumulator_adder` and the CLA/prefix network.

The operand registers also drive the forwarding outputs. The MAC sees their previously registered values at each advancing edge while those registers capture the next hop.

## Source-file guide

| File | Defined module(s) | Purpose |
| --- | --- | --- |
| [systolic_pe_signed.v](systolic_pe_signed.v) | `systolic_pe_signed` | PE top: forwarding, paired-operand handling, MAC and stream-error reporting |
| [tiled_mac_signed.v](tiled_mac_signed.v) | `tiled_mac_signed` | Multiplier, product pipeline, frame admission and accumulator |
| [tiled_multiplier_signed.v](tiled_multiplier_signed.v) | `tiled_multiplier_signed` | Combinational signed multiplier top |
| [precision_operand_register.v](precision_operand_register.v) | `precision_operand_register` | Precision-aware registered A/B forwarding hop |
| [precision_product_register.v](precision_product_register.v) | `precision_product_register` | Product pipeline storage, precision and valid tracking |
| [precision_accumulator.v](precision_accumulator.v) | `precision_accumulator` | Clock-gated sum storage, term count, completion and error state |
| [precision_accumulator_adder.v](precision_accumulator_adder.v) | `precision_accumulator_adder` | Signed product extension and precision-dependent accumulator addition |
| [cla_prefix_36.v](cla_prefix_36.v) | `cla_prefix_36` | Nine 4-bit CLA slices with a parallel block-prefix carry network |
| [cla4.v](cla4.v) | `cla4` | Four-bit carry-lookahead adder with group generate/propagate outputs |
| [precision_decode_mag.v](precision_decode_mag.v) | `precision_decode_mag` | Decode operand signs and form unsigned magnitudes |
| [tile_enable_decode.v](tile_enable_decode.v) | `tile_enable_decode` | Select the required multiplier tiles |
| [tile_product_bank.v](tile_product_bank.v) | `tile_product_bank` | Sixteen tiles and their sixteen weighted 32-bit product rows |
| [tile4_unsigned.v](tile4_unsigned.v) | `tile4_unsigned` | Operand-isolated tile wrapper; selects BASIC or HSM at elaboration |
| [unsigned_basic_4bit_multiplier.v](unsigned_basic_4bit_multiplier.v) | `basic_unsigned_4x4` | Unsigned 4x4 multiplication using the Verilog `*` operator |
| [unsigned_hsm_4bit_multiplier.v](unsigned_hsm_4bit_multiplier.v) | `hsm_unsigned_4x4`, `hsm4_square_4bit`, `hsm4_rom_square_2bit` | HSM tile and its two helper modules |
| [csa_3to2.v](csa_3to2.v) | `csa_3to2` | Parameterized three-input carry-save compressor; default width 32 |
| [csa_tree_16x32.v](csa_tree_16x32.v) | `csa_tree_16x32` | Local quadrant reduction and shared CSA reduction |
| [precision_final_adder.v](precision_final_adder.v) | `precision_final_adder` | Reconstruct unsigned product magnitude from the CSA outputs |
| [precision_sign_restore.v](precision_sign_restore.v) | `precision_sign_restore` | Conditional negation and signed product formatting |
| [precision_icg.v](precision_icg.v) | `precision_icg` | Low-phase enable latch and gated-clock generation |

The uploaded file `csa_3to2(1).v` is stored here as `csa_3to2.v`. Its source contents are preserved. The other source filenames are retained.

The HSM file already defines its squarer helpers. Compile it once; separate duplicate definitions of those helpers are unnecessary.

## Choosing BASIC or HSM

`USE_HSM` is an **elaboration-time parameter**:

| Value | Tile implementation |
| --- | --- |
| `0` | BASIC unsigned 4x4 |
| `1` | HSM unsigned 4x4 |

The PE and MAC tops default to **BASIC** (`USE_HSM=0`). The standalone multiplier, tile bank and tile wrapper default to **HSM** (`USE_HSM=1`). Set the parameter explicitly when comparing implementations.

The PE passes its chosen value down through the MAC and multiplier to the tile instances. Runtime `mode` changes operand precision; it does not switch between BASIC and HSM architectures.

## PE interface and frame control

| Signal | Meaning |
| --- | --- |
| `clk` | Common source clock |
| `rst_n` | Asynchronous, active-low reset |
| `clear` | Synchronous frame reset; clears pending data, accumulator and diagnostics, including during an advance stall |
| `advance` | Global pipeline/forwarding progress control; deasserting it holds normal pipeline state |
| `mode[1:0]` | Operand precision for the frame |
| `a_in[15:0]`, `b_in[15:0]` | Incoming operand buses |
| `a_valid_in`, `b_valid_in` | Independent valid tokens; both must align for a local multiplication |
| `a_out[15:0]`, `b_out[15:0]` | Registered, sign-extended forwarding outputs |
| `a_valid_out`, `b_valid_out` | Forwarded valid tokens |
| `acc_q[35:0]` | Current signed accumulated result |
| `acc_mode_q[1:0]` | Precision established by consumed products |
| `term_count[4:0]` | Number of products accumulated, from 0 through 16 |
| `result_valid` | High after sixteen products have accumulated; stays high until clear/reset |
| `protocol_error` | Sticky frame-error indication; clear/reset starts recovery |
| `tile_enabled[15:0]` | Currently activated multiplier tiles, not a stored frame-mode mask |

All connected PEs and boundary sources share `clk`, `rst_n`, `advance` and `clear`. Forwarding links have no independent ready/backpressure signal; upstream scheduling must align corresponding A/B terms.

A one-sided valid token during array fill or drain is legal and does not create a product. The stream checks diagnose invalid precision on valid inputs, mismatched paired modes, or an aligned pair the MAC cannot accept, such as an extra term.

After a stream error, further local pairs are blocked until clear/reset. Legal forwarding continues, and a product already stored in the pipeline may still drain. Treat a result with `protocol_error=1` as invalid.

## Pipeline timing

Starting from a cleared PE, with stable legal controls and `advance=1`:

| Advancing edge | First operand pair's progress |
| --- | --- |
| 1 | A1/B1 enter the operand registers |
| 2 | Product 1 enters the product register |
| 3 | Product 1 is added to the accumulator |
| 18 | The sixteenth product is accumulated after sixteen consecutive external operand pairs |

After the last input pair, continue advancing with invalid inputs for **two drain edges**. Stalls increase elapsed clock cycles; advancing edges describe pipeline progress.

Drive input data, mode, valid and control signals before the sampling edge. The clock-gating enables are captured while `clk` is low.

The standalone MAC has no A/B forwarding stage. Its final stored product needs one further advancing edge after the last accepted MAC input.

## Precision-dependent activity reduction

- **Operand isolation:** disabled tiles receive zero operands; an inactive multiplier blocks input changes before signed decoding.
- **Tile selection:** INT4 uses mask `16'h0001`; INT8 uses `16'h0033` (tiles 0, 1, 4 and 5); INT16 uses `16'hFFFF`.
- **Reduction bypass:** INT4 bypasses the CSA network. INT8 uses the first local quadrant and bypasses the shared tree. INT16 uses all four local quadrants and the shared tree.
- **Final-product addition:** INT4 bypasses the final adder; INT8 uses its lower 16-bit section; INT16 uses both 16-bit sections.
- **Accumulator isolation:** INT4, INT8 and INT16 activate 3, 5 and 9 four-bit CLA slices. Generate/propagate boundaries are cut before unused upper slices.
- **Register clock gating:** operand, product and accumulator storage is divided into precision-dependent banks.
- **INT4 guard-field gating:** the accumulator's upper four bits of the 12-bit low bank update only when an 8-bit carry/borrow changes that field.

`precision_icg` intentionally describes a latch: it captures an enable while the source clock is low and holds it through the high phase. Register banks retain asynchronous reset. The mapped implementation may use latch/AND logic or a recognized library clock-gating cell; inspect synthesis results to identify the actual mapping.

These mechanisms reduce unnecessary activity. Quantified area, timing and power comparisons require reports for the matching RTL, constraints, library corner and switching activity.

## Arithmetic conventions

- Tile `t = 4*i + j` multiplies magnitude chunks `A[i]` and `B[j]`. Its eight-bit result is widened and shifted by `4*(i+j)`, producing one weighted 32-bit row.
- `partial_products` is a **512-bit bus containing sixteen weighted 32-bit rows**. It is wider than the sixteen raw eight-bit tile outputs.
- CSA carry outputs are **unshifted**: `x + y + z = sum + 2*carry`. Each next stage aligns the incoming carry exactly once.
- The reduction tree contains eight local CSAs and six shared CSAs. Its width assumptions apply to valid weighted tile products.
- The HSM square lookup is combinational ROM-style RTL. It does not require a physical memory macro.
- `precision_accumulator_adder` defaults to signed output formatting. Its `RAW_RESULT=1` option is used internally by the accumulator, which formats the external result after storage.

## Compile the PE

From the repository root, with Icarus Verilog installed:

```bash
mkdir -p build
for rtl_arch in 0 1; do
  iverilog -g2012 -s systolic_pe_signed \
    -P systolic_pe_signed.USE_HSM=$rtl_arch \
    -o build/pe_$rtl_arch.vvp rtl/*.v
done
```

This elaborates BASIC and HSM versions of the PE. It does not apply stimulus or establish functional correctness. Add the matching project testbench and its vector/include files for simulation.

For a design-source import, add the 20 Verilog files once and select `systolic_pe_signed` as the design top. Testbenches belong in the simulator's test sources.

## Verification and synthesis scope

Keep testbenches in [tb/](../tb/), software reference calculations in [reference_model/](../reference_model/), and selected results in [reports/](../reports/).

For verification, compare signed products, running sums, forwarding, valid timing, stalls, reset/clear and protocol diagnostics. A previous passing result applies to its recorded source revision and stimulus; rerun the relevant regression after source changes.

For synthesis, use the PE top for the registered implementation or `tiled_multiplier_signed` for a combinational multiplier study. Set `USE_HSM` explicitly, and apply constraints for the chosen top, including the source and generated clocks as required by the flow.

The 300 MHz project target and any power-saving claim must be supported by the corresponding synthesis and activity-based power results.
