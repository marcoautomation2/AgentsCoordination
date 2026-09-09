---
name: full-manual-checks
description: The deepest Fearless verification pass — align to upstream, run TestAllFrontendCoordinatorIntegration.java, run the full manager GUI test plan, then invent and perform one exploratory check nothing else covers. Use only when explicitly asked for it by name or for "the deepest possible check"; it takes well over an hour.
---

# Full manual checks

1. Align the seven repos to upstream (global CLAUDE.md, "Fearless").
2. From `Coordinator\test`:
   ```powershell
   & "C:\Program Files\Java\jdk-26.0.2\bin\java.exe" --module-path ..\..\Commons\Commons.jar --add-modules Commons mainCoordinator\TestAllFrontendCoordinatorIntegration.java
   ```
   If it fails, report and stop; don't fix it here.
3. Run the `run-manager-gui-tests` skill, the whole plan. Write any
   failure (expected vs actual, screenshots if useful) into
   `C:\data\tools\shared-docs\manager-gui-test-report.txt`, commit and push
   to `main`.
4. Invent one check nothing above covers. Read
   `C:\data\tools\shared-docs\fearless\exploratory-checks.txt` first
   (create it if missing) so successive checks broaden coverage: a
   malformed program the parser has never seen, a much larger or deeper
   project, an OS interaction, a manager workflow outside the GUI plan,
   something about the app-image itself. Perform it. If it passes, append a
   dated entry to that file, commit and push. If it finds a real problem,
   do not fix it and do not add a test on your own judgment: report it with
   enough detail to reproduce and let Marco decide how it becomes a
   regression test.
