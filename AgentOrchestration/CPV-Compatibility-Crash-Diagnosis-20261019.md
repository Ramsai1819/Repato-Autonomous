# CPV synthetic test crash diagnosis

The captured engineering run failed with System.IO.InvalidDataException:
completed-recovery-historical-sidecar-missing. Stack: RecoverCompleted in
QaLaunchAgent/CpvPreparation.cs:308, Handle:99, top-level contract Program.cs:169
(line numbers at failure, before subsequent edits). CompletedRecoveryCase("valid")
omitted the historical sidecar newly required by the preservation contract. The
source-only-specific test created its own sidecar; the general factory did not.
The factory now creates exact historical source-only evidence. The missing-history
negative test explicitly verifies the exception type/message. This was a synthetic
fixture regression, not an observed production integrity violation or dependency issue.

The Windows exception 0xe0434352 is a managed-exception envelope. Read-only Windows
inspection found three older .NET Runtime 1026 events for this executable:
- 2026-10-19 15:01:29 +05:30 (record108879) and 14:37:11 (record108862):
  InvalidDataException completed-recovery-path-or-process-evidence-invalid,
  RecoverCompleted:293 -> Handle:98 -> Program:150.
- 12:29:34 (record108815): InvalidDataException reconciliation-model-hash-mismatch,
  synthetic Boundary.ValidateReconciliation:159 -> RecoverCompleted:285 ->
  Handle:93 -> Program:135.
Those older records cannot be correlated to the newly captured missing-sidecar
failure; do not conflate them or infer a production violation. Relevant event text
was saved to QA/Engineering/CPV-Compatibility-20261019/dotnet-events.json. The
queried Application Error/WER events and CPV-named WER report directories contained
no additional matching report. No crash dump was available in the inspected local
CrashDumps location. A later process check found no CpvPreparation.ContractTests
or WerFault process; earlier PID20320 lock/access-denied reports are historical.

The harness now catches unexpected exceptions, writes the full exception/stack to
stderr and returns exit1, including cleanup errors. --verify-failure-reporting is
an isolated diagnostic probe: InvalidDataException synthetic-failure-reporting-probe,
normal exit1, rather than an unhandled process crash. Normal tests use dotnet DLL
execution from QA/SyntheticBuilds/CpvCompatibility, not the default apphost.

Invoke-CpvEngineeringProcess.ps1 captures stdout, stderr and exact exit status,
uses CreateNoWindow and a configurable timeout default/minimum of7200 seconds.
Its Windows PowerShell child uses the standard WindowsPS module paths: direct
Process.Start otherwise inherits PS7 modules and can fail to discover Get-FileHash.
This child-only environment correction changes no persistent policy or settings.
PowerShell tests use process-local RemoteSigned, never a persistent policy change.

Revalidation includes127 C# assertions under each PowerShell engine and an expected
exit1 failure-reporting probe. No production dispatch, reservation reset, new
approval, deployment/restart, protected evidence edit or Revit operation is part
of crash diagnosis or synthetic validation.
