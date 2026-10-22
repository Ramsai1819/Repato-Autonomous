# Authorized 1.0.22 installation stopped before mutation

Task task-bf61fe7f22d74df7a92599681da5919e remains revision122. Consumed reservation
acfd8643ed2846b8a43b98d3a74c3217 is intact. Branch remains
fix/cpv-active-marker-binding-20261019; starting commit for this deployment turn
5db4d3ed1cc6694f2910d6e8f6fe74f4f9e5da9b remains reachable. No passing Revit baseline
is claimed; unrelated worktree changes preserved.

User authorized exactly one guarded installation/restart of
1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa, immutable manifest SHA256
7612D0657CF6287381F30A470D2B511BBF281B56CC36A095322845982879D726.
That release remains unchanged and was NOT installed.

Fresh supported elevated WindowsPS5.1 PreflightOnly passed immediately before the
attempt: exact release provenance/hashes, current installed1.0.21 process/owner,
interactive authenticated RepatoQA SID/session1, revision122 consumed retained
reservation, correlated non-execution proof and snapshot, generation13 committed
journal, administrator permissions, no Revit. Reviewed installer/startup path only
starts the fixed Launch Agent listener; it does not dispatch recovery/native QA.

The authorization wrapper invoked the supported installer with Execute exactly
ONCE. It inherited Set-StrictMode Latest from my new wrapper and failed at installer
line38: if((Get-CpvRevitProcesses).Count). When no Revit process exists, a function
returning an empty array is unrolled to null; strict-mode .Count access throws
System.Management.Automation.PropertyNotFoundException, "The property 'Count'
cannot be found on this object. Verify that the property exists."

The wrapper introduced the strict-mode context; the existing installer expression
was not robust in that context. A read-only elevated PreflightOnly reproduction
confirmed the exact source line/stack. The error precedes journal creation, agent
stop or runtime mutation. No second installer Execute invocation was made.

Read-only outcome verification:
- Installed version remains1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f.
- Same PID11372, start2026-10-19T20:19:41.6798583+05:30, session1, exact executable
  path, process owner SID S-1-5-21-1031246752-3872016183-2454652381-1015.
- Authenticated named-pipe health Ready=true, UserInteractive=true, Ramsai\RepatoQA,
  same SID/session. Capability runtime version confirms1.0.21.
- Prior installed EXE SHA256
  41CC849A07A62C2C06AB7528F0CE3AF6D01D5B05C6D831E19F267A91B4DD79AD;
  DLL SHA256 E8856573A5230459F98E432E12BC95BFA6353E0036C534FFFB28EC4D9435502A.
  All four runtime files match the unchanged prior committed journal. They do not
  match the approved1.0.22 artifacts, because runtime replacement never happened.
- Journal unchanged: Committed, generation13, transaction
  233a5e5a1d24450f866a256dbce60198, candidate1.0.21, SHA256
  DFEDE7F8C34119C4E9CDD1B3A9D9CB89F34592010A263240A08515BDE261D698.
- All28 task/evidence/frozen/runtime/journal file hashes from fresh preflight remain
  unchanged. Separate24-file protected snapshot includes replay ledger and is also
  unchanged. Reservation/task records unchanged. No Revit process present, no
  Revit/native QA launch, no approval/reset/recovery dispatch, no agent restart.

Safe engineering correction completed without retry: installer now uses
@(Get-CpvRevitProcesses).Count and stores the later result with @(...). Strict-mode
regression extracts the actual helper/guard expressions from installer AST and
injects absent/present/unknown processes. Six assertions passed in WindowsPS5.1 and
PS7, including fail-closed unknown process evidence. No guard or expiry weakened.
No agent binary or immutable release artifact changed.

After correction, an elevated supported PreflightOnly under Set-StrictMode Latest
passed for the exact1.0.22 release and revision122 retained reservation. All28
protected/runtime files and the installed process remained unchanged. Evidence:
corrected-strict-preflight.complete, corrected-strict-preflight.stdout.log and
corrected-strict-preflight-protected.json. This was read-only; attempt count stays1.

Files introduced/changed this turn:
- Invoke-CpvAuthorizedAgent122Installation.ps1: exact release pins, fresh preflight,
  one invocation, persistent CreateNew authorization receipt, protected snapshots,
  bounded7200s child execution, no retry/recovery calls.
- Test-CpvAuthorizedInstall122OutcomeReadOnly.ps1: journal/runtime/owner/health/hash
  verification and read-only strict-mode failure reproduction.
- Install-CpvPreparationAgentCandidate.ps1: two empty-array compatibility edits.
- Test-CpvInstallerStrictEmptyProcesses.ps1: synthetic actual-AST regression.
- This handoff. Tooling commit is the commit introducing this file; runtime source
  remains6119aceaab0a34c3e0323089a29f1cefb2c14aaa.

Evidence directory: QA/Engineering/CPV-AuthorizedInstall-20261019-1.0.22-6119.
Key evidence: fresh-preflight.*, deployment-failure.json, read-only-outcome.json,
protected-before.json, protected-after-failure.json, ps51/ps7-strict-process-guards.*.
single-authorization-lease.json and installation-attempt-1.txt remain in place.
Never delete/reset/reuse these receipts to obtain another attempt.

COMPACTION / HANDOFF NOTES: InstallationAttempted=true; InstallationAttemptCount=1
(one Execute invocation, conservatively counted even though no mutation occurred).
Actual runtime replacements=0, restarts=0. Stop production mutation here. The
corrected installer needs fresh explicit authorization for another single attempt,
plus fresh guarded preflight; this turn's authorization is exhausted. Do not reuse
the consumed CPV approval, reset reservation, create approvals, dispatch recovery or
launch Revit. Do not follow the earlier handoff as if1.0.22 were already installed.
