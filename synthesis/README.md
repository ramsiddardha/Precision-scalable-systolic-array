# Synthesis and constraints

This directory is reserved for the reproducible Cadence Genus flow. No synthesis
script or PPA report for the current repository revision is included yet.

## Files to add with a synthesis milestone

| Planned location | Contents |
| --- | --- |
| `genus/` | Source-reading, elaboration, mapping and report scripts |
| `constraints/` | SDC files matched to the actual top-level ports |
| `local/` | Untracked machine-specific library paths/settings |

Keep the scripts and SDC in Git. Supply technology libraries separately in the
tool environment; the project `.gitignore` excludes Liberty files and databases.

## Record each configuration

- Source commit and top module, including elaboration parameters.
- Tool version, cell library, operating corner and reported units.
- Clock/reference period, input/output delays, uncertainty, slew and loads.
- Combinational or registered block, interface and pipeline stages.
- Area, cell count, timing slack and the relevant critical path.
- Power activity source, workload, precision, clock rate and annotation coverage.

The project target is 300 MHz, or a 3.333333 ns period. Combinational blocks need
interface timing assumptions; a complete registered PE needs its actual clock
and register paths. Preserve those distinctions in comparisons.

## Fair comparisons

Compare BASIC and HSM with matching surrounding logic, constraints, library and
workload. Compare precision modes using representative mode-specific activity.
Label power estimated without representative VCD/SAIF as preliminary.

Cell count is not transistor count. Report the quantities actually supplied by
the tool, and keep area units as reported by the selected library.

Store selected text reports and a concise comparison under [reports/](../reports/README.md).
Use local build/run directories for large regenerable outputs.
