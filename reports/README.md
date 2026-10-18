# Verification and implementation results

Record results for an identified source revision and configuration. Keep concise
summaries and selected text evidence here; use ignored run folders for generated
projects, waveforms and binary databases.

## Available evidence

| Record | Scope | Outcome |
| --- | --- | --- |
| [18 October verification](verification/2026-10-18.md) | Python reference model and unsigned 4x4 tile candidates | 13 Python tests and 256 RTL input pairs passed |

No mapped area, timing or power report for these exact repository sources is
included yet. Earlier experiments should be added only with their matching RTL,
constraints, configuration and tool reports so their scope can be understood.

## When adding synthesis results

Record the source commit and top/parameters, tool version, cell library and
corner, constraints, reported units, pipeline structure, cell count, area and
timing slack. For power, also record the precision, workload, clock rate,
activity source and annotation coverage.

Use matching conditions for comparisons. Identify reports without representative
activity as preliminary estimates. Avoid presenting a cell count as transistor
count or treating a combinational block's delay as a complete PE's clock result.

## Suggested result-table fields

| Configuration | Mode/workload | Cell area/unit | Cell count | Slack/period | Power/unit and activity method |
| --- | --- | --- | --- | --- | --- |
| Fill from an actual run | Record inputs | Record library units | Record mapped cells | Record both values | State whether estimated or activity-annotated |
