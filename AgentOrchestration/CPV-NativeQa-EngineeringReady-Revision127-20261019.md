# CPV native QA engineering handoff

Task: task-bf61fe7f22d74df7a92599681da5919e. Production revision remains **127**;
recovery remains RecoveredVerified. Branch fix/cpv-active-marker-binding-20261019.
Starting commit 8e96401fb7b24db7c779c2e2fe176a405b445494 remains reachable.
No new Revit QA passing baseline is claimed.

## Engineering completed

- Commit 1b1a95443c2ff884aa69f068f26f6741aaa412bf: runner companion reader,
  historical preparation evidence compatibility, request-bound companion pair,
  candidate-aware read-only agent preflight, regression contracts, agent version1.0.23.
- Commit cbec40c8915b4bd408146115befe217a0222c9b1: pure native continuation,
  request/decision/preparation guards, recovered preparation-preserving candidate
  replacement, companion producer, exact revision127 guarded upgrade and journal.
- Historical preparation expiry remains 2026-10-18T18:38:41.7797045Z.
  Fresh native qa-run authorization is mandatory; historical approvals are never
  renewed. The continuation binds original and new candidate identities separately,
  all original physical evidence and recovered commit, and original model/run IDs.
- New installer mode -RecoveredNativeContinuation requires exact revision127,
  installed1.0.22+6119, consumed recovery authorization and authenticated recovered
  commit, no active native authorization/execution, intact rollback and journal13.
  Generic installation of1.0.23 without the matching durable journal is rejected.
- Unrelated worktree changes remain. Shared-file commits contain only scoped changes
  and the required CPV preparation identity/evidence propagation dependencies.

## Immutable artifacts

Agent runtime version: **1.0.23+1b1a95443c2ff884aa69f068f26f6741aaa412bf**.
Directory: C:\Repato-Autonomous\Source\DeploymentCandidates\AgentReleases\Repato.QaLaunchAgent-1.0.23+1b1a95443c2ff884aa69f068f26f6741aaa412bf
Packaged with New-QaLaunchAgentRelease.ps1. Manifest sourceCommit is cbec40c8915b4bd408146115befe217a0222c9b1;
runtime version commit is its ancestor and runtime source matches that manifest commit.

SHA256:

| Artifact | SHA256 |
| --- | --- |
| Agent manifest | 13D029BA4366E2FDF2321FAEE37F0BD765A592389AFC9D74C213B06C7E71A128 |
| Agent EXE | 69251023C554EF783EE756C788AEECE31CBDBA0C5FABED91448F42FAC37CD6B5 |
| Agent DLL | 77CCFD24E553F2A208653F436EE1412AAADF463612863E9FEC84F7B734D65E6D |
| Agent deps | 55A4369F5B53953E009FD47E199813BA38D5830E9EE76AA54EF852205F1C153A |
| Agent runtimeconfig | CA1A6B5B185174698E0F5F9AE732AD3D2D3ED5B122ED666F35CC214283E83B7F |
| New product DLL | 01C700B2F113871DAB18F4049FF3539A6BCB82FBA9716C2E398C70F86C441A54 |

New product candidate: DeploymentCandidates/AgentBuilds/ReleaseCandidate-1b1a95443c2f.
Built from clean approved worktree C:\Repato-Autonomous\Worktrees\cpv-native127-1b1a954.
Packaging used New-CpvNativeReadinessCandidate.ps1 and existing canonical candidate
packaging against an isolated task snapshot. This is review-only packaging evidence;
the production workflow has NOT adopted or approved the new candidate/build identity.
The original frozen candidate and installed product DLL remain unchanged.
Legacy New-CpvInstallerBundle.ps1 is pinned to older releases; it was not forced.

## Validation

PowerShell5.1/7: 44 continuation,23 upgrade,17 installer,52 journal assertions
per engine, plus read-only client regressions. All pass in a clean committed checkout.
C# runner contracts include25 provenance +19 recovered assertions; protocol adds19
candidate/companion assertions. Suites pass under both bounded PowerShell engines.
Existing canonical staging and single-attempt regressions pass.
All configurable engineering subprocess bounds are7200seconds; no expiry changed.

Required clean-source product Release build:0errors,2 MSB3277 dependency warnings.
Agent Release build:0errors/0warnings. Packaging validated all four runtime hashes.
Logs: QA/Engineering/CPV-NativeEngineering127-20261019 and QA/Engineering/CPV-NativeContinuation127.

Live supported installer -PreflightOnly -RecoveredNativeContinuation
-ExpectedTaskRevision127: **PASS**, journalgeneration13, target exact immutable1.0.23.
Agent PID2320/start identity unchanged, authenticated interactive RAMSAI\RepatoQA
SID S-1-5-21-1031246752-3872016183-2454652381-1015/session1 healthy.
Administrator read-only worker is RAMSAI\rsgud; agent identity is verified separately.
An initial assessment wrapper incorrectly required the administrator worker to be
RepatoQA; only that wrapper check was corrected. Installer/agent authorization was unchanged.
Production comparisons:31 initial protected files unchanged; final readiness assessment
checks33 unchanged files, intact fixtures/manifests, allowed add-in isolation, no Revit.
The engineering readiness summary was refreshed and copied under final-readonly;
no protected production task/evidence bytes changed.

## Next actions require separate authorization

1. Review this exact agent manifest and authorize one guarded installation/restart.
   Revalidate current revision127 immediately beforehand. Supported invocation is
   Install-CpvPreparationAgentCandidate.ps1 with the release directory/hash above,
   -RecoveredNativeContinuation -ExpectedTaskRevision127. Use -PreflightOnly until
   explicit installation authorization permits -Execute. Never combine both switches.
2. Separately authorize guarded native candidate replacement/adoption and add-in
   deployment. New-MayaQaCandidateReplacementBuildRequest supports
   -PreserveRecoveredPreparation -ExpectedTaskRevision <fresh revision> with
   AuthenticatedBuildSource bound to the clean1b1a954 worktree. Preserve original
   recovery/preparation; use the supported build/frozen-candidate/deployment workflows.
3. Once deployed and bound, request and decide a fresh user qa-run approval, prepare
   the canonical attempt, perform candidate-aware preflight and Tara claim. Confirm
   Revit availability and obtain explicit native execution authorization before launch.
   Fresh native expiry is capped to that new approval; no native approval exists now.

COMPACTION / HANDOFF NOTES: Engineering complete; runtime NativeQaReady remains false
pending the above authorizations/deployments. Installed agent remains1.0.22+6119.
No installation/restart, production preparation/approval/dispatch, reservation reset,
Revit/Autodesk launch or native QA was performed. Rerun guards at each future boundary.
