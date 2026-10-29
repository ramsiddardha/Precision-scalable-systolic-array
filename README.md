# Precision-Scalable 16×16 Systolic Tensor Unit

VLSI Design Laboratory project at IIT Delhi, supporting signed INT4, INT8 and INT16 arithmetic.

## Current milestone

The optimized BASIC single processing element is implemented and verified against Python using Vivado XSim.

The repository contains 20 RTL modules covering operand forwarding, the tiled multiplier, product register, accumulator, precision control and clock gating.

The complete 16×16 array is a separate implementation and verification milestone.

## Single-PE architecture

- Top module: `systolic_pe_signed`
- Validated configuration: `USE_HSM=0` selects BASIC tiles
- Runtime modes: `00` INT4, `01` INT8, `10` INT16
- Multiplier: sixteen unsigned 4×4 tiles with precision-dependent enables
- Pipeline: operand registers, product register and accumulator
- Frame: sixteen accumulated products
- Control: reset, clear, global advance, independent operand valids and protocol-error reporting

## Verification results

Completed full-profile Vivado/Python run, seed `20261029`:

| Metric | Result |
|---|---:|
| Clocked cycles | 100,408 |
| Pre/post comparisons | 200,816 |
| Product and running-sum comparisons | 81,440 |
| High-phase state-hold checks | 3,478 |
| Complete legal frames | 5,082 |
| Mismatched samples | 0 |
| Overall result | PASS |

| Precision | Unique operand pairs checked | Complete legal frames |
|---|---:|---:|
| INT4 | 256 / 256 | 130 |
| INT8 | 65,536 / 65,536 | 4,210 |
| INT16 | 11,643 sampled pairs | 742 |

INT4/INT8 operand-pair coverage is exhaustive. INT16 pairs and complete 16-term sequences are not exhaustive.

[Recorded results](reports/verification/single_pe/2026-10-29/)

## Run single-PE verification

Run Python commands from the repository root.

### 1. Generate inputs and expected values

```powershell
python verification/generate_vectors.py --profile full
```

### 2. Run the SystemVerilog testbench in Vivado

Follow the [Vivado setup instructions](verification/README.md).

### 3. Compare the saved RTL results

```powershell
python verification/compare_results.py
```

Expected successful message:

```text
PYTHON vs RTL: PASS
```

### Python reference-model checks

```powershell
python -m unittest discover -s tests -v
```

## Repository organization

| Location | Contents |
|---|---|
| `rtl/` | Synthesizable single-PE design |
| `tb/` | Hardware testbenches |
| `verification/` | PE cycle model, vector generator, comparator and Vivado helper |
| `reference_model/` | Earlier matrix arithmetic reference model |
| `tests/` | PE reference-model and checker tests |
| `reports/` | Selected verification and implementation results |
| `docs/` | Architecture and verification explanations |
| `synthesis/` | Synthesis-flow documentation |
| `run_verification.py` | Optional automated Icarus verification runner |

The generator creates `vectors/` locally. Simulation and comparison produce outputs in `results/`.

## Further reading

- [RTL documentation](rtl/README.md)
- [Testbench documentation](tb/README.md)
- [Single-PE verification explanation](docs/VERIFICATION_EXPLAINED.md)
- [Matrix reference model](reference_model/README.md)
- [Synthesis documentation](synthesis/README.md)

## Timing and power

The project targets 300 MHz. Functional verification checks arithmetic and cycle behavior. Timing and power measurements require the corresponding synthesis constraints, libraries, activity and Genus reports.

## Team

- Ram Siddardha Tammireddi
- Pruthvi Raj L.

Guides: Prof. Kaushik Saha and Prof. Jayadeva.
