# Project documentation

Read these pages in order:

1. [Architecture](architecture.md): the planned multiplier, MAC, PE and array.
2. [Verification](verification.md): what each model/test checks and what the counts mean.
3. [Roadmap](roadmap.md): current milestone and the next implementation steps.
4. [Results](../reports/README.md): recorded evidence for identified source revisions.

The top-level README introduces the project. Folder READMEs explain how to run
that part. These pages hold the detailed design explanation.

When adding a diagram, label whether it is the target architecture or an
implemented version. Record the source/reference for figures and literature.
Add presentation/report sources here when they are ready to share.

## Workflow for each new block

Write the interface and expected behavior, implement the RTL, add a testbench,
run the checks, record their outcome, and update the roadmap. Commit the related
changes together with a descriptive message, for example:

```text
Add signed precision decoder and boundary-value testbench
```

Use commit history for earlier versions instead of storing duplicate `final`,
`latest` or numbered copies of the same source.
