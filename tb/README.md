# RTL testbenches

| Source file | Simulation top | Designs checked |
| --- | --- | --- |
| `unsigned_4bit_multiplier_tb.v` | `unsigned_4x4_compare_tb` | BASIC and HSM unsigned 4x4 tiles |

The testbench applies every A/B pair from 0..15: 16*16 = 256 combinations.
Both circuits receive the same input pair. Each is compared with an independent
repeated-addition expectation. Case inequality also catches unexpected X/Z bits.

The testbench's `#1` wait allows combinational events to settle; it does not
measure physical circuit delay or demonstrate a particular operating frequency.

## Vivado

1. Add both files from `rtl/` as **Design Sources**.
2. Add `unsigned_4bit_multiplier_tb.v` as a **Simulation Source**.
3. Set `unsigned_4x4_compare_tb` as the simulation top. The module name, rather
   than the filename, is used for this selection.
4. Run **Behavioral Simulation** and use **Run All** if needed.
5. Read the final status in the simulation log/Tcl Console.

Expected message:

```text
PASS: all 256 input pairs matched for BASIC and HSM.
```

This testbench is simulation code. Do not include it as a Genus design source.

## Icarus Verilog

From the repository root, with Icarus Verilog installed:

```bash
mkdir -p build
iverilog -g2012 -s unsigned_4x4_compare_tb -o build/tiles.vvp \
  rtl/unsigned_basic_4bit_multiplier.v \
  rtl/unsigned_hsm_4bit_multiplier.v \
  tb/unsigned_4bit_multiplier_tb.v
vvp build/tiles.vvp
```

The supplied GitHub Actions workflow runs these same functional checks after
upload. A hosted workflow run is distinct from the local verification record.

## Planned checks

The next decoder testbench will check signed interpretation, magnitudes, sign
flags and reserved mode. Later testbenches will check the shared multiplier
against Python-generated expectations, followed by MAC/PE pipeline control and
complete matrix outputs. These are separate verification milestones.
