# Single-PE Verification

Python-backed verification of `systolic_pe_signed` using BASIC tiles (`USE_HSM=0`).

Run the Python commands from the repository root.

## 1. Generate inputs and expected values

```powershell
python verification/generate_vectors.py --profile full
```

## 2. Simulate in Vivado

Open a fresh Vivado RTL project. In the Tcl Console, run the following, replacing the example path with your local repository path:

```tcl
source {C:/path/to/repository/verification/setup_pe_python_vivado.tcl}
pe_run_python
```

## 3. Compare the saved RTL results

```powershell
python verification/compare_results.py
```

A successful run prints `PYTHON vs RTL: PASS`.

Generated vectors go into `vectors/`. Simulation outputs and comparison reports go into `results/`.

## Documentation

- [Verification explanation](../docs/VERIFICATION_EXPLAINED.md)
- [Recorded passing run](../reports/verification/single_pe/2026-10-29/)

The matrix reference model in `reference_model/` is separate from this PE cycle model.
